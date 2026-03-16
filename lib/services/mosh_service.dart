import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:xterm/xterm.dart';

import '../crypto/mosh_pb.dart';
import '../crypto/mosh_transport.dart';
import '../crypto/ocb.dart';
import '../models/connection.dart';
import '../util/constants.dart';
import 'mosh_framebuffer.dart';
import 'package:native_udp/native_udp.dart';
import 'ssh_service.dart';

/// Mosh client implementation with full SSP protocol support.
///
/// Protocol flow:
/// 1. SSH exec `mosh-server new -s -c 256 -l LANG=en_US.UTF-8` on the remote
/// 2. Parse stdout for `MOSH CONNECT [port] [key]`
/// 3. Open UDP socket to remote on that port
/// 4. Exchange datagrams via SSP transport (protobuf + fragments + OCB3)
class MoshService {
  final SSHService _sshService;

  MoshService(this._sshService);

  /// Start a mosh session.
  Future<MoshSession> connect(Connection conn) async {
    // Step 1: SSH connect and exec mosh-server.
    final result = await _sshService.connect(conn);
    final client = result.targetClient;

    // Allocate PTY on exec like real mosh (-tt). This triggers PAM
    // which generates MOTD. The login shell displays it via hoststrings.
    final session = await client.execute(
      'mosh-server new -s -c 256 -l LANG=en_US.UTF-8 -l TERM=xterm-256color',
      pty: const SSHPtyConfig(type: 'xterm-256color'),
    );

    // Collect stdout to parse connection info.
    final stdout = StringBuffer();
    final stderr = StringBuffer();

    final stdoutDone = Completer<void>();
    final stderrDone = Completer<void>();

    session.stdout.listen(
      (data) => stdout.write(utf8.decode(data, allowMalformed: true)),
      onDone: () => stdoutDone.complete(),
    );
    session.stderr.listen(
      (data) => stderr.write(utf8.decode(data, allowMalformed: true)),
      onDone: () => stderrDone.complete(),
    );

    await Future.any([
      Future.wait([stdoutDone.future, stderrDone.future]),
      Future.delayed(const Duration(seconds: 10)),
    ]);

    session.close();
    client.close();
    result.jumpClient?.close();

    // Step 2: Parse MOSH CONNECT [port] [key].
    final output = stdout.toString() + stderr.toString();
    final match = RegExp(
      r'MOSH CONNECT (\d+) ([A-Za-z0-9/+]+={0,2})',
    ).firstMatch(output);
    if (match == null) {
      throw MoshException(
        'mosh-server did not return connection info.\n'
        'Is mosh-server installed on the remote? Output: $output',
      );
    }

    final moshPort = int.parse(match.group(1)!);
    final keyStr = match.group(2)!;

    var padded = keyStr;
    while (padded.length % 4 != 0) {
      padded += '=';
    }
    final keyBytes = base64Decode(padded);
    if (keyBytes.length != 16) {
      throw MoshException('Invalid mosh key length: ${keyBytes.length}');
    }

    // Step 3: Determine UDP target.
    // For relay connections, latch rewrites the MOSH CONNECT line with the
    // relay's public UDP port. Prefer MOSH IP from latch (always the latest
    // relay address), then fall back to the resolved IP of the jump host we
    // actually connected through (same relay instance), then geo-routed hostname.
    String host;
    if (conn.type == ConnectionType.relay) {
      final ipMatch = RegExp(r'MOSH IP (\S+)').firstMatch(output);
      host = ipMatch?.group(1) ?? result.jumpHostAddress ?? relayJumpHost;
    } else {
      host = conn.host;
    }
    final udpPort = moshPort;

    // Step 4: Open UDP socket.
    // Uses native Network.framework on iOS for cellular support.
    final udpSocket = await NativeUdpSocket.bind(0);

    final addresses = await InternetAddress.lookup(host);
    if (addresses.isEmpty) throw MoshException('Could not resolve $host');
    final remoteAddr = addresses.first;

    // Extract any MOTD/PAM output from the SSH exec (before MOSH CONNECT).
    // This is the same output a real mosh client would show.
    final motdEnd = output.indexOf('MOSH CONNECT');
    final motd = motdEnd > 0 ? output.substring(0, motdEnd).trim() : null;

    return MoshSession(
      socket: udpSocket,
      remoteAddress: remoteAddr,
      remotePort: udpPort,
      key: keyBytes,
      motd: motd,
    );
  }
}

