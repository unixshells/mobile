import 'dart:typed_data';

import 'package:xterm/xterm.dart';

import 'mosh_framebuffer.dart';

/// Mosh-style speculative local echo.
///
/// When the user types a printable character, it is predicted to appear
/// at the current cursor position and the cursor advances. When the
/// server confirms the character (it appears in the server framebuffer
/// at the expected position), the prediction is retired. If the server
/// diverges, all predictions are cleared.
class MoshPredictor {
  final List<_Prediction> _pending = [];
  int _curX = 0;
  int _curY = 0;
  int _epoch = 0;
  bool _active = false;

  /// Whether there are pending predictions.
  bool get active => _active && _pending.isNotEmpty;

  /// Process user input. Returns true if predictions were added.
  bool keystroke(String input) {
    for (var i = 0; i < input.length; i++) {
      final cp = input.codeUnitAt(i);

      // Control characters — can't predict.
      if (cp < 0x20 || cp == 0x7f) {
        reset();
        return false;
      }

      // High surrogate — skip, handle as pair.
      if (cp >= 0xD800 && cp <= 0xDBFF) continue;

      int rune;
      if (cp >= 0xDC00 && cp <= 0xDFFF && i > 0) {
        // Low surrogate — combine with previous high surrogate.
        final hi = input.codeUnitAt(i - 1);
        rune = 0x10000 + ((hi - 0xD800) << 10) + (cp - 0xDC00);
      } else {
        rune = cp;
      }

      _pending.add(_Prediction(
        rune: rune,
        x: _curX,
        y: _curY,
        epoch: _epoch,
        at: DateTime.now(),
      ));
      _curX++;
      _active = true;
    }
    return _active;
  }

  /// Reset all predictions.
  void reset() {
    _pending.clear();
    _epoch++;
    _active = false;
  }

  /// Update predicted cursor from server state (when no predictions active).
  void setCursor(int x, int y) {
    if (!_active) {
      _curX = x;
      _curY = y;
    }
  }

  /// Remove predictions older than the timeout.
  void expireStale({Duration timeout = const Duration(milliseconds: 500)}) {
    final cutoff = DateTime.now().subtract(timeout);
    var changed = false;
    while (_pending.isNotEmpty && _pending.first.at.isBefore(cutoff)) {
      _pending.removeAt(0);
      changed = true;
    }
    if (changed && _pending.isEmpty) {
      _active = false;
    }
  }

  /// Confirm predictions against server framebuffer.
  void confirm(FramebufferSnapshot fb) {
    if (!_active || _pending.isEmpty) {
      _curX = fb.cursorX;
      _curY = fb.cursorY;
      return;
    }

    var confirmed = 0;
    while (confirmed < _pending.length) {
      final pred = _pending[confirmed];
      if (pred.epoch != _epoch) {
        confirmed++;
        continue;
      }

      if (pred.x < 0 || pred.x >= fb.cols || pred.y < 0 || pred.y >= fb.rows) {
        reset();
        _curX = fb.cursorX;
        _curY = fb.cursorY;
        return;
      }

      final cellCp = _cellCodepoint(fb, pred.x, pred.y);
      if (cellCp == pred.rune) {
        confirmed++;
      } else if ((cellCp == 0x20 || cellCp == 0) && pred.rune != 0x20) {
        // Server hasn't caught up yet (but if we predicted a space, a space is a match).
        break;
      } else {
        // Server diverged.
        reset();
        _curX = fb.cursorX;
        _curY = fb.cursorY;
        return;
      }
    }

    if (confirmed > 0) {
      _pending.removeRange(0, confirmed);
    }

    if (_pending.isEmpty) {
      _active = false;
      _curX = fb.cursorX;
      _curY = fb.cursorY;
    }
  }

  /// Apply prediction overlay to a snapshot, returning ANSI for the
  /// predicted characters. Predictions are underlined to indicate
  /// they are speculative.
  String overlayAnsi(FramebufferSnapshot fb) {
    if (!_active || _pending.isEmpty) return '';

    final sb = StringBuffer();
    sb.write('\x1b[?25l'); // hide cursor

    for (final pred in _pending) {
      if (pred.epoch != _epoch) continue;
      if (pred.x < 0 || pred.x >= fb.cols || pred.y < 0 || pred.y >= fb.rows) {
        continue;
      }
      _appendCUP(sb, pred.y, pred.x);
      sb.write('\x1b[4m'); // underline
      sb.writeCharCode(pred.rune);
      sb.write('\x1b[24m'); // underline off
    }

    // Move cursor to predicted position.
    _appendCUP(sb, _curY, _curX);
    sb.write('\x1b[?25h'); // show cursor
    return sb.toString();
  }

  /// Get the codepoint at (x, y) in a snapshot.
  static int _cellCodepoint(FramebufferSnapshot fb, int x, int y) {
    final off = (y * fb.cols + x) * 4;
    if (off + 3 >= fb.cells.length) return 0;
    return fb.cells[off + 3] & CellContent.codepointMask;
  }

  static void _appendCUP(StringBuffer sb, int row, int col) {
    sb.write('\x1b[');
    sb.write(row + 1);
    sb.write(';');
    sb.write(col + 1);
    sb.write('H');
  }
}

class _Prediction {
  final int rune;
  final int x;
  final int y;
  final int epoch;
  final DateTime at;

  _Prediction({
    required this.rune,
    required this.x,
    required this.y,
    required this.epoch,
    required this.at,
  });
}
