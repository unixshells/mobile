import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/ssh_key.dart';
import '../../services/key_service.dart';
import '../../util/constants.dart';

class KeyListView extends StatefulWidget {
  const KeyListView({super.key});

  @override
  State<KeyListView> createState() => _KeyListViewState();
}

class _KeyListViewState extends State<KeyListView> {
  List<SSHKeyPair> _keys = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadKeys();
  }

  Future<void> _loadKeys() async {
    final keyService = context.read<KeyService>();
    final keys = await keyService.list();
    setState(() {
      _keys = keys;
      _loading = false;
    });
  }

  Future<void> _generateKey() async {
    final keyService = context.read<KeyService>();
    final labelCtrl = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgCard,
        title: const Text('Generate SSH Key',
            style: TextStyle(color: textBright)),
        content: TextField(
          controller: labelCtrl,
          autofocus: true,
          style: const TextStyle(color: textBright),
          decoration: const InputDecoration(
            hintText: 'Key label (e.g. iphone)',
            hintStyle: TextStyle(color: textMuted),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, labelCtrl.text.trim()),
            child: const Text('Generate'),
          ),
        ],
      ),
    );

    if (label == null || label.isEmpty) return;

    await keyService.generate(label);
    _loadKeys();
  }

  Future<void> _deleteKey(SSHKeyPair key) async {
    final keyService = context.read<KeyService>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgCard,
        title:
            const Text('Delete Key', style: TextStyle(color: textBright)),
        content: Text('Delete "${key.label}"? This cannot be undone.',
            style: const TextStyle(color: textDim)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await keyService.delete(key.id);
    _loadKeys();
  }

  Future<void> _importKey() async {
    final keyService = context.read<KeyService>();
    final messenger = ScaffoldMessenger.of(context);

    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;

    final content = String.fromCharCodes(bytes);
    final labelCtrl = TextEditingController(text: file.name);

    if (!mounted) return;
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgCard,
        title: const Text('Import SSH Key',
            style: TextStyle(color: textBright)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: labelCtrl,
              autofocus: true,
              style: const TextStyle(color: textBright),
              decoration: const InputDecoration(
                hintText: 'Key label',
                hintStyle: TextStyle(color: textMuted),
              ),
            ),
            const SizedBox(height: 8),
            Text('File: ${file.name}',
                style: const TextStyle(color: textMuted, fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, labelCtrl.text.trim()),
            child: const Text('Import'),
          ),
        ],
      ),
    );

    if (label == null || label.isEmpty) return;

    try {
      await keyService.importKey(label, content);
      _loadKeys();
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Key imported')),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Import failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgDark,
      appBar: AppBar(
        title: const Text('SSH Keys'),
        backgroundColor: bgCard,
        foregroundColor: textBright,
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload_outlined),
            onPressed: _importKey,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _keys.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.vpn_key,
                          size: 64, color: borderColor),
                      const SizedBox(height: 16),
                      const Text('No SSH keys',
                          style:
                              TextStyle(color: textMuted, fontSize: 16)),
                      const SizedBox(height: 8),
                      const Text('Generate one to get started',
                          style:
                              TextStyle(color: borderColor, fontSize: 14)),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _keys.length,
                  itemBuilder: (context, i) {
                    final key = _keys[i];
                    return ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: bgButton,
                        child: Icon(Icons.vpn_key,
                            color: textDim, size: 20),
                      ),
                      title: Text(key.label,
                          style: const TextStyle(color: textBright)),
                      subtitle: Text(key.fingerprint,
                          style: const TextStyle(
                              color: textMuted, fontSize: 12,
                              fontFamily: 'monospace')),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.copy,
                                color: textMuted, size: 20),
                            onPressed: () {
                              Clipboard.setData(
                                  ClipboardData(text: key.publicKeyOpenSSH));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Public key copied')),
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.red, size: 20),
                            onPressed: () => _deleteKey(key),
                          ),
                        ],
                      ),
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: bgCard,
                            title: Text(key.label,
                                style: const TextStyle(color: textBright)),
                            content: SelectableText(
                              key.publicKeyOpenSSH,
                              style: const TextStyle(
                                color: textDim,
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('Close'),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: accent,
        onPressed: _generateKey,
        child: const Icon(Icons.add),
      ),
    );
  }
}
