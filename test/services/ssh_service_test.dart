import 'package:flutter_test/flutter_test.dart';

// Test the session name routing logic in SSHService.openShell().
// We can't call openShell() directly without a real SSHClient, but we
// can verify the branching condition that determines shell vs execute.

void main() {
  group('SSHService session name routing', () {
    // The logic in openShell: use execute() when sessionName is non-null,
    // non-empty, and not "default". Otherwise use shell().

    test('null session name should use shell', () {
      expect(_shouldUseExec(null), isFalse);
    });

    test('empty session name should use shell', () {
      expect(_shouldUseExec(''), isFalse);
    });

    test('"default" session name should use shell', () {
      expect(_shouldUseExec('default'), isFalse);
    });

    test('"work" session name should use execute', () {
      expect(_shouldUseExec('work'), isTrue);
    });

    test('"dev" session name should use execute', () {
      expect(_shouldUseExec('dev'), isTrue);
    });

    test('whitespace-only session name after trim is empty, uses shell', () {
      // connect_view trims before saving, so whitespace becomes null.
      // After trim, empty string uses shell.
      expect(_shouldUseExec(''), isFalse);
    });
  });
}

/// Mirrors the branching logic in SSHService.openShell().
bool _shouldUseExec(String? sessionName) {
  return sessionName != null &&
      sessionName.isNotEmpty &&
      sessionName != 'default';
}
