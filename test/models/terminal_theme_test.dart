import 'package:flutter_test/flutter_test.dart';
import 'package:unixshells/models/terminal_theme.dart';

void main() {
  group('terminalThemes', () {
    const expectedKeys = [
      'default',
      'solarized_dark',
      'monokai',
      'dracula',
      'nord',
      'gruvbox',
      'tokyo_night',
      'catppuccin',
    ];

    test('has all expected keys', () {
      for (final key in expectedKeys) {
        expect(terminalThemes.containsKey(key), isTrue,
            reason: 'missing theme key: $key');
      }
    });

    test('has exactly 8 themes', () {
      expect(terminalThemes.length, 8);
    });

    test('each theme has a non-empty name', () {
      for (final entry in terminalThemes.entries) {
        expect(entry.value.name.isNotEmpty, isTrue,
            reason: 'theme ${entry.key} has empty name');
      }
    });

    test('default theme exists and has correct name', () {
      final defaultTheme = terminalThemes['default'];
      expect(defaultTheme, isNotNull);
      expect(defaultTheme!.name, 'Default');
    });

    test('catppuccin theme has correct name', () {
      final theme = terminalThemes['catppuccin'];
      expect(theme, isNotNull);
      expect(theme!.name, 'Catppuccin Mocha');
    });

    test('no duplicate theme names', () {
      final names = terminalThemes.values.map((t) => t.name).toSet();
      expect(names.length, terminalThemes.length);
    });
  });
}
