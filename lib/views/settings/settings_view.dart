import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/terminal_theme.dart';
import '../../services/key_service.dart';
import '../../services/relay_api_service.dart';
import '../../services/storage_service.dart';
import '../../services/sync_service.dart';
import '../../util/constants.dart';

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
  bool _syncEnabled = false;
  String? _lastSync;
  bool _syncing = false;

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
    final syncEnabled = await storage.getSetting('sync_enabled');
    final lastSync = await storage.getSetting('last_sync');
    _selectedTheme = theme ?? 'default';
    _fontSize = double.tryParse(fontSize ?? '') ?? 14;
    _fontFamily = fontFamily ?? 'monospace';
    _syncEnabled = syncEnabled == 'true';
    _lastSync = lastSync;
    setState(() => _loaded = true);
  }

  Future<void> _saveSetting(String key, String value) async {
    final storage = context.read<StorageService>();
    await storage.saveSetting(key, value);
  }

  SyncService get _syncService => SyncService(
        context.read<StorageService>(),
        RelayApiService(),
        context.read<KeyService>(),
      );

  Future<void> _pushSync() async {
    setState(() => _syncing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _syncService.push();
      final lastSync = await _syncService.lastSync();
      if (mounted) setState(() => _lastSync = lastSync);
      messenger.showSnackBar(
        const SnackBar(content: Text('Config pushed to cloud')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Push failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _pullSync() async {
    setState(() => _syncing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ok = await _syncService.pull();
      final lastSync = await _syncService.lastSync();
      if (mounted) setState(() => _lastSync = lastSync);
      messenger.showSnackBar(
        SnackBar(
          content: Text(ok ? 'Config pulled from cloud' : 'No cloud data found'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Pull failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
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

      final merge = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: bgCard,
          title: const Text('Import Backup',
              style: TextStyle(color: Colors.white)),
          content: const Text('How should existing data be handled?',
              style: TextStyle(color: Colors.white70)),
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
    return Scaffold(
      backgroundColor: bgDark,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: bgCard,
        foregroundColor: Colors.white,
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Terminal section.
                _sectionHeader('Terminal Theme'),
                _buildThemePicker(),
                const SizedBox(height: 16),
                _sectionHeader('Font'),
                _buildFontSizeSlider(),
                const SizedBox(height: 12),
                _buildFontFamilyPicker(),

                const SizedBox(height: 24),
                _sectionHeader('Cloud Sync'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Sync via Relay',
                      style: TextStyle(color: Colors.white)),
                  subtitle: Text(
                    _lastSync != null
                        ? 'Last synced: $_lastSync'
                        : 'Sync connections, keys, and settings across devices',
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  value: _syncEnabled,
                  onChanged: (v) {
                    setState(() => _syncEnabled = v);
                    _saveSetting('sync_enabled', v.toString());
                  },
                ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: _syncing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white54))
                            : const Icon(Icons.cloud_upload_outlined,
                                size: 18),
                        label: const Text('Push'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Colors.white24),
                        ),
                        onPressed: _syncing ? null : _pushSync,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.cloud_download_outlined,
                            size: 18),
                        label: const Text('Pull'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Colors.white24),
                        ),
                        onPressed: _syncing ? null : _pullSync,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),
                _sectionHeader('Local Backup'),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.upload_outlined,
                      color: Colors.white54),
                  title: const Text('Export Backup',
                      style: TextStyle(color: Colors.white)),
                  subtitle: const Text(
                      'Save connections, keys, and settings to a file',
                      style: TextStyle(color: Colors.white38, fontSize: 12)),
                  onTap: _exportBackup,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.download_outlined,
                      color: Colors.white54),
                  title: const Text('Import Backup',
                      style: TextStyle(color: Colors.white)),
                  subtitle: const Text(
                      'Restore from a backup file',
                      style: TextStyle(color: Colors.white38, fontSize: 12)),
                  onTap: _importBackup,
                ),

                const SizedBox(height: 24),
                _sectionHeader('About'),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Version',
                      style: TextStyle(color: Colors.white)),
                  subtitle: const Text('1.0.0',
                      style: TextStyle(color: Colors.white38)),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Website',
                      style: TextStyle(color: Colors.white)),
                  subtitle: const Text('unixshells.com',
                      style: TextStyle(color: Colors.blue)),
                  onTap: () =>
                      launchUrl(Uri.parse('https://unixshells.com')),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Licenses',
                      style: TextStyle(color: Colors.white)),
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
                  color: selected ? Colors.blue : Colors.white12,
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
        const Text('Size', style: TextStyle(color: Colors.white70)),
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
            style: const TextStyle(color: Colors.white54, fontSize: 13)),
      ],
    );
  }

  Widget _buildFontFamilyPicker() {
    return DropdownButtonFormField<String>(
      initialValue: _fontFamily,
      dropdownColor: bgCard,
      style: const TextStyle(color: Colors.white),
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
        labelStyle: const TextStyle(color: Colors.white54),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.white24),
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.blue),
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
              color: Colors.white54,
              fontSize: 13,
              fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildField(
    TextEditingController ctrl,
    String label,
    String hint, {
    void Function(String)? onSubmitted,
  }) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: Colors.white),
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.white24),
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.blue),
          borderRadius: BorderRadius.circular(8),
        ),
        filled: true,
        fillColor: bgCard,
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}
