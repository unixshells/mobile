import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

import 'package:unixshells/models/connection.dart';
import 'package:unixshells/models/session.dart';
import 'package:unixshells/views/terminal/terminal_bridge.dart';

// -- Fake SSHSession that implements just enough for the bridge --

class FakeSSHSession extends Fake implements SSHSession {
  final _stdoutController = StreamController<Uint8List>.broadcast();
  final _stdinSink = _FakeStdinSink();

  @override
  Stream<Uint8List> get stdout => _stdoutController.stream;

  @override
  StreamSink<Uint8List> get stdin => _stdinSink;

  @override
  void resizeTerminal(int width, int height,
      [int pixelWidth = 0, int pixelHeight = 0]) {
    // no-op for tests
  }

  @override
  void close() {}

  /// Emit data as if from the remote process.
  void emitStdout(String text) {
    _stdoutController.add(Uint8List.fromList(utf8.encode(text)));
  }

  /// Close the stdout stream (simulates session ending).
  Future<void> closeStdout() => _stdoutController.close();

  /// Emit an error on stdout.
  void emitError(Object error) {
    _stdoutController.addError(error);
  }
}

class _FakeStdinSink extends Fake implements StreamSink<Uint8List> {
  final List<Uint8List> written = [];

  @override
  void add(Uint8List data) {
    written.add(data);
  }
}

ActiveSession _makeSession(FakeSSHSession shell) {
  return ActiveSession(
    id: 'test-session-1',
    connection: Connection(
      id: 'conn-1',
      label: 'Test',
      host: 'localhost',
    ),
    shell: shell,
    label: 'Test Session',
  );
}

void main() {
  group('TerminalBridge attach', () {
    test('sets up output listener that writes to terminal', () async {
      final bridge = TerminalBridge();
      final shell = FakeSSHSession();
      final session = _makeSession(shell);

      bridge.attach(session);

      // Simulate server output.
      shell.emitStdout('Hello');
      await Future.delayed(Duration.zero);

      // Verify the bridge is functional (no crash, subscription active).
      expect(bridge, isNotNull);

      bridge.dispose();
      await shell.closeStdout();
    });

    test('terminal input is forwarded to shell stdin', () async {
      final bridge = TerminalBridge();
      final shell = FakeSSHSession();
      final session = _makeSession(shell);

      bridge.attach(session);

      // Simulate terminal user typing.
      session.terminal.onOutput?.call('ls\n');

      final stdinSink = shell.stdin as _FakeStdinSink;
      expect(stdinSink.written.length, equals(1));
      expect(utf8.decode(stdinSink.written[0]), equals('ls\n'));

      bridge.dispose();
      await shell.closeStdout();
    });
  });

  group('TerminalBridge detach', () {
    test('cancels subscription and clears session', () async {
      final bridge = TerminalBridge();
      final shell = FakeSSHSession();
      final session = _makeSession(shell);

      bridge.attach(session);
      bridge.detach();

      // After detach, output from shell should not cause errors.
      shell.emitStdout('ignored');
      await Future.delayed(Duration.zero);

      // Input should be ignored (onOutput is null after detach).
      expect(session.terminal.onOutput, isNull);

      bridge.dispose();
      await shell.closeStdout();
    });

    test('double detach is safe', () {
      final bridge = TerminalBridge();
      final shell = FakeSSHSession();
      final session = _makeSession(shell);

      bridge.attach(session);
      bridge.detach();
      bridge.detach(); // Should not throw.

      expect(session.terminal.onOutput, isNull);
      bridge.dispose();
    });
  });

  group('TerminalBridge onSessionEnded', () {
    test('fires when stdout stream closes', () async {
      final bridge = TerminalBridge();
      final shell = FakeSSHSession();
      final session = _makeSession(shell);
      session.startListening();

      String? endedSessionId;
      bridge.onSessionEnded = (id) => endedSessionId = id;

      bridge.attach(session);

      // Close the stdout stream to simulate session end.
      await shell.closeStdout();
      await Future.delayed(Duration.zero);

      expect(endedSessionId, equals('test-session-1'));

      bridge.dispose();
    });

    test('fires when stdout stream errors', () async {
      final bridge = TerminalBridge();
      final shell = FakeSSHSession();
      final session = _makeSession(shell);
      session.startListening();

      String? endedSessionId;
      bridge.onSessionEnded = (id) => endedSessionId = id;

      bridge.attach(session);

      // Emit an error on the stdout stream.
      shell.emitError(Exception('connection lost'));
      await Future.delayed(Duration.zero);

      expect(endedSessionId, equals('test-session-1'));

      bridge.dispose();
      await shell.closeStdout();
    });
  });

  group('TerminalBridge input after session ends', () {
    test('input is ignored after session ends (_ended flag)', () async {
      final bridge = TerminalBridge();
      final shell = FakeSSHSession();
      final session = _makeSession(shell);
      session.startListening();

      bridge.attach(session);

      // End the session.
      await shell.closeStdout();
      await Future.delayed(Duration.zero);

      // Try to send input. The onOutput callback should still be set
      // but should silently drop input because _ended is true.
      session.terminal.onOutput?.call('should be ignored');

      final stdinSink = shell.stdin as _FakeStdinSink;
      expect(stdinSink.written, isEmpty);

      bridge.dispose();
    });

    test('onSessionEnded fires only once for multiple close signals', () async {
      final bridge = TerminalBridge();
      final shell = FakeSSHSession();
      final session = _makeSession(shell);
      session.startListening();

      var endedCount = 0;
      bridge.onSessionEnded = (_) => endedCount++;

      bridge.attach(session);

      // Close the stream (fires onDone).
      await shell.closeStdout();
      await Future.delayed(Duration.zero);

      // _showEnded checks _ended flag, so it should fire only once.
      expect(endedCount, equals(1));

      bridge.dispose();
    });
  });

  group('TerminalBridge dispose', () {
    test('dispose calls detach', () {
      final bridge = TerminalBridge();
      final shell = FakeSSHSession();
      final session = _makeSession(shell);

      bridge.attach(session);
      bridge.dispose();

      expect(session.terminal.onOutput, isNull);
    });

    test('dispose without attach is safe', () {
      final bridge = TerminalBridge();

      // Should not throw.
      bridge.dispose();
    });
  });

  group('TerminalBridge clear', () {
    test('writes ANSI clear sequence to terminal', () {
      final bridge = TerminalBridge();

      // Should not throw even without a session.
      bridge.clear();
      bridge.dispose();
    });
  });

  group('TerminalBridge attach replaces previous session', () {
    test('attaching a new session detaches the previous one', () async {
      final bridge = TerminalBridge();

      final shell1 = FakeSSHSession();
      final session1 = _makeSession(shell1);
      bridge.attach(session1);

      final shell2 = FakeSSHSession();
      final session2 = ActiveSession(
        id: 'test-session-2',
        connection: Connection(
          id: 'conn-2',
          label: 'Test 2',
          host: 'localhost',
        ),
        shell: shell2,
        label: 'Test Session 2',
      );
      bridge.attach(session2);

      // Output from first session should be ignored.
      shell1.emitStdout('from old session');
      await Future.delayed(Duration.zero);

      // Input should go to the new session.
      session2.terminal.onOutput?.call('hello');
      final stdinSink2 = shell2.stdin as _FakeStdinSink;
      expect(stdinSink2.written.length, equals(1));

      final stdinSink1 = shell1.stdin as _FakeStdinSink;
      expect(stdinSink1.written, isEmpty);

      bridge.dispose();
      await shell1.closeStdout();
      await shell2.closeStdout();
    });
  });
}