/// Active mosh session with full SSP transport and framebuffer diffing.
///
/// Mirrors the real C++ mosh client's received_states architecture:
/// each incoming diff is applied to a COPY of the base state (looked up
/// by oldNum), producing a new state stored by newNum. The display
/// always shows the latest received state, diffed against what's
/// currently on screen. This eliminates character doubling from
/// overlapping diffs during fast typing.
///
/// Call [start] after subscribing to [incoming] to begin the
/// SSP handshake. This ensures the server's initial screen state
/// is not lost to an unsubscribed broadcast stream.
class MoshSession {
  final NativeUdpSocket socket;
  final InternetAddress remoteAddress;
  final int remotePort;
  final Uint8List key;
  final String? motd; // PAM MOTD from SSH exec, shown before mosh session

  final _incoming = StreamController<Uint8List>.broadcast();
  final _passthroughEscapes = StreamController<Uint8List>.broadcast();
  StreamSubscription<Datagram>? _sub;
  Timer? _ticker;
  bool _started = false;

  /// Whether the SSP handshake has been initiated.
  bool get started => _started;

  late final AesOcb _ocb = AesOcb(key);
  late final MoshTransport _transport = MoshTransport.client(_ocb);

  // Shadow VT emulator for applying diffs.
  Terminal _shadow = Terminal(maxLines: 80);
  int _shadowStateNum = 0;

  // Received states: stateNum → framebuffer snapshot.
  // Mirrors C++ mosh's std::list<TimestampedState<RemoteState>>.
  final _receivedStates = <int, FramebufferSnapshot>{};
  int _latestStateNum = 0;

  // What the display terminal currently shows.
  FramebufferSnapshot? _displayedSnapshot;

  // Terminal dimensions for creating fresh shadows.
  int _cols = 80;
  int _rows = 24;

  /// Stream of pre-diffed ANSI output (only changed cells).
  Stream<Uint8List> get incoming => _incoming.stream;

  /// Stream of passthrough escape sequences (OSC 52 clipboard, etc).
  Stream<Uint8List> get passthroughEscapes => _passthroughEscapes.stream;

  MoshSession({
    required this.socket,
    required this.remoteAddress,
    required this.remotePort,
    required this.key,
    this.motd,
  }) {
    _sub = socket.receive.listen(_handleDatagram);
    // 8ms matches mosh's SEND_MINDELAY — minimum time to batch keystrokes.
    _ticker = Timer.periodic(const Duration(milliseconds: 8), (_) {
      _flush();
    });
  }

  /// Begin the SSP handshake. Call this AFTER subscribing to [incoming]
  /// so the server's initial screen state is delivered to the listener.
  void start() {
    if (_started) return;
    _started = true;
    _transport.forceNextSend();
    _flush();
  }

  void _handleDatagram(Datagram datagram) {
    if (datagram.data.length < minDatagram) return;

    try {
      final diff = _transport.recv(Uint8List.fromList(datagram.data));
      if (diff == null || diff.isEmpty) return;

      final oldNum = _transport.lastRecvOldNum;
      final newNum = _transport.lastRecvNewNum;

      // Already have this state (dedup, matching C++ recv).
      if (_receivedStates.containsKey(newNum)) return;

      // Need the base state to apply the diff.
      // If shadow is at oldNum, snapshot it before modifying.
      if (oldNum == _shadowStateNum && !_receivedStates.containsKey(oldNum)) {
        _receivedStates[oldNum] = FramebufferSnapshot.fromTerminal(_shadow);
      }

      final base = _receivedStates[oldNum];
      if (base == null) return; // unknown base, can't apply

      // Restore shadow to the base state (like C++ copy constructor).
      // Server diffs use absolute CUP positioning so this is sufficient.
      if (_shadowStateNum != oldNum) {
        _shadow = Terminal(maxLines: 80);
        _shadow.resize(_cols, _rows);
        _shadow.write(base.fullRedrawAnsi());
      }

      // Apply diff: feed hoststrings to shadow, extract passthrough escapes.
      final instrs = unmarshalHostMessage(diff);
      for (final hi in instrs) {
        if (hi.hoststring == null || hi.hoststring!.isEmpty) continue;
        final str = utf8.decode(hi.hoststring!, allowMalformed: true);
        final passthrough = _extractPassthrough(str);
        if (passthrough != null) {
          _passthroughEscapes.add(Uint8List.fromList(utf8.encode(passthrough)));
        }
        _shadow.write(str);
      }
      _shadowStateNum = newNum;

      // Store the result as a new received state.
      final snap = FramebufferSnapshot.fromTerminal(_shadow);
      _receivedStates[newNum] = snap;
      if (newNum > _latestStateNum) _latestStateNum = newNum;

      // Bound the received states list (matching C++ 1024 cap).
      if (_receivedStates.length > 128) {
        final sorted = _receivedStates.keys.toList()..sort();
        for (final k in sorted.take(sorted.length - 64)) {
          _receivedStates.remove(k);
        }
      }

      // Display: diff latest state against what's on screen.
      final latest = _receivedStates[_latestStateNum];
      if (latest != null) {
        final ansi = latest.diffAnsi(_displayedSnapshot);
        _displayedSnapshot = latest;
        if (ansi.isNotEmpty) {
          _incoming.add(Uint8List.fromList(utf8.encode(ansi)));
        }
      }
    } catch (_) {
      // Malformed packet — ignore, don't kill socket listener.
    }
  }

