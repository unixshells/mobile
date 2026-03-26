import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:provider/provider.dart';

import '../../models/shell.dart';
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

  Future<void> _requestShell(String plan) async {
    try {
      final username = await _getUsername();
      if (username == null) return;
      final msg = await _api.requestShell(username: username, plan: plan);
      _showMessage(msg);
    } catch (e) {
      _showMessage(e.toString());
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
                        decoration: BoxDecoration(border: Border.all(color: const Color(0xFF21262d))),
                        child: Text(
                          _iap.purchasing ? 'Processing...' : 'New Shell',
                          style: const TextStyle(color: Color(0xFFF0F6FC), fontWeight: FontWeight.w500, fontSize: 13),
                        ),
                      ),
                    )
                  : PopupMenuButton<String>(
                      onSelected: _requestShell,
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'shell', child: Text('Shell — \$6/mo\n2GB / 1 vCPU / 10GB')),
                        const PopupMenuItem(value: 'shell-plus', child: Text('Shell+ — \$12/mo\n4GB / 2 vCPU / 25GB')),
                      ],
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(border: Border.all(color: const Color(0xFF21262d))),
                        child: const Text('New Shell', style: TextStyle(color: Color(0xFFF0F6FC), fontWeight: FontWeight.w500, fontSize: 13)),
                      ),
                    ),
            ],
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              color: const Color(0xFF1c222c),
              child: Text(_message!, style: const TextStyle(fontSize: 13, color: Color(0xFF8b949e))),
            ),
          ],
          const SizedBox(height: 16),
          if (_loading)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
          else if (_shells.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('No running shells.\nTap "New Shell" to provision one.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF8b949e)))),
            )
          else
            ..._shells.map(_buildShellCard),
        ],
      ),
    );
  }

  Widget _buildShellCard(Shell shell) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1c222c),
        border: Border.all(color: const Color(0xFF21262d)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(shell.id, style: const TextStyle(fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.w600))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            color: shell.isRunning ? const Color(0xFF6bc26b).withValues(alpha: 0.15) : const Color(0xFF484f58).withValues(alpha: 0.15),
            child: Text(shell.state, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: shell.isRunning ? const Color(0xFF6bc26b) : const Color(0xFF484f58))),
          ),
        ]),
        const SizedBox(height: 8),
        Text('${shell.plan} — ${shell.specs}', style: const TextStyle(fontSize: 12, color: Color(0xFF8b949e))),
        if (shell.isRunning) ...[
          const SizedBox(height: 12),
          Row(children: [
            _actionButton('Restart', () => _restartShell(shell)),
            const SizedBox(width: 8),
            _actionButton('Destroy', () => _destroyShell(shell), danger: true),
          ]),
        ],
      ]),
    );
  }

  Widget _actionButton(String label, VoidCallback onTap, {bool danger = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(border: Border.all(color: danger ? Colors.red.withValues(alpha: 0.3) : const Color(0xFF21262d))),
        child: Text(label, style: TextStyle(fontSize: 12, color: danger ? Colors.red.shade300 : const Color(0xFF8b949e))),
      ),
    );
  }
}
