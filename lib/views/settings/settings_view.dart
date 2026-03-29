import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/terminal_theme.dart';
import '../../services/storage_service.dart';
import '../../util/constants.dart';
import '../account/account_view.dart';
import '../keys/key_list_view.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  bool _loaded = false;
  String _selectedTheme = 'default';
  double _fontSize = 14;
  String _fontFamily = 'monospace';

  static const _fontFamilies = [
    'monospace',
    'Courier New',
    'Menlo',
    'Fira Code',
    'JetBrains Mono',
    'Source Code Pro',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final storage = context.read<StorageService>();
    final theme = await storage.getSetting('theme');
    final fontSize = await storage.getSetting('font_size');
    final fontFamily = await storage.getSetting('font_family');
    _selectedTheme = theme ?? 'default';
    _fontSize = double.tryParse(fontSize ?? '') ?? 14;
    _fontFamily = fontFamily ?? 'monospace';
    setState(() => _loaded = true);
  }

  Future<void> _saveSetting(String key, String value) async {
    final storage = context.read<StorageService>();
    await storage.saveSetting(key, value);
  }

  Future<void> _clearHostKeys() async {
    final storage = context.read<StorageService>();
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgCard,
        title: const Text('Clear Host Keys',
            style: TextStyle(color: textBright)),
        content: const Text(
            'This will remove all cached host key fingerprints. '
            'You will be prompted to accept host keys again on next connect.',
            style: TextStyle(color: textDim)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await storage.clearHostKeys();
    messenger.showSnackBar(
      const SnackBar(content: Text('Host keys cleared')),
    );
  }

  Future<void> _exportBackup() async {
    final storage = context.read<StorageService>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final json = await storage.exportData();
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Backup',
        fileName: 'unixshells-backup.json',
        bytes: Uint8List.fromList(json.codeUnits),
      );
      if (result != null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Backup exported')),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    }
  }

  Future<void> _importBackup() async {
    final storage = context.read<StorageService>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final bytes = result.files.first.bytes;
      if (bytes == null) return;
      final json = String.fromCharCodes(bytes);

      if (!mounted) return;
      final merge = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: bgCard,
          title: const Text('Import Backup',
              style: TextStyle(color: textBright)),
          content: const Text('How should existing data be handled?',
              style: TextStyle(color: textDim)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Replace All'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Merge'),
            ),
          ],
        ),
      );
      if (merge == null) return;

      await storage.importData(json, merge: merge);
      messenger.showSnackBar(
        SnackBar(content: Text(merge ? 'Backup merged' : 'Backup imported')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Import failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Material(
              color: bgDark,
              child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _sectionHeader('SSH Keys'),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.vpn_key_outlined, color: textDim),
                  title: const Text('Manage Keys', style: TextStyle(color: textBright)),
                  subtitle: const Text('Generate, import, and manage SSH keys', style: TextStyle(color: textMuted, fontSize: 12)),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: textMuted),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const KeyListView()),
                  ),
                ),

                const SizedBox(height: 24),
                _sectionHeader('Terminal Theme'),
                _buildThemePicker(),
                const SizedBox(height: 16),
                _sectionHeader('Font'),
                _buildFontSizeSlider(),
                const SizedBox(height: 12),
                _buildFontFamilyPicker(),

                const SizedBox(height: 24),
                _sectionHeader('Local Backup'),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.upload_outlined,
                      color: textDim),
                  title: const Text('Export Backup',
                      style: TextStyle(color: textBright)),
                  subtitle: const Text(
                      'Save connections, keys, and settings to a file',
                      style: TextStyle(color: textMuted, fontSize: 12)),
                  onTap: _exportBackup,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.download_outlined,
                      color: textDim),
                  title: const Text('Import Backup',
                      style: TextStyle(color: textBright)),
                  subtitle: const Text(
                      'Restore from a backup file',
                      style: TextStyle(color: textMuted, fontSize: 12)),
                  onTap: _importBackup,
                ),

                const SizedBox(height: 24),
                _sectionHeader('Security'),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.key_off_outlined,
                      color: textDim),
                  title: const Text('Clear Host Keys',
                      style: TextStyle(color: textBright)),
                  subtitle: const Text(
                      'Remove cached SSH host key fingerprints',
                      style: TextStyle(color: textMuted, fontSize: 12)),
                  onTap: _clearHostKeys,
                ),

                const SizedBox(height: 24),
                _sectionHeader('About'),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Version',
                      style: TextStyle(color: textBright)),
                  subtitle: const Text('1.0.0',
                      style: TextStyle(color: textMuted)),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Licenses',
                      style: TextStyle(color: textBright)),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: 'Unix Shells',
                    applicationVersion: '1.0.0',
                  ),
                ),
              ],
            ),
  );
  }

  Widget _buildThemePicker() {
    return SizedBox(
      height: 80,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: terminalThemes.entries.map((entry) {
          final id = entry.key;
          final theme = entry.value;
          final selected = _selectedTheme == id;
          return GestureDetector(
            onTap: () {
              setState(() => _selectedTheme = id);
              _saveSetting('theme', id);
            },
            child: Container(
              width: 100,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: theme.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected ? accent : borderColor,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _colorDot(theme.red),
                      _colorDot(theme.green),
                      _colorDot(theme.yellow),
                      _colorDot(theme.blue),
                      _colorDot(theme.magenta),
                      _colorDot(theme.cyan),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    theme.name,
                    style: TextStyle(
                      color: theme.foreground,
                      fontSize: 10,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _colorDot(Color color) {
    return Container(
      width: 10,
      height: 10,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Widget _buildFontSizeSlider() {
    return Row(
      children: [
        const Text('Size', style: TextStyle(color: textDim)),
        Expanded(
          child: Slider(
            value: _fontSize,
            min: 8,
            max: 24,
            divisions: 16,
            label: _fontSize.round().toString(),
            onChanged: (v) {
              setState(() => _fontSize = v);
              _saveSetting('font_size', v.round().toString());
            },
          ),
        ),
        Text('${_fontSize.round()}',
            style: const TextStyle(color: textDim, fontSize: 13)),
      ],
    );
  }

  Widget _buildFontFamilyPicker() {
    return DropdownButtonFormField<String>(
      initialValue: _fontFamily,
      dropdownColor: bgCard,
      style: const TextStyle(color: textBright),
      items: _fontFamilies
          .map((f) => DropdownMenuItem(
                value: f,
                child: Text(f, style: TextStyle(fontFamily: f)),
              ))
          .toList(),
      onChanged: (v) {
        if (v == null) return;
        setState(() => _fontFamily = v);
        _saveSetting('font_family', v);
      },
      decoration: InputDecoration(
        labelText: 'Font Family',
        labelStyle: const TextStyle(color: textDim),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: borderColor),
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: accent),
          borderRadius: BorderRadius.circular(8),
        ),
        filled: true,
        fillColor: bgCard,
      ),
    );
  }

  Widget _sectionHeader(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: const TextStyle(
              color: textDim,
              fontSize: 13,
              fontWeight: FontWeight.w600)),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}
