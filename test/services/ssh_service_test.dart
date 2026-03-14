import 'package:flutter_test/flutter_test.dart';

// Test the session name → SSH username logic in SSHService._connectRelay().
// The SSH username IS the session name. No more exec-based session selection.

void main() {
  group('SSHService relay username selection', () {
    // The logic in _connectRelay: use sessionName as SSH username,
    // falling back to "default" if empty/null.

    test('null session name should use "default"', () {
      expect(_relayUsername(null), equals('default'));
    });

    test('empty session name should use "default"', () {
      expect(_relayUsername(''), equals('default'));
    });

    test('"default" session name should use "default"', () {
      expect(_relayUsername('default'), equals('default'));
    });

    test('"work" session name should use "work"', () {
      expect(_relayUsername('work'), equals('work'));
    });

    test('"dev" session name should use "dev"', () {
      expect(_relayUsername('dev'), equals('dev'));
    });
  });
}

/// Mirrors the username selection logic in SSHService._connectRelay().
String _relayUsername(String? sessionName) {
  return (sessionName != null && sessionName.isNotEmpty)
      ? sessionName
      : 'default';
}
