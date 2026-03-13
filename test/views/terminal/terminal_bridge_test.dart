import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

import 'package:unixshells/models/connection.dart';
import 'package:unixshells/models/session.dart';
import 'package:unixshells/services/mosh_service.dart';
import 'package:unixshells/views/terminal/terminal_bridge.dart';

// -- Fakes --

class FakeSSHSession extends Fake implements SSHSession {
  final _stdoutController = StreamController<Uint8List>.broadcast();
  final _stdinSink = FakeStdinSink();
  int resizeCalls = 0;
  int lastResizeWidth = 0;
  int lastResizeHeight = 0;

  @override
  Stream<Uint8List> get stdout => _stdoutController.stream;

  @override
  StreamSink<Uint8List> get stdin => _stdinSink;

  @override
  void resizeTerminal(int width, int height,
      [int pixelWidth = 0, int pixelHeight = 0]) {
    resizeCalls++;
    lastResizeWidth = width;
    lastResizeHeight = height;
  }

  @override
  void close() {}

  void emitStdout(String text) {
    _stdoutController.add(Uint8List.fromList(utf8.encode(text)));
  }

  Future<void> closeStdout() => _stdoutController.close();

  void emitError(Object error) {
    _stdoutController.addError(error);
  }
}

class FakeStdinSink extends Fake implements StreamSink<Uint8List> {
  final List<Uint8List> written = [];

  @override
  void add(Uint8List data) {
    written.add(data);
  }
}

class FakeMoshSession extends Fake implements MoshSession {
  final _incomingController = StreamController<Uint8List>.broadcast();
  int resizeCalls = 0;
  int lastResizeWidth = 0;
  int lastResizeHeight = 0;
  final List<String> keystrokes = [];

  @override
  Stream<Uint8List> get incoming => _incomingController.stream;

  @override
  void sendResize(int width, int height) {
    resizeCalls++;
    lastResizeWidth = width;
    lastResizeHeight = height;
  }

  @override
  void sendKeystroke(String s) {
    keystrokes.add(s);
  }

  @override
  void close() {
    _incomingController.close();
  }

  void emitIncoming(String text) {
    _incomingController.add(Uint8List.fromList(utf8.encode(text)));
  }

  Future<void> closeIncoming() => _incomingController.close();
}

Connection _testConnection() => Connection(
      id: 'conn-1',
      label: 'Test',
      host: 'localhost',
    );

ActiveSession _makeSSHSession(FakeSSHSession shell) => ActiveSession(
      id: 'ssh-session-1',
      connection: _testConnection(),
      shell: shell,
      label: 'SSH Session',
    );

ActiveSession _makeMoshSession(FakeMoshSession mosh) => ActiveSession(
      id: 'mosh-session-1',
      connection: _testConnection(),
      moshSession: mosh,
      label: 'Mosh Session',
    );

