import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart' as xterm;

import '../../models/terminal_theme.dart';
import '../../services/storage_service.dart';
import '../../util/constants.dart';

class LocalTerminalView extends StatefulWidget {
  const LocalTerminalView({super.key});

  @override
  State<LocalTerminalView> createState() => _LocalTerminalViewState();
}

class _LocalTerminalViewState extends State<LocalTerminalView> {
  late xterm.Terminal _terminal;
  Pty? _pty;
  final bool _showExtraKeys = true;
  bool _ctrlActive = false;

  String _themeId = 'default';
  double _fontSize = 14;
  String _fontFamily = 'monospace';

  @override
  void initState() {
    super.initState();
    _terminal = xterm.Terminal(maxLines: 10000);
    _loadSettings();
    _startShell();
  }

  Future<void> _loadSettings() async {
    final storage = context.read<StorageService>();
    final theme = await storage.getSetting('theme');
    final fontSize = await storage.getSetting('font_size');
    final fontFamily = await storage.getSetting('font_family');
    if (mounted) {
      setState(() {
        _themeId = theme ?? 'default';
        _fontSize = double.tryParse(fontSize ?? '') ?? 14;
        _fontFamily = fontFamily ?? 'monospace';
      });
    }
  }

  void _startShell() {
    String shell;
    if (Platform.isAndroid) {
      shell = '/system/bin/sh';
    } else {
      shell = Platform.environment['SHELL'] ?? (Platform.isMacOS ? '/bin/zsh' : '/bin/bash');
    }
    final env = Platform.environment;

    _pty = Pty.start(
      shell,
      environment: {
        ...env,
        'TERM': 'xterm-256color',
      },
      columns: 80,
      rows: 24,
    );

    _pty!.output.listen((data) {
      _terminal.write(utf8.decode(data, allowMalformed: true));
    });

    _terminal.onOutput = (data) {
      _pty!.write(utf8.encoder.convert(data));
    };

    _terminal.onResize = (cols, rows, pixelWidth, pixelHeight) {
      _pty!.resize(rows, cols);
    };
  }

  xterm.TerminalTheme _buildXtermTheme() {
    final t = terminalThemes[_themeId] ?? terminalThemes['default']!;
    return xterm.TerminalTheme(
      cursor: t.cursor,
      selection: t.selection,
      foreground: t.foreground,
      background: t.background,
      black: t.black,
      red: t.red,
      green: t.green,
      yellow: t.yellow,
      blue: t.blue,
      magenta: t.magenta,
      cyan: t.cyan,
      white: t.white,
      brightBlack: t.brightBlack,
      brightRed: t.brightRed,
      brightGreen: t.brightGreen,
      brightYellow: t.brightYellow,
      brightBlue: t.brightBlue,
      brightMagenta: t.brightMagenta,
      brightCyan: t.brightCyan,
      brightWhite: t.brightWhite,
      searchHitBackground: const Color(0xFFFFDF5D),
      searchHitBackgroundCurrent: const Color(0xFFFF9632),
      searchHitForeground: const Color(0xFF000000),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgDark,
      appBar: AppBar(
        backgroundColor: bgCard,
        foregroundColor: Colors.white,
        title: const Text('Local Terminal'),
        titleTextStyle: const TextStyle(fontSize: 16, color: Colors.white),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: xterm.TerminalView(
                _terminal,
                theme: _buildXtermTheme(),
                textStyle: xterm.TerminalStyle(
                  fontSize: _fontSize,
                  fontFamily: _fontFamily,
                ),
                autofocus: true,
                deleteDetection: true,
              ),
            ),
            if (_showExtraKeys) _buildExtraKeys(),
          ],
        ),
      ),
    );
  }

  Widget _buildExtraKeys() {
    return Container(
      color: bgCard,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _extraKey('Esc', '\x1b'),
            _extraKey('Tab', '\x09'),
            _extraKey('Ctrl', null, isModifier: true),
            _extraKey('|', '|'),
            _extraKey('/', '/'),
            _extraKey('-', '-'),
            _extraKey('_', '_'),
            _extraKey('~', '~'),
            _extraKey('.', '.'),
            _extraKey(':', ':'),
            _extraKey('@', '@'),
            _extraKey('#', '#'),
            _extraKey('\$', '\$'),
            _extraKey('\u2190', '\x1b[D'),
            _extraKey('\u2191', '\x1b[A'),
            _extraKey('\u2193', '\x1b[B'),
            _extraKey('\u2192', '\x1b[C'),
          ],
        ),
      ),
    );
  }

  Widget _extraKey(String label, String? sequence,
      {bool isModifier = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          if (isModifier) {
            setState(() => _ctrlActive = !_ctrlActive);
            return;
          }
          if (sequence != null) {
            if (_ctrlActive && sequence.length == 1) {
              final code = sequence.codeUnitAt(0) & 0x1f;
              _terminal.textInput(String.fromCharCode(code));
              setState(() => _ctrlActive = false);
            } else {
              _terminal.textInput(sequence);
            }
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: (isModifier && _ctrlActive)
                ? Colors.blue.withValues(alpha: 0.3)
                : bgButton,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pty?.kill();
    super.dispose();
  }
}
