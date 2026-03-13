import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/account.dart';
import '../../models/device.dart';
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
                onPressed: _busy ? null : () => _showSignupSheet(),
                child: const Text('Sign Up',
                    style: TextStyle(fontSize: 16, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white24),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _busy ? null : () => _showSigninSheet(),
                child: const Text('Sign In',
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

  void _showSignupSheet() {
    final usernameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final deviceCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: bgCard,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Sign Up',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              _sheetField(usernameCtrl, 'Username', validator: _required),
              _sheetField(emailCtrl, 'Email', validator: _validateEmail),
              _sheetField(deviceCtrl, 'Device Name', validator: _required),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style:
                      ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                  onPressed: () {
                    if (!formKey.currentState!.validate()) return;
                    Navigator.pop(ctx);
                    _performSignup(
                      usernameCtrl.text.trim(),
                      emailCtrl.text.trim(),
                      deviceCtrl.text.trim(),
                    );
                  },
                  child: const Text('Create Account',
                      style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSigninSheet() {
    final emailCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: bgCard,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Sign In',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('We\'ll send a magic link to your email.',
                style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 16),
            _sheetField(emailCtrl, 'Email'),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style:
                    ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                onPressed: () async {
                  final email = emailCtrl.text.trim();
                  if (email.isEmpty) return;
                  Navigator.pop(ctx);
                  await _requestMagicLink(email);
                },
                child: const Text('Send Magic Link',
                    style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sheetField(TextEditingController ctrl, String hint,
      {String? Function(String?)? validator}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: ctrl,
        style: const TextStyle(color: Colors.white),
        validator: validator,
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

  Future<void> _performSignup(
      String username, String email, String device) async {
    setState(() => _busy = true);
    final keyService = context.read<KeyService>();
    final api = context.read<RelayApiService>();
    final storage = context.read<StorageService>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final key = await keyService.generate('relay-$device');
      await api.signup(
        username: username,
        email: email,
        pubkey: key.publicKeyOpenSSH,
        device: device,
      );
      await storage.saveAccount(UnixShellsAccount(
        username: username,
        email: email,
      ));
      await _loadAccount();
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Account created')),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Signup failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestMagicLink(String email) async {
    setState(() => _busy = true);
    final api = context.read<RelayApiService>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await api.requestMagicLink(email);
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Magic link sent — check your email')),
        );
        _showTokenDialog(email);
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showTokenDialog(String email) {
    final tokenCtrl = TextEditingController();
    final deviceCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgCard,
        title: const Text('Enter Token',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Paste the token from the magic link email.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: tokenCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Token',
                hintStyle: TextStyle(color: Colors.white38),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: deviceCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Device name (e.g. iphone)',
                hintStyle: TextStyle(color: Colors.white38),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _completeSignin(
                email,
                tokenCtrl.text.trim(),
                deviceCtrl.text.trim(),
              );
            },
            child: const Text('Sign In'),
          ),
        ],
      ),
    );
  }

  Future<void> _completeSignin(
      String email, String token, String device) async {
    if (token.isEmpty || device.isEmpty) return;
    setState(() => _busy = true);
    final keyService = context.read<KeyService>();
    final api = context.read<RelayApiService>();
    final storage = context.read<StorageService>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final key = await keyService.generate('relay-$device');
      final username = await api.addKey(
        token: token,
        pubkey: key.publicKeyOpenSSH,
        device: device,
      );
      await storage.saveAccount(UnixShellsAccount(
        username: username,
        email: email,
      ));
      await _loadAccount();
      if (mounted) {
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
      if (mounted) setState(() => _busy = false);
    }
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
    setState(() {
      _account = null;
      _devices = [];
    });
  }

  String? _required(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    return null;
  }

  String? _validateEmail(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    if (!v.contains('@') || !v.contains('.')) return 'Invalid email';
    return null;
  }
}
