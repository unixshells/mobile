import 'dart:convert';
import 'dart:typed_data';

import 'package:xterm/xterm.dart';

import '../../models/session.dart';

/// Bridges keyboard input from an xterm Terminal to the active session.
/// Stream subscriptions (stdout → terminal) live on ActiveSession, not here.
class TerminalBridge {
  Terminal? _terminal;
  ActiveSession? _session;
  void Function(String sessionId)? onDisconnect;
  void Function(String sessionId)? onSessionEnded;

  String Function(String data)? outputInterceptor;

  TerminalBridge();

  Terminal? get terminal => _terminal;

  void attach(ActiveSession session) {
    // Unhook previous session/terminal.
    _terminal?.onOutput = null;
    if (_session != null) _session!.onEnded = null;
    _session = session;
    _terminal = session.terminal;

    session.onEnded = () {
      final cb = onSessionEnded;
      if (cb != null) cb(session.id);
    };

    final term = _terminal!;
    if (session.isMosh) {
      term.onOutput = (data) {
        if (session.ended) return;
        final out = outputInterceptor?.call(data) ?? data;
        session.moshSession!.sendKeystroke(out);
      };
      // Re-attaching to a running mosh session — redraw.
      if (session.moshSession!.started) {
        final redraw = session.moshSession!.getLatestRedraw();
        if (redraw != null) term.write(redraw);
      }
    } else {
      term.onOutput = (data) {
        if (session.ended) return;
        final out = outputInterceptor?.call(data) ?? data;
        session.shell?.stdin.add(Uint8List.fromList(utf8.encode(out)));
      };
    }
  }

  void detach() {
    _terminal?.onOutput = null;
    _session?.onEnded = null;
    _session = null;
  }

  void checkAlive() {
    final session = _session;
    if (session == null || session.ended) return;
    final term = _terminal;
    if (term == null) return;
    if (session.isMosh) {
      final cols = term.viewWidth;
      final rows = term.viewHeight;
      if (cols > 0 && rows > 0) session.moshSession!.sendResize(cols, rows);
    } else {
      try {
        final shell = session.shell;
        if (shell == null) return;
        shell.stdin.add(Uint8List(0));
      } catch (_) {
        session.ended = true;
        final cb = onSessionEnded;
        if (cb != null) cb(session.id);
      }
    }
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

  void clear() { _terminal?.write('\x1b[2J\x1b[H'); }
  void dispose() { detach(); }
}
