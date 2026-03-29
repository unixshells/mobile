import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:provider/provider.dart';

import '../../models/shell.dart';
import '../../services/demo_service.dart';
import '../../services/iap_service.dart';
import '../../services/key_service.dart';
import '../../services/relay_api_service.dart';
import '../../services/storage_service.dart';

/// Shells management tab. Lists shells, create/destroy/restart.
/// Shells also appear as devices in the Unix Shells tab for connecting.
class ShellsTab extends StatefulWidget {
  const ShellsTab({super.key});

  @override
  State<ShellsTab> createState() => _ShellsTabState();
}

class _ShellsTabState extends State<ShellsTab> {
  final _api = RelayApiService();
  final _iap = IAPService();
  List<Shell> _shells = [];
  bool _loading = true;
  String? _message;

  @override
  void initState() {
    super.initState();
    _iap.init();
    _iap.addListener(_onIAPUpdate);
    _refresh();
  }

  @override
  void dispose() {
    _iap.removeListener(_onIAPUpdate);
    _iap.dispose();
    super.dispose();
  }

  void _onIAPUpdate() {
    if (_iap.error != null) _showMessage(_iap.error!);
    if (_iap.successMessage != null) {
      _showMessage(_iap.successMessage!);
      _refresh(); // Reload shells after purchase
    }
    if (mounted) setState(() {});
  }

  Future<String?> _getAuthToken() async {
    final keyService = context.read<KeyService>();
    final storage = context.read<StorageService>();
    final keys = await keyService.list();
    if (keys.isEmpty) return null;

    final savedKeyId = await storage.getSetting('relay_key_id');
    var key = savedKeyId != null
        ? keys.where((k) => k.id == savedKeyId).firstOrNull
        : null;
    key ??= keys.where((k) => k.label.startsWith('relay-')).firstOrNull;
    if (key == null) return null;

    final identities = await keyService.loadIdentity(key.id);
    if (identities.isEmpty) return null;

    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final sig = identities.first.sign(Uint8List.fromList(utf8.encode(timestamp)));
    final token = base64Encode(sig.encode());
    return '$timestamp:$token';
  }

  Future<String?> _getUsername() async {
    final storage = context.read<StorageService>();
    final account = await storage.getAccount();
    return account?.username;
  }

  Future<void> _refresh() async {
    final demo = DemoService();
    if (demo.isActive) {
      if (mounted) setState(() { _shells = demo.shells; _loading = false; });
      return;
    }
    setState(() => _loading = true);
    try {
      final token = await _getAuthToken();
      if (token == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final shells = await _api.listShells(token: token);
      if (mounted) setState(() { _shells = shells; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; });
    }
  }

  Future<void> _destroyShell(Shell shell) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Destroy shell'),
        content: Text('Destroy ${shell.id}?\n\nHome directory data retained for 30 days. Subscription canceled immediately.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Destroy'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final token = await _getAuthToken();
      if (token == null) return;
      final msg = await _api.destroyShell(shell.id, token: token);
      _showMessage(msg);
      _refresh();
    } catch (e) {
      _showMessage(e.toString());
    }
  }

  Future<void> _restartShell(Shell shell) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restart shell'),
        content: Text('Restart ${shell.id}?\n\nVM reprovisioned, home directory preserved.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Restart')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final token = await _getAuthToken();
      if (token == null) return;
      final msg = await _api.restartShell(shell.id, token: token);
      _showMessage(msg);
      _refresh();
    } catch (e) {
      _showMessage(e.toString());
    }
  }

  void _showMessage(String msg) {
    if (mounted) {
      setState(() => _message = msg);
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) setState(() => _message = null);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Manage Shells', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              ),
              _iap.available && _iap.products.isNotEmpty
                  ? PopupMenuButton<ProductDetails>(
                      onSelected: (product) async {
                        _iap.username = await _getUsername() ?? '';
                        _iap.authToken = await _getAuthToken() ?? '';
                        _iap.purchase(product);
                      },
                      itemBuilder: (_) => _iap.products.map((p) =>
                        PopupMenuItem(value: p, child: Text('${p.title}\n${p.price}', style: const TextStyle(fontSize: 13))),
                      ).toList(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(border: Border.all(color: const Color(0x0FFFFFFF))),
                        child: Text(
                          _iap.purchasing ? 'Processing...' : 'New Shell',
                          style: const TextStyle(color: Color(0xFFe2e6ec), fontWeight: FontWeight.w500, fontSize: 13),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ],
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              color: const Color(0xFF12141a),
              child: Text(_message!, style: const TextStyle(fontSize: 13, color: Color(0xFF7c8594))),
            ),
          ],
          const SizedBox(height: 16),
          if (_loading)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
          else if (_shells.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(child: Text(
                _iap.available ? 'No running shells.\nTap "New Shell" to provision one.' : 'No running shells.\nPurchase a shell from the app store.',
                textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF7c8594)),
              )),
            )
          else
            ..._shells.map(_buildShellCard),
        ],
      ),
    );
  }

  Widget _buildShellCard(Shell shell) {
    return _ShellCard(
      shell: shell,
      api: _api,
      getAuthToken: _getAuthToken,
      onRestart: () => _restartShell(shell),
      onDestroy: () => _destroyShell(shell),
    );
  }
}

