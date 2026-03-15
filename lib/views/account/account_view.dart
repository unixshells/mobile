import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/account.dart';
import '../../models/device.dart';
import '../../models/ssh_key.dart';
import '../../services/discovery_service.dart';
import '../../services/key_service.dart';
import '../../services/relay_api_service.dart';
import '../../services/storage_service.dart';
import '../../util/constants.dart';

class AccountView extends StatefulWidget {
  const AccountView({super.key});

  @override
  State<AccountView> createState() => _AccountViewState();
}

class _AccountViewState extends State<AccountView> {
  UnixShellsAccount? _account;
  List<Device> _devices = [];
  bool _loading = true;
  bool _busy = false;
  String? _busyMessage;

  @override
  void initState() {
    super.initState();
    _loadAccount();
  }

  Future<void> _loadAccount() async {
    final storage = context.read<StorageService>();
    final account = await storage.getAccount();
    setState(() {
      _account = account;
      _loading = false;
    });
    if (account != null) _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    if (_account == null) return;
    final api = context.read<RelayApiService>();
    final storage = context.read<StorageService>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final status = await api.getStatus(_account!.username);
      await storage.saveAccount(status.account);
      if (mounted) {
        setState(() {
          _account = status.account;
          _devices = status.devices;
        });
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Failed to refresh: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgDark,
      appBar: AppBar(
        title: const Text('Account'),
        backgroundColor: bgCard,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _account == null
              ? _buildSignedOut()
              : _buildSignedIn(),
    );
  }

  Widget _buildSignedOut() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_outlined, size: 80, color: Colors.white24),
            const SizedBox(height: 24),
            const Text(
              'Unix Shells',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Access your machines from anywhere.\nSSH through NAT, no port forwarding needed.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _busy ? null : _showSigninSheet,
                child: _busy
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white54),
                          ),
                          if (_busyMessage != null) ...[
                            const SizedBox(height: 8),
                            Text(_busyMessage!,
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 12)),
                          ],
                        ],
                      )
                    : const Text('Sign In',
                        style: TextStyle(fontSize: 16, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignedIn() {
    return RefreshIndicator(
      onRefresh: _refreshStatus,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: bgCard,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_account!.username,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(_account!.email,
                    style: const TextStyle(color: Colors.white54)),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _account!.isActive
                        ? Colors.green.withValues(alpha: 0.2)
                        : Colors.orange.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _account!.subscriptionStatus.isEmpty
                        ? 'No subscription'
                        : _account!.subscriptionStatus,
                    style: TextStyle(
                      color:
                          _account!.isActive ? Colors.green : Colors.orange,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text('Devices',
              style: TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (_devices.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No devices registered',
                  style: TextStyle(color: Colors.white38)),
            ),
          ..._devices.map((d) => ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.blue.withValues(alpha: 0.2),
                  child: const Icon(Icons.computer,
                      color: Colors.blue, size: 20),
                ),
                title: Text(d.name,
                    style: const TextStyle(color: Colors.white)),
                subtitle: Text(d.addedAt,
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 12)),
              )),
          const SizedBox(height: 24),
          TextButton(
            onPressed: _signOut,
            child: const Text('Sign Out',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  static String _deviceName() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'iphone';
    if (Platform.isMacOS) return 'mac';
    if (Platform.isLinux) return 'linux';
    return 'mobile';
  }

  void _showSigninSheet() {
    final usernameCtrl = TextEditingController();
    final keyService = context.read<KeyService>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: bgCard,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: FutureBuilder<List<SSHKeyPair>>(
          future: keyService.list(),
          builder: (ctx, snapshot) {
            final keys = snapshot.data ?? [];
            String? selectedKeyId = keys.isNotEmpty ? keys.first.id : null;

            return StatefulBuilder(
              builder: (ctx, setSheetState) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Sign In',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Enter your username. We\'ll email you an approval link.',
                      style: TextStyle(color: Colors.white54)),
                  const SizedBox(height: 16),
                  _sheetField(usernameCtrl, 'Username'),
                  const SizedBox(height: 4),
                  if (keys.isNotEmpty) ...[
                    const Text('SSH Key',
                        style: TextStyle(color: Colors.white54, fontSize: 12)),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<String>(
                      initialValue: selectedKeyId,
                      dropdownColor: bgCard,
                      style: const TextStyle(color: Colors.white),
                      items: [
                        ...keys.map((k) => DropdownMenuItem(
                              value: k.id,
                              child: Text(k.label,
                                  style: const TextStyle(color: Colors.white)),
                            )),
                        const DropdownMenuItem(
                          value: '_generate',
                          child: Text('Generate new key',
                              style: TextStyle(color: Colors.blue)),
                        ),
                      ],
                      onChanged: (v) => setSheetState(() => selectedKeyId = v),
                      decoration: InputDecoration(
                        enabledBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: Colors.white24),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: Colors.blue),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        filled: true,
                        fillColor: bgDark,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style:
                          ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                      onPressed: () {
                        final username = usernameCtrl.text.trim();
                        if (username.isEmpty) return;
                        Navigator.pop(ctx);
                        _startSignin(username, selectedKeyId);
                      },
                      child: const Text('Sign In',
                          style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _startSignin(String username, String? keyId) async {
    setState(() {
      _busy = true;
      _busyMessage = 'Preparing key...';
    });
    final keyService = context.read<KeyService>();
    final api = context.read<RelayApiService>();
    final storage = context.read<StorageService>();
    final messenger = ScaffoldMessenger.of(context);
    final device = _deviceName();

    try {
      // Get or generate key.
      SSHKeyPair key;
      if (keyId == null || keyId == '_generate') {
        key = await keyService.generate('relay-$device');
      } else {
        final keys = await keyService.list();
        key = keys.firstWhere((k) => k.id == keyId);
      }

      // Send device request.
      if (mounted) setState(() => _busyMessage = 'Sending request...');
      final requestId = await api.deviceRequest(
        username: username,
        pubkey: key.publicKeyOpenSSH,
        device: device,
      );

      // Poll for approval.
      if (mounted) setState(() => _busyMessage = 'Check your email — waiting for approval...');
      final approvedUsername = await _pollForApproval(api, requestId);
      if (approvedUsername == null) {
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Request expired or not approved')),
          );
        }
        return;
      }

      // Fetch account details.
      final status = await api.getStatus(approvedUsername);
      await storage.saveAccount(status.account);
      await _loadAccount();
      if (mounted) {
        context.read<DiscoveryService>().refresh();
        messenger.showSnackBar(
          const SnackBar(content: Text('Signed in successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Sign in failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() { _busy = false; _busyMessage = null; });
    }
  }

  /// Poll for device request approval. Returns username on success, null on timeout.
  Future<String?> _pollForApproval(RelayApiService api, String requestId) async {
    // Poll every 3 seconds for up to 15 minutes.
    for (var i = 0; i < 300; i++) {
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return null;
      try {
        final username = await api.getDeviceRequestStatus(requestId);
        if (username != null) return username;
      } catch (_) {
        return null; // Request expired.
      }
    }
    return null;
  }

  Widget _sheetField(TextEditingController ctrl, String hint) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: ctrl,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white38),
          enabledBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: Colors.white24),
            borderRadius: BorderRadius.circular(8),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: Colors.blue),
            borderRadius: BorderRadius.circular(8),
          ),
          filled: true,
          fillColor: bgDark,
        ),
      ),
    );
  }

  Future<void> _signOut() async {
    final storage = context.read<StorageService>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgCard,
        title: const Text('Sign Out', style: TextStyle(color: Colors.white)),
        content: const Text('Are you sure you want to sign out?',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign Out', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await storage.deleteAccount();
    if (mounted) context.read<DiscoveryService>().refresh();
    setState(() {
      _account = null;
      _devices = [];
    });
  }
}
