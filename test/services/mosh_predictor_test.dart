import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

import 'package:unixshells/services/mosh_framebuffer.dart';
import 'package:unixshells/services/mosh_predictor.dart';

/// Helper: build a snapshot with specific characters at positions.
FramebufferSnapshot _makeFB(int cols, int rows,
    {Map<int, int>? chars, int cursorX = 0, int cursorY = 0}) {
  final cells = Uint32List(rows * cols * 4);
  // Fill with spaces (matching FramebufferSnapshot._emptyContent).
  final emptyContent = 0x20 | (1 << CellContent.widthShift);
  for (var i = 0; i < rows * cols; i++) {
    cells[i * 4 + 3] = emptyContent;
  }
  if (chars != null) {
    for (final entry in chars.entries) {
      final off = entry.key * 4;
      // Set codepoint + width 1.
      cells[off + 3] = entry.value | (1 << CellContent.widthShift);
    }
  }
  return FramebufferSnapshot(
    cols: cols,
    rows: rows,
    cursorX: cursorX,
    cursorY: cursorY,
    cells: cells,
  );
}

void main() {
  group('MoshPredictor', () {
    test('basic echo — predictions created for printable chars', () {
      final p = MoshPredictor();
      p.setCursor(0, 0);
      p.keystroke('abc');
      expect(p.active, isTrue);
    });

    test('overlay produces ANSI output', () {
      final p = MoshPredictor();
      p.setCursor(0, 0);
      p.keystroke('hi');
      final fb = _makeFB(80, 24);
      final ansi = p.overlayAnsi(fb);
      // Should contain the predicted characters.
      expect(ansi, contains('h'));
      expect(ansi, contains('i'));
      // Should contain underline SGR.
      expect(ansi, contains('\x1b[4m'));
    });

    test('confirm all — predictions cleared', () {
      final p = MoshPredictor();
      p.setCursor(0, 0);
      p.keystroke('ab');

      // Server shows 'a' at (0,0) and 'b' at (1,0).
      final fb = _makeFB(80, 24, chars: {
        0: 0x61, // 'a'
        1: 0x62, // 'b'
      }, cursorX: 2, cursorY: 0);

      p.confirm(fb);
      expect(p.active, isFalse);
    });

    test('partial confirm — some predictions remain', () {
      final p = MoshPredictor();
      p.setCursor(0, 0);
      p.keystroke('abc');

      // Server confirms 'a' only.
      final fb = _makeFB(80, 24, chars: {
        0: 0x61, // 'a'
      }, cursorX: 1, cursorY: 0);

      p.confirm(fb);
      expect(p.active, isTrue);
    });

    test('divergence — predictions cleared', () {
      final p = MoshPredictor();
      p.setCursor(0, 0);
      p.keystroke('abc');

      // Server shows 'x' where we predicted 'a'.
      final fb = _makeFB(80, 24, chars: {
        0: 0x78, // 'x'
      }, cursorX: 5, cursorY: 0);

      p.confirm(fb);
      expect(p.active, isFalse);
    });

    test('control character resets', () {
      final p = MoshPredictor();
      p.setCursor(0, 0);
      p.keystroke('ab');
      expect(p.active, isTrue);

      p.keystroke('\n');
      expect(p.active, isFalse);
    });

    test('escape resets', () {
      final p = MoshPredictor();
      p.setCursor(0, 0);
      p.keystroke('ab');
      expect(p.active, isTrue);

      p.keystroke('\x1b');
      expect(p.active, isFalse);
    });

    test('setCursor tracks server when inactive', () {
      final p = MoshPredictor();
      p.setCursor(10, 5);
      // After typing, setCursor should not override predicted position.
      p.keystroke('x');
      p.setCursor(0, 0);
      // Predicted cursor should be at 11 (10 + 1 char typed).
      final fb = _makeFB(80, 24);
      final ansi = p.overlayAnsi(fb);
      // The CUP should position cursor at row 6 col 12 (1-indexed).
      expect(ansi, contains('\x1b[6;12H'));
    });

    test('expire stale predictions', () {
      final p = MoshPredictor();
      p.setCursor(0, 0);
      p.keystroke('a');
      expect(p.active, isTrue);

      // Can't easily backdate in Dart, but we can call expireStale
      // with a very short timeout to verify the mechanism works
      // after enough time passes.
      p.expireStale(timeout: Duration.zero);
      expect(p.active, isFalse);
    });

    test('no overlay when inactive', () {
      final p = MoshPredictor();
      final fb = _makeFB(80, 24);
      final ansi = p.overlayAnsi(fb);
      expect(ansi, isEmpty);
    });
  });
}