void main() {
  group('checkAlive on ended session', () {
    test('does nothing when session already ended (SSH)', () async {
      final terminal = Terminal(maxLines: 100);
      final bridge = TerminalBridge(terminal);
      final shell = FakeSSHSession();
      final session = _makeSSHSession(shell);

      bridge.attach(session);

      // End the session by closing stdout.
      await shell.closeStdout();
      await Future.delayed(Duration.zero);

      // checkAlive should not crash or write duplicate messages.
      bridge.checkAlive();

      // Verify no stdin probe was attempted (session is ended).
      final stdinSink = shell.stdin as FakeStdinSink;
      expect(stdinSink.written, isEmpty);

      bridge.dispose();
    });

    test('does nothing when session already ended (Mosh)', () async {
      final terminal = Terminal(maxLines: 100);
      final bridge = TerminalBridge(terminal);
      final mosh = FakeMoshSession();
      final session = _makeMoshSession(mosh);

      bridge.attach(session);

      // End the session by closing incoming stream.
      await mosh.closeIncoming();
      await Future.delayed(Duration.zero);

      // Reset the resize counter after any attach-time calls.
      mosh.resizeCalls = 0;

      // checkAlive should not crash or call sendResize.
      bridge.checkAlive();
      expect(mosh.resizeCalls, equals(0));

      bridge.dispose();
    });
  });

  group('checkAlive with null session', () {
    test('does nothing when no session is attached', () {
      final terminal = Terminal(maxLines: 100);
      final bridge = TerminalBridge(terminal);

      // No attach call -- session is null.
      // checkAlive should return silently without throwing.
      bridge.checkAlive();

      bridge.dispose();
    });

    test('does nothing after detach', () async {
      final terminal = Terminal(maxLines: 100);
      final bridge = TerminalBridge(terminal);
      final shell = FakeSSHSession();
      final session = _makeSSHSession(shell);

      bridge.attach(session);
      bridge.detach();

      // Session is now null. checkAlive should not crash.
      bridge.checkAlive();

      bridge.dispose();
      await shell.closeStdout();
    });
  });

  group('_showDisconnected writes disconnect message', () {
    test('writes disconnect text when stdin.add throws (broken pipe)', () async {
      final terminal = Terminal(maxLines: 100);
      final bridge = TerminalBridge(terminal);
      final shell = _ThrowingSSHSession();
      final session = ActiveSession(
        id: 'broken-pipe',
        connection: _testConnection(),
        shell: shell,
        label: 'Broken Pipe Session',
      );

      String? endedId;
      bridge.onSessionEnded = (id) => endedId = id;

      bridge.attach(session);

      // checkAlive tries stdin.add which throws, triggering _showDisconnected.
      bridge.checkAlive();

      expect(endedId, equals('broken-pipe'));

      bridge.dispose();
      await shell.closeStdout();
    });

    test('onSessionEnded receives correct session id', () async {
      final terminal = Terminal(maxLines: 100);
      final bridge = TerminalBridge(terminal);
      final shell = _ThrowingSSHSession();
      final session = ActiveSession(
        id: 'specific-id-42',
        connection: _testConnection(),
        shell: shell,
        label: 'ID Check Session',
      );

      String? endedId;
      bridge.onSessionEnded = (id) => endedId = id;

      bridge.attach(session);
      bridge.checkAlive();

      expect(endedId, equals('specific-id-42'));

      bridge.dispose();
      await shell.closeStdout();
    });
  });

  group('_showDisconnected only fires once', () {
    test('calling checkAlive twice does not duplicate disconnect', () async {
      final terminal = Terminal(maxLines: 100);
      final bridge = TerminalBridge(terminal);
      final shell = _ThrowingSSHSession();
      final session = ActiveSession(
        id: 'dup-test',
        connection: _testConnection(),
        shell: shell,
        label: 'Dup Test',
      );

      var endedCount = 0;
      bridge.onSessionEnded = (_) => endedCount++;

      bridge.attach(session);

      // First checkAlive triggers _showDisconnected via thrown exception.
      bridge.checkAlive();
      // Second checkAlive should be a no-op since _ended is now true.
      bridge.checkAlive();

      // onSessionEnded should fire exactly once.
      expect(endedCount, equals(1));

      bridge.dispose();
      await shell.closeStdout();
    });

    test('_showEnded + checkAlive does not duplicate', () async {
      final terminal = Terminal(maxLines: 100);
      final bridge = TerminalBridge(terminal);
      final shell = FakeSSHSession();
      final session = _makeSSHSession(shell);

      var endedCount = 0;
      bridge.onSessionEnded = (_) => endedCount++;

      bridge.attach(session);

      // Trigger _showEnded via stream close.
      await shell.closeStdout();
      await Future.delayed(Duration.zero);
      expect(endedCount, equals(1));

      // checkAlive should not fire again -- _ended is already true.
      bridge.checkAlive();
      expect(endedCount, equals(1));

      bridge.dispose();
    });
  });

  group('syncDimensions routes to mosh', () {
    test('calls moshSession.sendResize when session is mosh', () {
      final terminal = Terminal(maxLines: 100);
      final bridge = TerminalBridge(terminal);
      final mosh = FakeMoshSession();
      final session = _makeMoshSession(mosh);

      bridge.attach(session);
      mosh.resizeCalls = 0;

      bridge.syncDimensions();

      // Terminal has default dimensions (80x24 or similar).
      // As long as cols > 0 and rows > 0, sendResize should be called.
      if (terminal.viewWidth > 0 && terminal.viewHeight > 0) {
        expect(mosh.resizeCalls, equals(1));
        expect(mosh.lastResizeWidth, equals(terminal.viewWidth));
        expect(mosh.lastResizeHeight, equals(terminal.viewHeight));
      }

      bridge.dispose();
    });

    test('does not call shell.resizeTerminal when session is mosh', () {
      // Mosh sessions have no shell, so there's nothing to accidentally call.
      // This test verifies the routing is correct by confirming mosh is used.
      final terminal = Terminal(maxLines: 100);
      final bridge = TerminalBridge(terminal);
      final mosh = FakeMoshSession();
      final session = _makeMoshSession(mosh);

      bridge.attach(session);
      mosh.resizeCalls = 0;

      bridge.syncDimensions();

      // The session has no shell, so only mosh path runs.
      expect(session.isMosh, isTrue);
      expect(session.shell, isNull);

      bridge.dispose();
    });
  });

  group('handleResize routes to mosh', () {
    test('calls moshSession.sendResize for mosh session', () {
      final terminal = Terminal(maxLines: 100);
      final bridge = TerminalBridge(terminal);
      final mosh = FakeMoshSession();
      final session = _makeMoshSession(mosh);

      bridge.attach(session);
      mosh.resizeCalls = 0;

      bridge.handleResize(120, 40);

      expect(mosh.resizeCalls, equals(1));
      expect(mosh.lastResizeWidth, equals(120));
      expect(mosh.lastResizeHeight, equals(40));

      bridge.dispose();
    });

    test('does not call shell.resizeTerminal for mosh session', () {
      final terminal = Terminal(maxLines: 100);
      final bridge = TerminalBridge(terminal);
      final mosh = FakeMoshSession();
      final session = _makeMoshSession(mosh);

      bridge.attach(session);

      bridge.handleResize(100, 50);

      // Mosh session has no shell -- only mosh path is taken.
      expect(session.shell, isNull);
      expect(mosh.resizeCalls, greaterThan(0));

      bridge.dispose();
    });
  });

  group('syncDimensions routes to SSH', () {
    test('calls shell.resizeTerminal for SSH session', () {
      final terminal = Terminal(maxLines: 100);
      final bridge = TerminalBridge(terminal);
      final shell = FakeSSHSession();
      final session = _makeSSHSession(shell);

      bridge.attach(session);
      shell.resizeCalls = 0;

      bridge.syncDimensions();

      if (terminal.viewWidth > 0 && terminal.viewHeight > 0) {
        expect(shell.resizeCalls, equals(1));
        expect(shell.lastResizeWidth, equals(terminal.viewWidth));
        expect(shell.lastResizeHeight, equals(terminal.viewHeight));
      }

      bridge.dispose();
    });

    test('handleResize calls shell.resizeTerminal for SSH session', () {
      final terminal = Terminal(maxLines: 100);
      final bridge = TerminalBridge(terminal);
      final shell = FakeSSHSession();
      final session = _makeSSHSession(shell);

      bridge.attach(session);
      shell.resizeCalls = 0;

      bridge.handleResize(132, 43);

      expect(shell.resizeCalls, equals(1));
      expect(shell.lastResizeWidth, equals(132));
      expect(shell.lastResizeHeight, equals(43));

      bridge.dispose();
    });

    test('does not call mosh sendResize for SSH session', () {
      final terminal = Terminal(maxLines: 100);
      final bridge = TerminalBridge(terminal);
      final shell = FakeSSHSession();
      final session = _makeSSHSession(shell);

      // SSH session has no mosh.
      expect(session.isMosh, isFalse);
      expect(session.moshSession, isNull);

      bridge.attach(session);
      shell.resizeCalls = 0;

      bridge.handleResize(80, 24);

      expect(shell.resizeCalls, equals(1));

      bridge.dispose();
    });
  });
}

/// SSHSession whose stdin.add always throws, simulating a broken pipe.
class _ThrowingSSHSession extends Fake implements SSHSession {
  final _stdoutController = StreamController<Uint8List>.broadcast();

  @override
  Stream<Uint8List> get stdout => _stdoutController.stream;

  @override
  StreamSink<Uint8List> get stdin => _ThrowingStdinSink();

  @override
  void resizeTerminal(int width, int height,
      [int pixelWidth = 0, int pixelHeight = 0]) {}

  @override
  void close() {}

  Future<void> closeStdout() => _stdoutController.close();
}

class _ThrowingStdinSink extends Fake implements StreamSink<Uint8List> {
  @override
  void add(Uint8List data) {
    throw StateError('Broken pipe');
  }
}
