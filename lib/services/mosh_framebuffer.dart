import 'dart:typed_data';

import 'package:xterm/xterm.dart';

/// Compact snapshot of a terminal viewport for framebuffer diffing.
///
/// Each cell is stored as 4 ints in a Uint32List: [fg, bg, attrs, content].
/// This allows O(1) per-cell comparison and minimal ANSI output.
class FramebufferSnapshot {
  final int cols;
  final int rows;
  final int cursorX;
  final int cursorY;
  final Uint32List cells; // rows * cols * 4

  FramebufferSnapshot({
    required this.cols,
    required this.rows,
    required this.cursorX,
    required this.cursorY,
    required this.cells,
  });

  /// Snapshot the viewport of a Terminal into a compact Uint32List.
  /// Empty cell content: space with width 1. Matches Go framebuffer init.
  /// Without this, empty cells have content=0 (width=0) and get skipped
  /// as "continuation cells" during diff/redraw.
  static final int _emptyContent = 0x20 | (1 << CellContent.widthShift);

  static FramebufferSnapshot fromTerminal(Terminal t) {
    final cols = t.viewWidth;
    final rows = t.viewHeight;
    final buf = t.buffer;
    final cells = Uint32List(rows * cols * 4);
    final cd = CellData.empty();

    for (var y = 0; y < rows; y++) {
      final lineIdx = buf.scrollBack + y;
      final line = (lineIdx < buf.lines.length) ? buf.lines[lineIdx] : null;
      final rowOff = y * cols * 4;

      for (var x = 0; x < cols; x++) {
        final cellOff = rowOff + x * 4;
        if (line != null && x < line.length) {
          line.getCellData(x, cd);
          cells[cellOff] = cd.foreground;
          cells[cellOff + 1] = cd.background;
          cells[cellOff + 2] = cd.flags;
          // Normalize empty cells to space+width1. In xterm, empty/erased
          // cells have content=0 (width=0). Continuation cells (second half
          // of a wide char) also have content=0 but follow a width-2 cell.
          if (cd.content == 0) {
            bool isContinuation = false;
            if (x > 0) {
              final prevWidth = cells[cellOff - 4 + 3] >> CellContent.widthShift;
              isContinuation = prevWidth > 1;
            }
            cells[cellOff + 3] = isContinuation ? 0 : _emptyContent;
          } else {
            cells[cellOff + 3] = cd.content;
          }
        } else {
          // Beyond line length or no line — empty cell.
          cells[cellOff + 3] = _emptyContent;
        }
      }
    }

    return FramebufferSnapshot(
      cols: cols,
      rows: rows,
      cursorX: buf.cursorX,
      cursorY: buf.cursorY,
      cells: cells,
    );
  }

  /// Generate minimal ANSI to transform [old] into this snapshot.
  /// If [old] is null or dimensions differ, produces a full redraw.
  String diffAnsi(FramebufferSnapshot? old) {
    if (old == null || old.cols != cols || old.rows != rows) {
      return fullRedrawAnsi();
    }

    final sb = StringBuffer();
    sb.write('\x1b[?25l'); // hide cursor

    int curFg = 0, curBg = 0, curFlags = 0;
    int cx = -1, cy = -1;

    for (var y = 0; y < rows; y++) {
      final rowOff = y * cols * 4;

      // Find first and last changed column.
      var first = -1, last = -1;
      for (var x = 0; x < cols; x++) {
        final off = rowOff + x * 4;
        if (cells[off] != old.cells[off] ||
            cells[off + 1] != old.cells[off + 1] ||
            cells[off + 2] != old.cells[off + 2] ||
            cells[off + 3] != old.cells[off + 3]) {
          if (first < 0) first = x;
          last = x;
        }
      }
      if (first < 0) continue;

      if (cx != first || cy != y) {
        _appendCUP(sb, y, first);
        cx = first;
        cy = y;
      }

      for (var x = first; x <= last; x++) {
        final off = rowOff + x * 4;
        final content = cells[off + 3];
        final width = content >> CellContent.widthShift;
        if (width == 0) continue; // continuation cell

        final fg = cells[off];
        final bg = cells[off + 1];
        final flags = cells[off + 2];
        _appendAttrDiff(sb, curFg, curBg, curFlags, fg, bg, flags);
        curFg = fg;
        curBg = bg;
        curFlags = flags;

        final cp = content & CellContent.codepointMask;
        sb.writeCharCode(cp == 0 ? 0x20 : cp);
        cx += width > 0 ? width : 1;
      }
    }

    // Reset attributes if any are active.
    if (curFg != 0 || curBg != 0 || curFlags != 0) {
      sb.write('\x1b[m');
    }

    _appendCUP(sb, cursorY, cursorX);
    sb.write('\x1b[?25h'); // show cursor

    return sb.toString();
  }