  /// Extract OSC 52 sequences from a string. Returns the OSC 52 data
  /// (for clipboard passthrough) or null if none found.
  static String? _extractPassthrough(String s) {
    // Look for OSC 52: ESC ] 52 ; ... ST
    final start = s.indexOf('\x1b]52');
    if (start < 0) return null;
    // Find terminator: BEL or ESC backslash.
    var end = s.indexOf('\x07', start);
    if (end < 0) {
      end = s.indexOf('\x1b\\', start);
      if (end >= 0) end += 2; // include the terminator
    } else {
      end += 1;
    }
    if (end < 0) return null;
    return s.substring(start, end);
  }

  // Simple single-state approach matching real mosh:
  // - Accumulate keystrokes in _pendingKeys
  // - On each tick, if server acked our last state AND we have pending keys,
  //   send a NEW state with all pending keys
  // - Only one unacked state in flight at a time
  // - Transport handles retransmission of the in-flight state
  final _pendingKeys = <UserInstruction>[];

  /// Send keystrokes to the remote.
  // IME composing dedup state.
  Uint8List? _lastKeystrokeBytes;
  DateTime _lastKeystrokeTime = DateTime.fromMillisecondsSinceEpoch(0);

  void sendKeystroke(String s) {
    final keys = Uint8List.fromList(utf8.encode(s));
    final now = DateTime.now();

    // Android IME sends composing text updates that duplicate characters.
    // Pattern: 'f' (1 byte) then 'fa' (2 bytes, 1ms later).
    // The composing text starts with the previous character.
    // Detect and replace instead of append.
    if (_lastKeystrokeBytes != null &&
        now.difference(_lastKeystrokeTime).inMilliseconds < 10 &&
        keys.length > _lastKeystrokeBytes!.length &&
        _startsWith(keys, _lastKeystrokeBytes!)) {
      // Composing replacement: strip the prefix already sent.
      final newBytes = keys.sublist(_lastKeystrokeBytes!.length);
      if (_pendingKeys.isNotEmpty) _pendingKeys.removeLast();
      if (newBytes.isNotEmpty) {
        _pendingKeys.add(UserInstruction(keys: newBytes));
      }
      _lastKeystrokeBytes = keys;
      _lastKeystrokeTime = now;
      return;
    }

    _lastKeystrokeBytes = keys;
    _lastKeystrokeTime = now;
    _pendingKeys.add(UserInstruction(keys: keys));
  }

  bool _startsWith(Uint8List data, Uint8List prefix) {
    if (data.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (data[i] != prefix[i]) return false;
    }
    return true;
  }

  /// Send raw key bytes to the remote.
  void send(Uint8List data) {
    _pendingKeys.add(UserInstruction(keys: data));
  }

  /// Get a full redraw ANSI string for the latest state.
  /// Returns null if no state is available.
  /// Also resets _displayedSnapshot so subsequent diffs are correct.
  String? getLatestRedraw() {
    _displayedSnapshot = null;
    final latest = _receivedStates[_latestStateNum];
    if (latest == null) return null;
    _displayedSnapshot = latest;
    return latest.fullRedrawAnsi();
  }

  /// Force a full redraw of the latest state to the display.
  /// Call when re-attaching to a new display terminal.
  void resetDisplay() {
    final ansi = getLatestRedraw();
    if (ansi != null && ansi.isNotEmpty) {
      _incoming.add(Uint8List.fromList(utf8.encode(ansi)));
    }
  }

  /// Send a terminal resize.
  void sendResize(int width, int height) {
    _cols = width;
    _rows = height;
    _shadow.resize(width, height);
    _displayedSnapshot = null;
    _receivedStates.clear();
    _pendingKeys.add(UserInstruction(width: width, height: height));
  }

  /// Flush: send outgoing keystrokes.
  void _flush() {
    if (!_transport.hasPendingState && _pendingKeys.isNotEmpty) {
      final diff = marshalUserMessage(_pendingKeys);
      _pendingKeys.clear();
      _transport.sendNew(diff);
    }

    final datagrams = _transport.tick();
    for (final dg in datagrams) {
      socket.send(Uint8List.fromList(dg), remoteAddress, remotePort);
    }
  }

  void close() {
    _ticker?.cancel();
    _sub?.cancel();
    _incoming.close();
    _passthroughEscapes.close();
    socket.close();
  }
}

class MoshException implements Exception {
  final String message;
  MoshException(this.message);

  @override
  String toString() => message;
}
