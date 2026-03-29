import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/account.dart';
import '../../models/connection.dart';
import '../../models/device.dart';
import '../../models/ssh_key.dart';
import '../../services/demo_service.dart';
import '../../services/discovery_service.dart';
import '../../services/key_service.dart';
import '../../services/relay_api_service.dart';
import '../../services/storage_service.dart';
import '../../util/constants.dart';
import '../terminal/terminal_view.dart';

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
    final demo = DemoService();
    if (demo.isActive) {
      if (mounted) {
        setState(() {
          _account = demo.account;
          _devices = demo.devices;
        });
      }
      return;
    }
    final api = context.read<RelayApiService>();
    final storage = context.read<StorageService>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final token = await _getAuthToken();
      if (token == null) return;
      final status = await api.getStatus(_account!.username, token: token);
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
    if (_loading) return const Center(child: CircularProgressIndicator());
    return _account == null ? _buildSignedOut() : _buildSignedIn();
  }

  Widget _buildSignedOut() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_outlined, size: 80, color: borderColor),
            const SizedBox(height: 24),
            const Text(
              'Unix Shells',
              style: TextStyle(
                  color: textBright,
                  fontSize: 24,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Sign in to discover your devices\nand manage your shells.',
              textAlign: TextAlign.center,
              style: TextStyle(color: textDim, fontSize: 14),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: const Color(0xFF0b0c10),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: const RoundedRectangleBorder(),
                ),
                onPressed: _busy ? null : _showSigninSheet,
                child: _busy
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: textDim),
                          ),
                          if (_busyMessage != null) ...[
                            const SizedBox(height: 8),
                            Text(_busyMessage!,
                                style: const TextStyle(
                                    color: textDim, fontSize: 12)),
                          ],
                        ],
                      )
                    : const Text('Sign In',
                        style: TextStyle(fontSize: 16, color: textBright)),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: textDim,
                  side: const BorderSide(color: borderColor),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: const RoundedRectangleBorder(),
                ),
                onPressed: _busy ? null : _showCreateAccountSheet,
                child: const Text('Create Account',
                    style: TextStyle(fontSize: 16)),
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
                        color: textBright,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(_account!.email,
                    style: const TextStyle(color: textDim)),
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
                  color: textDim,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (_devices.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No devices registered',
                  style: TextStyle(color: textMuted)),
            ),
          ..._devices.expand((d) {
            final sessions = d.sessions.where((s) => s.status == 'alive').toList();
            if (sessions.isEmpty || !DemoService().isActive) {
              return [
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: accent.withValues(alpha: 0.2),
                    child: const Icon(Icons.computer, color: accent, size: 20),
                  ),
                  title: Text(d.name, style: const TextStyle(color: textBright)),
                  subtitle: Text(d.addedAt, style: const TextStyle(color: textMuted, fontSize: 12)),
                ),
              ];
            }
            return sessions.map((s) => ListTile(
              leading: CircleAvatar(
                backgroundColor: accent.withValues(alpha: 0.2),
                child: const Icon(Icons.computer, color: accent, size: 20),
              ),
              title: Text('${d.name} / ${s.name}', style: const TextStyle(color: textBright)),
              subtitle: Text(s.title, style: const TextStyle(color: textMuted, fontSize: 12)),
              trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: textMuted),
              onTap: () {
                final conn = Connection(
                  id: 'demo-${d.name}-${s.name}',
                  label: '${d.name}/${s.name}',
                  host: '${d.name}.iapdemo.unixshells.com',
                  port: 22,
                  username: 'iapdemo',
                  authMethod: AuthMethod.key,
                  type: ConnectionType.relay,
                  relayDevice: d.name,
                  sessionName: s.name,
                );
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => TerminalPage(pendingConnection: conn)),
                );
              },
            ));
          }),
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
                          color: textBright,
                          fontSize: 20,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Enter your username. We\'ll email you an approval link.',
                      style: TextStyle(color: textDim)),
                  const SizedBox(height: 16),
                  _sheetField(usernameCtrl, 'Username'),
                  const SizedBox(height: 4),
                  if (keys.isNotEmpty) ...[
                    const Text('SSH Key',
                        style: TextStyle(color: textDim, fontSize: 12)),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<String>(
                      initialValue: selectedKeyId,
                      dropdownColor: bgCard,
                      style: const TextStyle(color: textBright),
                      items: [
                        ...keys.map((k) => DropdownMenuItem(
                              value: k.id,
                              child: Text(k.label,
                                  style: const TextStyle(color: textBright)),
                            )),
                        const DropdownMenuItem(
                          value: '_generate',
                          child: Text('Generate new key',
                              style: TextStyle(color: accent)),
                        ),
                      ],
                      onChanged: (v) => setSheetState(() => selectedKeyId = v),
                      decoration: InputDecoration(
                        enabledBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: borderColor),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: accent),
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
                          ElevatedButton.styleFrom(backgroundColor: accent),
                      onPressed: () {
                        final username = usernameCtrl.text.trim();
                        if (username.isEmpty) return;
                        Navigator.pop(ctx);
                        _startSignin(username, selectedKeyId);
                      },
                      child: const Text('Sign In',
                          style: TextStyle(color: textBright)),
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
    // Demo mode: skip real auth flow entirely.
    if (username == 'iapdemo') {
      setState(() { _busy = true; _busyMessage = 'Signing in...'; });
      final demo = DemoService();
      final storage = context.read<StorageService>();
      demo.activate();
      await storage.saveAccount(demo.account);
      await _loadAccount();
      if (mounted) {
        context.read<DiscoveryService>().refresh();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signed in successfully')),
        );
        setState(() { _busy = false; _busyMessage = null; });
      }
      return;
    }

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
      await storage.saveSetting('relay_key_id', key.id);
      final token = await _getAuthToken();
      final status = await api.getStatus(approvedUsername, token: token ?? '');
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
        style: const TextStyle(color: textBright),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: textMuted),
          enabledBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: borderColor),
            borderRadius: BorderRadius.circular(8),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: accent),
            borderRadius: BorderRadius.circular(8),
          ),
          filled: true,
          fillColor: bgDark,
        ),
      ),
    );
  }

  void _showCreateAccountSheet() {
    final usernameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
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
            String? error;

            return StatefulBuilder(
              builder: (ctx, setSheetState) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Create Account',
                      style: TextStyle(color: textBright, fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Create a Unix Shells account to manage devices and shells.',
                      style: TextStyle(color: textDim)),
                  const SizedBox(height: 16),
                  _sheetField(usernameCtrl, 'Username'),
                  _sheetField(emailCtrl, 'Email'),
                  if (keys.isNotEmpty) ...[
                    const Text('SSH Key', style: TextStyle(color: textDim, fontSize: 12)),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<String>(
                      initialValue: selectedKeyId,
                      dropdownColor: bgCard,
                      style: const TextStyle(color: textBright),
                      items: [
                        ...keys.map((k) => DropdownMenuItem(
                              value: k.id,
                              child: Text(k.label, style: const TextStyle(color: textBright)),
                            )),
                        DropdownMenuItem(
                          value: '_generate',
                          child: Text('Generate new key', style: TextStyle(color: accent)),
                        ),
                      ],
                      onChanged: (v) => setSheetState(() => selectedKeyId = v),
                      decoration: InputDecoration(
                        enabledBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: borderColor),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: accent),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        filled: true, fillColor: bgDark,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ] else ...[
                    const Text('An SSH key will be generated automatically.',
                        style: TextStyle(color: textMuted, fontSize: 12)),
                    const SizedBox(height: 12),
                  ],
                  if (error != null) ...[
                    Text(error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                    const SizedBox(height: 8),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: const Color(0xFF0b0c10),
                        shape: const RoundedRectangleBorder(),
                      ),
                      onPressed: () async {
                        final username = usernameCtrl.text.trim().toLowerCase();
                        final email = emailCtrl.text.trim();
                        if (username.isEmpty || email.isEmpty) {
                          setSheetState(() => error = 'Username and email are required.');
                          return;
                        }

                        Navigator.pop(ctx);
                        setState(() { _busy = true; _busyMessage = 'Creating account...'; });

                        try {
                          // Ensure we have a key.
                          String keyId = selectedKeyId ?? '_generate';
                          String pubKey;
                          if (keyId == '_generate' || keys.isEmpty) {
                            final kp = await keyService.generate('relay-$username');
                            keyId = kp.id;
                            pubKey = kp.publicKeyOpenSSH;
                          } else {
                            final kp = (await keyService.list()).firstWhere((k) => k.id == keyId);
                            pubKey = kp.publicKeyOpenSSH;
                          }
                          final device = _deviceName();
                          final api = context.read<RelayApiService>();

                          // Call /api/signup to create account + register key.
                          final resp = await api.signup(
                            username: username,
                            email: email,
                            pubkey: pubKey,
                            device: device,
                          );

                          // Save account locally.
                          final storage = context.read<StorageService>();
                          await storage.saveAccount(UnixShellsAccount(
                            username: resp['username'] ?? username,
                            email: email,
                          ));
                          await storage.saveSetting('relay_key_id', keyId);

                          // Start discovery.
                          if (mounted) {
                            context.read<DiscoveryService>().refresh();
                          }

                          await _loadAccount();
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(e.toString())),
                            );
                          }
                        } finally {
                          if (mounted) setState(() { _busy = false; _busyMessage = null; });
                        }
                      },
                      child: const Text('Create Account'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    children: [
                      const Text('By creating an account you agree to the ', style: TextStyle(color: textMuted, fontSize: 11)),
                      GestureDetector(
                        onTap: () => launchUrl(Uri.parse('https://unixshells.com/terms.html')),
                        child: const Text('Terms of Service', style: TextStyle(color: accent, fontSize: 11)),
                      ),
                      const Text(' and ', style: TextStyle(color: textMuted, fontSize: 11)),
                      GestureDetector(
                        onTap: () => launchUrl(Uri.parse('https://unixshells.com/privacy.html')),
                        child: const Text('Privacy Policy', style: TextStyle(color: accent, fontSize: 11)),
                      ),
                      const Text('.', style: TextStyle(color: textMuted, fontSize: 11)),
                    ],
                  ),
                ],
              ),
            );
          },
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
        title: const Text('Sign Out', style: TextStyle(color: textBright)),
        content: const Text('Are you sure you want to sign out?',
            style: TextStyle(color: textDim)),
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
    DemoService().deactivate();
    await storage.deleteAccount();
    if (mounted) context.read<DiscoveryService>().refresh();
    setState(() {
      _account = null;
      _devices = [];
    });
  }
}
