import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../../models/session.dart';

/// Bridges an SSH session's I/O to a native xterm Terminal.
class TerminalBridge {
  Terminal? _terminal;
  StreamSubscription<Uint8List>? _outputSub;
  StreamSubscription<Uint8List>? _passthroughSub;
  ActiveSession? _session;
  bool _ended = false;
  void Function(String sessionId)? onDisconnect;
  void Function(String sessionId)? onSessionEnded;

  /// Optional interceptor for terminal output before sending to session.
  /// Return the (possibly modified) data to send, or null to suppress.
  String Function(String data)? outputInterceptor;

  final _oscBuf = StringBuffer();
  bool _inOsc52 = false;
  String _lastChar = '';

  TerminalBridge();

  Terminal? get terminal => _terminal;

  void attach(ActiveSession session) {
    detach();
    _session = session;
    _terminal = session.terminal;
    if (session.isMosh) {
      _attachMosh(session);
    } else {
      _attachSSH(session);
    }
  }

  void _attachSSH(ActiveSession session) {
    _ended = false;
    final term = _terminal!;
    _outputSub = session.shell!.stdout.listen(
      (data) {
        _handleOsc52(data);
        term.write(utf8.decode(data, allowMalformed: true));
      },
      onError: (error) => _showEnded(session.id),
      onDone: () => _showEnded(session.id),
    );
    term.onOutput = (data) {
      if (_ended) return;
      final out = outputInterceptor?.call(data) ?? data;
      _session?.shell?.stdin.add(Uint8List.fromList(utf8.encode(out)));
    };
  }

  void _attachMosh(ActiveSession session) {
    _ended = false;
    final term = _terminal!;
    final mosh = session.moshSession!;

    // incoming now emits pre-diffed ANSI (cursor-positioned cell updates).
    _outputSub = mosh.incoming.listen(
      (data) {
        try {
          term.write(utf8.decode(data, allowMalformed: true));
        } catch (_) {}
      },
      onError: (error) => _showEnded(session.id),
      onDone: () => _showEnded(session.id),
    );

    // OSC 52 clipboard passthrough comes on a separate stream.
    _passthroughSub = mosh.passthroughEscapes.listen(
      (data) {
        try {
          _handleOsc52(data);
        } catch (_) {}
      },
    );

    term.onOutput = (data) {
      if (_ended) return;
      final out = outputInterceptor?.call(data) ?? data;
      mosh.sendKeystroke(out);
    };

    // Don't display SSH exec MOTD separately — the mosh server's login
    // shell produces it via hoststrings (triggered by PTY exec + PAM).
    if (mosh.started) {
      // Re-attaching to an already-started session — write full redraw
      // directly to terminal (not via stream, to avoid async delivery).
      final redraw = mosh.getLatestRedraw();
      if (redraw != null) term.write(redraw);
    } else {
      mosh.start();
    }
  }

  void _showEnded(String sessionId) {
    if (_ended) return;
    _ended = true;
    _terminal?.write('\r\n\x1b[90m[Session ended. Close tab to disconnect.]\x1b[0m\r\n');
    onSessionEnded?.call(sessionId);
  }

  void checkAlive() {
    final session = _session;
    if (session == null || _ended) return;
    final term = _terminal;
    if (term == null) return;
    if (session.isMosh) {
      final cols = term.viewWidth;
      final rows = term.viewHeight;
      if (cols > 0 && rows > 0) session.moshSession!.sendResize(cols, rows);
    } else {
      try {
        final shell = session.shell;
        if (shell == null) { _showDisconnected(session.id); return; }
        shell.stdin.add(Uint8List(0));
      } catch (_) { _showDisconnected(session.id); }
    }
  }

  void _showDisconnected(String sessionId) {
    if (_ended) return;
    _ended = true;
    _terminal?.write('\r\n\x1b[31m[Disconnected — session ended by iOS.]\x1b[0m\r\n');
    _terminal?.write('\x1b[90m[Close tab to return.]\x1b[0m\r\n');
    onSessionEnded?.call(sessionId);
  }

  void syncDimensions() {
    final term = _terminal;
    if (term == null) return;
    final cols = term.viewWidth;
    final rows = term.viewHeight;
    if (cols > 0 && rows > 0) {
      if (_session?.isMosh == true) {
        _session!.moshSession!.sendResize(cols, rows);
      } else {
        _session?.shell?.resizeTerminal(cols, rows);
      }
    }
  }

  void handleResize(int cols, int rows) {
    if (_session?.isMosh == true) {
      _session!.moshSession!.sendResize(cols, rows);
    } else {
      _session?.shell?.resizeTerminal(cols, rows);
    }
  }

  void _handleOsc52(Uint8List data) {
    final str = utf8.decode(data, allowMalformed: true);
    for (var i = 0; i < str.length; i++) {
      if (_inOsc52) {
        if (str[i] == '\x07' || (str[i] == '\\' && _lastChar == '\x1b')) {
          var payload = _oscBuf.toString();
          if (payload.endsWith('\x1b')) payload = payload.substring(0, payload.length - 1);
          _processOsc52(payload);
          _inOsc52 = false;
          _oscBuf.clear();
          _lastChar = '';
        } else { _oscBuf.write(str[i]); _lastChar = str[i]; }
      } else if (i + 3 < str.length && str[i] == '\x1b' && str[i + 1] == ']' && str[i + 2] == '5' && str[i + 3] == '2') {
        _inOsc52 = true; _oscBuf.clear(); i += 3;
      }
    }
  }

  void _processOsc52(String payload) {
    final parts = payload.split(';');
    if (parts.length < 3) return;
    final b64 = parts.last;
    if (b64 == '?') return;
    try { Clipboard.setData(ClipboardData(text: utf8.decode(base64Decode(b64)))); } catch (_) {}
  }

  void detach() {
    _outputSub?.cancel(); _outputSub = null;
    _passthroughSub?.cancel(); _passthroughSub = null;
    _terminal?.onOutput = null; _session = null; _ended = false;
  }
  void clear() { _terminal?.write('\x1b[2J\x1b[H'); }
  void dispose() { detach(); }
}