  /// Generate ANSI to draw the entire screen from scratch.
  String fullRedrawAnsi() {
    final sb = StringBuffer();
    sb.write('\x1b[?25l'); // hide cursor
    sb.write('\x1b[H');    // home
    sb.write('\x1b[2J');   // clear screen
    sb.write('\x1b[m');    // reset attrs

    int curFg = 0, curBg = 0, curFlags = 0;

    for (var y = 0; y < rows; y++) {
      if (y > 0) sb.write('\r\n');
      final rowOff = y * cols * 4;

      // Find last non-empty cell to avoid trailing spaces.
      var lastNonSpace = -1;
      for (var x = cols - 1; x >= 0; x--) {
        final off = rowOff + x * 4;
        final cp = cells[off + 3] & CellContent.codepointMask;
        if ((cp != 0 && cp != 0x20) ||
            cells[off] != 0 || cells[off + 1] != 0 || cells[off + 2] != 0) {
          lastNonSpace = x;
          break;
        }
      }

      for (var x = 0; x <= lastNonSpace; x++) {
        final off = rowOff + x * 4;
        final content = cells[off + 3];
        final width = content >> CellContent.widthShift;
        if (width == 0) continue;

        final fg = cells[off];
        final bg = cells[off + 1];
        final flags = cells[off + 2];
        _appendAttrDiff(sb, curFg, curBg, curFlags, fg, bg, flags);
        curFg = fg;
        curBg = bg;
        curFlags = flags;

        final cp = content & CellContent.codepointMask;
        sb.writeCharCode(cp == 0 ? 0x20 : cp);
      }
    }

    if (curFg != 0 || curBg != 0 || curFlags != 0) {
      sb.write('\x1b[m');
    }
    _appendCUP(sb, cursorY, cursorX);
    sb.write('\x1b[?25h');

    return sb.toString();
  }
}

/// Append CUP (cursor position) escape — 1-indexed.
void _appendCUP(StringBuffer sb, int row, int col) {
  sb.write('\x1b[');
  sb.write(row + 1);
  sb.write(';');
  sb.write(col + 1);
  sb.write('H');
}

/// Append SGR sequences to transition between attribute states.
///
/// Colors use xterm's packed encoding:
/// - CellColor.normal (type 0): default color
/// - CellColor.named (type 1): 16 named colors (value 0-15)
/// - CellColor.palette (type 2): 256 palette (value 0-255)
/// - CellColor.rgb (type 3): 24-bit RGB (value = 0xRRGGBB)
void _appendAttrDiff(
  StringBuffer sb,
  int curFg, int curBg, int curFlags,
  int newFg, int newBg, int newFlags,
) {
  if (curFg == newFg && curBg == newBg && curFlags == newFlags) return;

  // Check if any attribute is being removed — if so, reset first.
  final removedFlags = curFlags & ~newFlags;
  final curFgType = curFg & CellColor.typeMask;
  final newFgType = newFg & CellColor.typeMask;
  final curBgType = curBg & CellColor.typeMask;
  final newBgType = newBg & CellColor.typeMask;

  final needsReset = removedFlags != 0 ||
      (curFgType != CellColor.normal && newFgType == CellColor.normal) ||
      (curBgType != CellColor.normal && newBgType == CellColor.normal);

  final params = <String>[];
  int baseFg, baseBg, baseFlags;

  if (needsReset) {
    params.add('0');
    baseFg = 0;
    baseBg = 0;
    baseFlags = 0;
  } else {
    baseFg = curFg;
    baseBg = curBg;
    baseFlags = curFlags;
  }

  // Flags.
  if (newFlags & CellAttr.bold != 0 && baseFlags & CellAttr.bold == 0) {
    params.add('1');
  }
  if (newFlags & CellAttr.faint != 0 && baseFlags & CellAttr.faint == 0) {
    params.add('2');
  }
  if (newFlags & CellAttr.italic != 0 && baseFlags & CellAttr.italic == 0) {
    params.add('3');
  }
  if (newFlags & CellAttr.underline != 0 &&
      baseFlags & CellAttr.underline == 0) {
    params.add('4');
  }
  if (newFlags & CellAttr.blink != 0 && baseFlags & CellAttr.blink == 0) {
    params.add('5');
  }
  if (newFlags & CellAttr.inverse != 0 && baseFlags & CellAttr.inverse == 0) {
    params.add('7');
  }
  if (newFlags & CellAttr.strikethrough != 0 &&
      baseFlags & CellAttr.strikethrough == 0) {
    params.add('9');
  }

  // Foreground.
  if (newFg != baseFg) {
    _appendColorParams(params, newFg, true);
  }

  // Background.
  if (newBg != baseBg) {
    _appendColorParams(params, newBg, false);
  }

  sb.write('\x1b[');
  sb.write(params.join(';'));
  sb.write('m');
}

/// Append SGR color parameters for a packed xterm color value.
void _appendColorParams(List<String> params, int color, bool fg) {
  final type = color & CellColor.typeMask;
  final value = color & CellColor.valueMask;

  switch (type) {
    case CellColor.normal:
      params.add(fg ? '39' : '49');
    case CellColor.named:
      if (value < 8) {
        params.add('${fg ? 30 + value : 40 + value}');
      } else if (value < 16) {
        params.add('${fg ? 90 + value - 8 : 100 + value - 8}');
      } else {
        // Shouldn't happen for named, but handle gracefully.
        params.addAll(fg ? ['38', '5', '$value'] : ['48', '5', '$value']);
      }
    case CellColor.palette:
      params.addAll(fg ? ['38', '5', '$value'] : ['48', '5', '$value']);
    case CellColor.rgb:
      final r = (value >> 16) & 0xff;
      final g = (value >> 8) & 0xff;
      final b = value & 0xff;
      params.addAll(fg ? ['38', '2', '$r', '$g', '$b'] : ['48', '2', '$r', '$g', '$b']);
  }
}