class _ShellCard extends StatefulWidget {
  final Shell shell;
  final RelayApiService api;
  final Future<String?> Function() getAuthToken;
  final VoidCallback onRestart;
  final VoidCallback onDestroy;

  const _ShellCard({
    required this.shell,
    required this.api,
    required this.getAuthToken,
    required this.onRestart,
    required this.onDestroy,
  });

  @override
  State<_ShellCard> createState() => _ShellCardState();
}

class _ShellCardState extends State<_ShellCard> {
  bool _keysExpanded = false;
  List<Map<String, String>>? _keys;
  bool _keysLoading = false;
  final _addKeyCtrl = TextEditingController();

  Future<void> _loadKeys() async {
    setState(() => _keysLoading = true);
    try {
      final token = await widget.getAuthToken();
      if (token == null) return;
      final keys = await widget.api.listShellKeys(widget.shell.id, token: token);
      if (mounted) setState(() { _keys = keys; _keysLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _keys = []; _keysLoading = false; });
    }
  }

  Future<void> _removeKey(String keyId) async {
    if (keyId.isEmpty) return;
    try {
      final token = await widget.getAuthToken();
      if (token == null) return;
      await widget.api.removeShellKey(widget.shell.id, keyId, token: token);
      _loadKeys();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _addKey() async {
    final pubkey = _addKeyCtrl.text.trim();
    if (pubkey.isEmpty) return;
    try {
      final token = await widget.getAuthToken();
      if (token == null) return;
      await widget.api.addShellKey(widget.shell.id, pubkey, token: token);
      _addKeyCtrl.clear();
      _loadKeys();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final shell = widget.shell;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF12141a),
        border: Border.all(color: const Color(0x0FFFFFFF)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(shell.id, style: const TextStyle(fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.w600))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                color: shell.isRunning ? const Color(0xFF6aaa6a).withValues(alpha: 0.15) : const Color(0xFF4a5060).withValues(alpha: 0.15),
                child: Text(shell.state, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: shell.isRunning ? const Color(0xFF6aaa6a) : const Color(0xFF4a5060))),
              ),
            ]),
            const SizedBox(height: 8),
            Text('${shell.plan} — ${shell.specs}', style: const TextStyle(fontSize: 12, color: Color(0xFF7c8594))),
            if (shell.previewUrl.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(shell.previewUrl, style: const TextStyle(fontSize: 11, color: Color(0xFF58a6ff), fontFamily: 'monospace')),
            ],
            if (shell.isRunning) ...[
              const SizedBox(height: 12),
              Row(children: [
                _actionButton('Keys', () {
                  setState(() => _keysExpanded = !_keysExpanded);
                  if (_keysExpanded && _keys == null) _loadKeys();
                }),
                const SizedBox(width: 8),
                _actionButton('Restart', widget.onRestart),
                if (shell.isStripe) ...[
                  const SizedBox(width: 8),
                  _actionButton('Destroy', widget.onDestroy, danger: true),
                ],
              ]),
            ],
          ]),
        ),
        // Expandable keys panel
        if (_keysExpanded) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0x0FFFFFFF))),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 12),
              const Text('SSH keys on this shell', style: TextStyle(color: Color(0xFF7c8594), fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              if (_keysLoading)
                const Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
              else if (_keys != null && _keys!.isEmpty)
                const Text('No keys found.', style: TextStyle(color: Color(0xFF4a5060), fontSize: 12))
              else if (_keys != null)
                ..._keys!.map((k) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${k['type'] ?? ''} ${k['key'] ?? ''}${k['comment'] != null ? ' ${k['comment']}' : ''}',
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: Color(0xFF7c8594)),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _removeKey(k['id'] ?? ''),
                        child: const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Icon(Icons.close, size: 14, color: Color(0xFFc83c3c)),
                        ),
                      ),
                    ],
                  ),
                )),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _addKeyCtrl,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFFe2e6ec)),
                    decoration: InputDecoration(
                      hintText: 'ssh-ed25519 AAAA...',
                      hintStyle: const TextStyle(color: Color(0xFF4a5060), fontSize: 11),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0x0FFFFFFF)), borderRadius: BorderRadius.circular(4)),
                      focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFF6aaa6a)), borderRadius: BorderRadius.circular(4)),
                      filled: true, fillColor: const Color(0xFF0b0c10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _addKey,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6aaa6a),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('Add', style: TextStyle(fontSize: 12, color: Color(0xFF0b0c10), fontWeight: FontWeight.w600)),
                  ),
                ),
              ]),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _actionButton(String label, VoidCallback onTap, {bool danger = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(border: Border.all(color: danger ? Colors.red.withValues(alpha: 0.3) : const Color(0x0FFFFFFF))),
        child: Text(label, style: TextStyle(fontSize: 12, color: danger ? Colors.red.shade300 : const Color(0xFF7c8594))),
      ),
    );
  }
}
