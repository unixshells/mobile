import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

// Test the OSC 52 parsing logic extracted from TerminalBridge.
// We can't test the full bridge without a WebView, but we can test the parsing.

void main() {
  group('OSC 52 parsing', () {
    test('detects OSC 52 sequence with BEL terminator', () {
      final text = 'Hello, world!';
      final b64 = base64Encode(utf8.encode(text));
      // ESC ] 52 ; c ; <base64> BEL
      final seq = '\x1b]52;c;$b64\x07';
      final payload = _extractOsc52(seq);
      expect(payload, isNotNull);
      expect(utf8.decode(base64Decode(payload!)), text);
    });

    test('detects OSC 52 sequence with ST terminator', () {
      final text = 'clipboard data';
      final b64 = base64Encode(utf8.encode(text));
      // ESC ] 52 ; c ; <base64> ESC backslash
      final seq = '\x1b]52;c;$b64\x1b\\';
      final payload = _extractOsc52(seq);
      expect(payload, isNotNull);
      expect(utf8.decode(base64Decode(payload!)), text);
    });

    test('ignores OSC 52 query', () {
      final seq = '\x1b]52;c;?\x07';
      final payload = _extractOsc52(seq);
      expect(payload, '?');
    });

    test('returns null for non-OSC data', () {
      final payload = _extractOsc52('just normal text');
      expect(payload, isNull);
    });

    test('handles mixed data with OSC 52', () {
      final text = 'test';
      final b64 = base64Encode(utf8.encode(text));
      final data = 'prefix\x1b]52;c;$b64\x07suffix';
      final payload = _extractOsc52(data);
      expect(payload, isNotNull);
      expect(utf8.decode(base64Decode(payload!)), text);
    });
  });
}

/// Simplified OSC 52 extraction matching terminal_bridge.dart logic.
String? _extractOsc52(String str) {
  final buf = StringBuffer();
  bool inOsc = false;

  for (var i = 0; i < str.length; i++) {
    if (inOsc) {
      if (str[i] == '\x07' ||
          (str[i] == '\\' && buf.toString().endsWith('\x1b'))) {
        var payload = buf.toString();
        if (payload.endsWith('\x1b')) {
          payload = payload.substring(0, payload.length - 1);
        }
        final parts = payload.split(';');
        if (parts.length >= 3) return parts.last;
        return null;
      } else {
        buf.write(str[i]);
      }
    } else if (i + 3 < str.length &&
        str[i] == '\x1b' &&
        str[i + 1] == ']' &&
        str[i + 2] == '5' &&
        str[i + 3] == '2') {
      inOsc = true;
      buf.clear();
      i += 3;
    }
  }
  return null;
}
