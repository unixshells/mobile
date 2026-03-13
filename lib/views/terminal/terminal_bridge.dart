import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../../models/session.dart';

/// Bridges an SSH session's I/O to a native xterm Terminal.
class TerminalBridge {
  final Terminal terminal;
  StreamSubscription<Uint8List>? _outputSub;
  ActiveSession? _session;
  bool _ended = false;
  void Function(String sessionId)? onDisconnect;
  void Function(String sessionId)? onSessionEnded;

  // OSC 52 accumulation buffer.
  final _oscBuf = StringBuffer();
  bool _inOsc52 = false;
  String _lastChar = '';

  TerminalBridge(this.terminal);

  /// Attach a session: pipe SSH/mosh output to terminal, terminal input back.
  void attach(ActiveSession session) {
    detach();
    _session = session;

    if (session.isMosh) {
      _attachMosh(session);
    } else {
      _attachSSH(session);
    }
  }

  void _attachSSH(ActiveSession session) {
    _ended = false;
    _outputSub = session.shell!.stdout.listen(
      (data) {
        _handleOsc52(data);
        terminal.write(utf8.decode(data, allowMalformed: true));
      },
      onError: (error) {
        _showEnded(session.id);
      },
      onDone: () {
        _showEnded(session.id);
      },
    );

    terminal.onOutput = (data) {
      if (_ended) return;
      final bytes = utf8.encode(data);
      _session?.shell?.stdin.add(Uint8List.fromList(bytes));
    };
  }

  void _attachMosh(ActiveSession session) {
    _ended = false;
    final mosh = session.moshSession!;
    _outputSub = mosh.incoming.listen(
      (data) {
        _handleOsc52(data);
        terminal.write(utf8.decode(data, allowMalformed: true));
      },
      onError: (error) {
        _showEnded(session.id);
      },
      onDone: () {
        _showEnded(session.id);
      },
    );

    terminal.onOutput = (data) {
      if (_ended) return;
      mosh.sendKeystroke(data);
    };
  }

  void _showEnded(String sessionId) {
    if (_ended) return;
    _ended = true;
    terminal.write('\r\n\x1b[90m[Session ended. Close tab to disconnect.]\x1b[0m\r\n');
    onSessionEnded?.call(sessionId);
  }

  /// Check if the session is still alive after returning from background.
  /// For SSH: detect dead TCP connection and show disconnect message.
  /// For Mosh: send a resize to kick the UDP transport back to life.
  void checkAlive() {
    final session = _session;
    if (session == null || _ended) return;

    if (session.isMosh) {
      // Mosh uses UDP — survives backgrounding. Send a resize to
      // trigger an immediate round-trip with the server.
      final cols = terminal.viewWidth;
      final rows = terminal.viewHeight;
      if (cols > 0 && rows > 0) {
        session.moshSession!.sendResize(cols, rows);
      }
    } else {
      // SSH uses TCP — iOS kills the connection on background.
      // Try writing to detect a broken pipe.
      try {
        final shell = session.shell;
        if (shell == null) {
          _showDisconnected(session.id);
          return;
        }
        // The stream listener's onDone/onError will fire if the
        // connection is dead. But on iOS, the socket may appear
        // open until we try to use it. Send a zero-byte write
        // to probe. If it throws, the connection is dead.
        shell.stdin.add(Uint8List(0));
      } catch (_) {
        _showDisconnected(session.id);
      }
    }
  }

  void _showDisconnected(String sessionId) {
    if (_ended) return;
    _ended = true;
    terminal.write('\r\n\x1b[31m[Disconnected — session ended by iOS.]\x1b[0m\r\n');
    terminal.write('\x1b[90m[Close tab to return.]\x1b[0m\r\n');
    onSessionEnded?.call(sessionId);
  }

  /// Resize the session to match terminal dimensions.
  void syncDimensions() {
    final cols = terminal.viewWidth;
    final rows = terminal.viewHeight;
    if (cols > 0 && rows > 0) {
      if (_session?.isMosh == true) {
        _session!.moshSession!.sendResize(cols, rows);
      } else {
        _session?.shell?.resizeTerminal(cols, rows);
      }
    }
  }

  /// Handle resize from terminal.
  void handleResize(int cols, int rows) {
    if (_session?.isMosh == true) {
      _session!.moshSession!.sendResize(cols, rows);
    } else {
      _session?.shell?.resizeTerminal(cols, rows);
    }
  }

  /// Scan output for OSC 52 clipboard sequences and copy to system clipboard.
  void _handleOsc52(Uint8List data) {
    final str = utf8.decode(data, allowMalformed: true);
    for (var i = 0; i < str.length; i++) {
      if (_inOsc52) {
        if (str[i] == '\x07' || (str[i] == '\\' && _lastChar == '\x1b')) {
          var payload = _oscBuf.toString();
          if (payload.endsWith('\x1b')) {
            payload = payload.substring(0, payload.length - 1);
          }
          _processOsc52(payload);
          _inOsc52 = false;
          _oscBuf.clear();
          _lastChar = '';
        } else {
          _oscBuf.write(str[i]);
          _lastChar = str[i];
        }
      } else if (i + 3 < str.length &&
          str[i] == '\x1b' &&
          str[i + 1] == ']' &&
          str[i + 2] == '5' &&
          str[i + 3] == '2') {
        _inOsc52 = true;
        _oscBuf.clear();
        i += 3;
      }
    }
  }

  void _processOsc52(String payload) {
    final parts = payload.split(';');
    if (parts.length < 3) return;
    final b64 = parts.last;
    if (b64 == '?') return;
    try {
      final text = utf8.decode(base64Decode(b64));
      Clipboard.setData(ClipboardData(text: text));
    } catch (_) {}
  }

  void detach() {
    _outputSub?.cancel();
    _outputSub = null;
    terminal.onOutput = null;
    _session = null;
    _ended = false;
  }

  /// Clear the terminal display.
  void clear() {
    terminal.write('\x1b[2J\x1b[H');
  }

  void dispose() {
    detach();
  }
}
