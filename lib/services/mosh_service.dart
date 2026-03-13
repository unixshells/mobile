import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../crypto/mosh_pb.dart';
import '../crypto/mosh_transport.dart';
import '../crypto/ocb.dart';
import '../models/connection.dart';
import 'relay_api_service.dart';
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
  final RelayApiService _api;

  MoshService(this._sshService, this._api);

  /// Start a mosh session.
  Future<MoshSession> connect(Connection conn) async {
    // Step 1: SSH connect and exec mosh-server.
    final result = await _sshService.connect(conn);
    final client = result.targetClient;

    final session = await client.execute(
      'mosh-server new -s -c 256 -l LANG=en_US.UTF-8 -- /bin/sh',
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
    final match = RegExp(r'MOSH CONNECT (\d+) ([A-Za-z0-9/+]+={0,2})')
        .firstMatch(output);
    if (match == null) {
      throw MoshException('mosh-server did not return connection info.\n'
          'Is mosh-server installed on the remote? Output: $output');
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
    String host;
    int udpPort;

    if (conn.type == ConnectionType.relay) {
      final relaySession = await _api.moshRelay(
        username: conn.relayUsername!,
        device: conn.relayDevice!,
        targetPort: moshPort,
      );
      host = relaySession.relayHost;
      udpPort = relaySession.relayPort;
    } else {
      host = conn.host;
      udpPort = moshPort;
    }

    // Step 4: Open UDP socket.
    final udpSocket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      0,
    );

    final addresses = await InternetAddress.lookup(host);
    if (addresses.isEmpty) throw MoshException('Could not resolve $host');
    final remoteAddr = addresses.first;

    return MoshSession(
      socket: udpSocket,
      remoteAddress: remoteAddr,
      remotePort: udpPort,
      key: keyBytes,
    );
  }
}

/// Active mosh session with full SSP transport.
class MoshSession {
  final RawDatagramSocket socket;
  final InternetAddress remoteAddress;
  final int remotePort;
  final Uint8List key;

  final _incoming = StreamController<Uint8List>.broadcast();
  StreamSubscription<RawSocketEvent>? _sub;
  Timer? _ticker;

  late final AesOcb _ocb = AesOcb(key);
  late final MoshTransport _transport = MoshTransport.client(_ocb);

  /// Stream of decoded terminal output from the server.
  Stream<Uint8List> get incoming => _incoming.stream;

  MoshSession({
    required this.socket,
    required this.remoteAddress,
    required this.remotePort,
    required this.key,
  }) {
    _sub = socket.listen(_handleEvent);

    // Tick loop drives the SSP send timer.
    _ticker = Timer.periodic(const Duration(milliseconds: 20), (_) {
      _flush();
    });

    // Send initial empty datagram to establish the association.
    _transport.setPending(Uint8List(0));
    _flush();
  }

  void _handleEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = socket.receive();
    if (datagram == null) return;
    if (datagram.data.length < minDatagram) return;

    final diff = _transport.recv(Uint8List.fromList(datagram.data));
    if (diff == null || diff.isEmpty) return;

    // Parse HostMessage protobuf.
    try {
      final instrs = unmarshalHostMessage(diff);
      for (final hi in instrs) {
        if (hi.hoststring != null && hi.hoststring!.isNotEmpty) {
          _incoming.add(hi.hoststring!);
        }
      }
    } catch (_) {
      // Malformed protobuf — ignore.
    }
  }

  /// Send keystrokes to the remote.
  void sendKeystroke(String s) {
    final keys = Uint8List.fromList(utf8.encode(s));
    final diff = marshalUserMessage([UserInstruction(keys: keys)]);
    _transport.setPending(diff);
  }

  /// Send raw key bytes to the remote.
  void send(Uint8List data) {
    final diff = marshalUserMessage([UserInstruction(keys: data)]);
    _transport.setPending(diff);
  }

  /// Send a terminal resize.
  void sendResize(int width, int height) {
    final diff = marshalUserMessage([
      UserInstruction(width: width, height: height),
    ]);
    _transport.setPending(diff);
  }

  /// Flush pending transport datagrams to the socket.
  void _flush() {
    final datagrams = _transport.tick();
    for (final dg in datagrams) {
      socket.send(dg, remoteAddress, remotePort);
    }
  }

  void close() {
    _ticker?.cancel();
    _sub?.cancel();
    _incoming.close();
    socket.close();
  }
}

class MoshException implements Exception {
  final String message;
  MoshException(this.message);

  @override
  String toString() => message;
}
