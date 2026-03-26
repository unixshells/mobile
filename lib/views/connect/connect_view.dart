import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/connection.dart';
import '../../models/port_forward.dart';
import '../../models/ssh_key.dart' as model;
import '../../services/key_service.dart';
import '../../services/storage_service.dart';
import '../../util/constants.dart';

class ConnectView extends StatefulWidget {
  final Connection? existing;

  const ConnectView({super.key, this.existing});

  @override
  State<ConnectView> createState() => _ConnectViewState();
}

class _ConnectViewState extends State<ConnectView> {
  final _formKey = GlobalKey<FormState>();
  late ConnectionType _type;
  late AuthMethod _authMethod;

  final _labelCtrl = TextEditingController();
  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _relayUsernameCtrl = TextEditingController();
  final _relayDeviceCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _sessionNameCtrl = TextEditingController();

  String? _selectedKeyId;
  List<model.SSHKeyPair> _keys = [];
  List<PortForward> _portForwards = [];
  bool _agentForwarding = false;
  bool _useMosh = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _type = c?.type ?? ConnectionType.direct;
    _authMethod = c?.authMethod ?? AuthMethod.key;
    _labelCtrl.text = c?.label ?? '';
    _hostCtrl.text = c?.host ?? '';
    _portCtrl.text = (c?.port ?? 22).toString();
    _usernameCtrl.text = c?.username ?? '';
    _relayUsernameCtrl.text = c?.relayUsername ?? '';
    _relayDeviceCtrl.text = c?.relayDevice ?? '';
    _selectedKeyId = c?.keyId;
    _portForwards = List.of(c?.portForwards ?? []);
    _agentForwarding = c?.agentForwarding ?? false;
    _useMosh = c?.useMosh ?? false;
    _sessionNameCtrl.text = c?.sessionName ?? '';
    _loadKeys();
  }

  Future<void> _loadKeys() async {
    final keyService = context.read<KeyService>();
    _keys = await keyService.list();
    if (_selectedKeyId != null && !_keys.any((k) => k.id == _selectedKeyId)) {
      _selectedKeyId = null;
    }
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final storage = context.read<StorageService>();
    final nav = Navigator.of(context);
    final id = widget.existing?.id ?? const Uuid().v4();

    String? passwordId;
    if (_authMethod == AuthMethod.password && _passwordCtrl.text.isNotEmpty) {
      passwordId = widget.existing?.passwordId ?? const Uuid().v4();
      await storage.savePassword(passwordId, _passwordCtrl.text);
    }

    final conn = Connection(
      id: id,
      label: _labelCtrl.text.trim(),
      type: _type,
      host: _type == ConnectionType.direct ? _hostCtrl.text.trim() : '',
      port: int.tryParse(_portCtrl.text) ?? 22,
      username: _usernameCtrl.text.trim(),
      authMethod: _authMethod,
      keyId: _authMethod == AuthMethod.key ? _selectedKeyId : null,
      passwordId: _authMethod == AuthMethod.password ? passwordId : null,
      relayUsername: _type == ConnectionType.relay
          ? _relayUsernameCtrl.text.trim()
          : null,
      relayDevice: _type == ConnectionType.relay
          ? _relayDeviceCtrl.text.trim()
          : null,
      portForwards: _portForwards,
      agentForwarding: _agentForwarding,
      useMosh: _useMosh,
      sessionName: _sessionNameCtrl.text.trim().isEmpty
          ? null
          : _sessionNameCtrl.text.trim(),
      sortOrder: widget.existing?.sortOrder ?? 0,
    );

    if (_authMethod == AuthMethod.key && widget.existing?.passwordId != null) {
      await storage.deletePassword(widget.existing!.passwordId!);
    }

    await storage.saveConnection(conn);
    nav.pop();
  }

  void _addPortForward() {
    final localPortCtrl = TextEditingController();
    final remoteHostCtrl = TextEditingController(text: 'localhost');
    final remotePortCtrl = TextEditingController();
    var type = ForwardType.local;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: bgCard,
          title: const Text('Add Port Forward',
              style: TextStyle(color: textBright)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  ...[ForwardType.local, ForwardType.remote].map((ft) {
                    final sel = type == ft;
                    return Expanded(child: GestureDetector(
                      onTap: () => setDialogState(() => type = ft),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        margin: EdgeInsets.only(right: ft == ForwardType.local ? 8 : 0),
                        decoration: BoxDecoration(
                          color: sel ? accent.withValues(alpha: 0.12) : bgCard,
                          border: Border.all(color: sel ? accent : borderColor),
                        ),
                        child: Center(child: Text(
                          ft == ForwardType.local ? 'Local' : 'Remote',
                          style: TextStyle(color: sel ? accent : textDim, fontSize: 13, fontWeight: sel ? FontWeight.w600 : FontWeight.w400),
                        )),
                      ),
                    ));
                  }),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: localPortCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: textBright),
                decoration: InputDecoration(
                  labelText: type == ForwardType.local
                      ? 'Local Port'
                      : 'Local Port (destination)',
                  labelStyle: const TextStyle(color: textDim),
                ),
              ),
              TextField(
                controller: remoteHostCtrl,
                style: const TextStyle(color: textBright),
                decoration: const InputDecoration(
                  labelText: 'Remote Host',
                  labelStyle: TextStyle(color: textDim),
                ),
              ),
              TextField(
                controller: remotePortCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: textBright),
                decoration: InputDecoration(
                  labelText: type == ForwardType.local
                      ? 'Remote Port (destination)'
                      : 'Remote Port (listen)',
                  labelStyle: const TextStyle(color: textDim),
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
                final lp = int.tryParse(localPortCtrl.text);
                final rp = int.tryParse(remotePortCtrl.text);
                if (lp == null || rp == null) return;
                final conflict = _portForwards.any(
                    (f) => f.localPort == lp && f.type == type);
                if (conflict) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('Port $lp already forwarded')),
                  );
                  return;
                }
                setState(() {
                  _portForwards.add(PortForward(
                    type: type,
                    localPort: lp,
                    remoteHost: remoteHostCtrl.text.trim().isEmpty
                        ? 'localhost'
                        : remoteHostCtrl.text.trim(),
                    remotePort: rp,
                  ));
                });
                Navigator.pop(ctx);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgDark,
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Connection' : 'New Connection'),
        backgroundColor: bgCard,
        foregroundColor: textBright,
        actions: [
          TextButton(
            onPressed: _save,
            child:
                const Text('Save', style: TextStyle(color: accent)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionHeader('Type'),
            Row(
              children: [
                _typeBox('Direct SSH', ConnectionType.direct),
                const SizedBox(width: 8),
                _typeBox('latch', ConnectionType.relay),
              ],
            ),
            const SizedBox(height: 16),

            _sectionHeader('Connection'),
            _field(_labelCtrl, 'Label', 'My Server', validator: _required),

            if (_type == ConnectionType.direct) ...[
              _field(_hostCtrl, 'Host', '192.168.1.100', validator: _required),
              _field(_portCtrl, 'Port', '22',
                  keyboardType: TextInputType.number,
                  validator: _validatePort),
            ],

            if (_type == ConnectionType.relay) ...[
              _field(_relayUsernameCtrl, 'latch username', 'rasengan',
                  validator: _required),
              _field(_relayDeviceCtrl, 'Device', 'macbook',
                  validator: _required),
            ],

            if (_type == ConnectionType.direct)
              _field(_usernameCtrl, 'SSH Username', 'root',
                  validator: _required),

            const SizedBox(height: 16),
            _sectionHeader('Authentication'),
            // latch connections are always key-based
            if (_type == ConnectionType.direct) ...[
              Row(
                children: [
                  _authBox('Key', AuthMethod.key),
                  const SizedBox(width: 8),
                  _authBox('Password', AuthMethod.password),
                ],
              ),
            ],
            const SizedBox(height: 12),

            if (_authMethod == AuthMethod.key || _type == ConnectionType.relay) ...[
              DropdownButtonFormField<String>(
                initialValue: _selectedKeyId,
                hint: const Text('Select SSH key',
                    style: TextStyle(color: textMuted)),
                dropdownColor: bgCard,
                style: const TextStyle(color: textBright),
                items: _keys
                    .map((k) => DropdownMenuItem(
                          value: k.id,
                          child: Text(k.label),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _selectedKeyId = v),
                decoration: _inputDecoration('SSH Key'),
                validator: (v) {
                  if (_authMethod == AuthMethod.key && v == null) {
                    return 'Select a key';
                  }
                  return null;
                },
              ),
            ],

            if (_authMethod == AuthMethod.password)
              _field(_passwordCtrl, 'Password', '',
                  obscure: true, validator: _required),

            // Protocol section.
            const SizedBox(height: 16),
            _sectionHeader('Protocol'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Use Mosh',
                  style: TextStyle(color: textBright)),
              subtitle: const Text(
                  'Mobile shell — roaming, intermittent connectivity',
                  style: TextStyle(color: textMuted, fontSize: 12)),
              value: _useMosh,
              onChanged: (v) => setState(() => _useMosh = v),
            ),
            if (_type == ConnectionType.relay) ...[
              const SizedBox(height: 8),
              _field(_sessionNameCtrl, 'latch session', 'default'),
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                    'Leave blank for "default". Selects which latch session to attach to.',
                    style: TextStyle(color: textMuted, fontSize: 12)),
              ),
            ],

            // Forwarding section.
            const SizedBox(height: 16),
            _sectionHeader('Forwarding'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Agent Forwarding',
                  style: TextStyle(color: textBright)),
              subtitle: const Text('Forward SSH keys to remote host',
                  style: TextStyle(color: textMuted, fontSize: 12)),
              value: _agentForwarding,
              onChanged: (v) => setState(() => _agentForwarding = v),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Port Forwards',
                    style: TextStyle(color: textBright, fontSize: 14)),
                IconButton(
                  icon: const Icon(Icons.add, color: accent, size: 20),
                  onPressed: _addPortForward,
                ),
              ],
            ),
            if (_portForwards.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('No port forwards configured',
                    style: TextStyle(color: borderColor, fontSize: 13)),
              ),
            ..._portForwards.asMap().entries.map((entry) {
              final i = entry.key;
              final fwd = entry.value;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  fwd.type == ForwardType.local
                      ? Icons.arrow_forward
                      : Icons.arrow_back,
                  color: textDim,
                  size: 18,
                ),
                title: Text(
                  fwd.toString(),
                  style:
                      const TextStyle(color: textBright, fontFamily: 'monospace', fontSize: 13),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.close, color: Colors.red, size: 18),
                  onPressed: () =>
                      setState(() => _portForwards.removeAt(i)),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _typeBox(String label, ConnectionType value) {
    final selected = _type == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _type = value;
          if (value == ConnectionType.relay) _authMethod = AuthMethod.key;
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? accent.withValues(alpha: 0.12) : bgCard,
            border: Border.all(color: selected ? accent : borderColor),
          ),
          child: Center(
            child: Text(label, style: TextStyle(
              color: selected ? accent : textDim,
              fontSize: 13, fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            )),
          ),
        ),
      ),
    );
  }

  Widget _authBox(String label, AuthMethod value) {
    final selected = _authMethod == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _authMethod = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? accent.withValues(alpha: 0.12) : bgCard,
            border: Border.all(color: selected ? accent : borderColor),
          ),
          child: Center(
            child: Text(label, style: TextStyle(
              color: selected ? accent : textDim,
              fontSize: 13, fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            )),
          ),
        ),
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

  Widget _field(
    TextEditingController ctrl,
    String label,
    String hint, {
    bool obscure = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: ctrl,
        obscureText: obscure,
        keyboardType: keyboardType,
        style: const TextStyle(color: textBright),
        decoration: _inputDecoration(label).copyWith(hintText: hint),
        validator: validator,
      ),
    );
  }

  String? _required(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    return null;
  }

  String? _validatePort(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    final port = int.tryParse(v);
    if (port == null || port < 1 || port > 65535) return 'Invalid port (1-65535)';
    return null;
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: textDim),
      hintStyle: const TextStyle(color: borderColor),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: borderColor),
        borderRadius: BorderRadius.circular(8),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: accent),
        borderRadius: BorderRadius.circular(8),
      ),
      filled: true,
      fillColor: bgCard,
    );
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _usernameCtrl.dispose();
    _relayUsernameCtrl.dispose();
    _relayDeviceCtrl.dispose();
    _passwordCtrl.dispose();
    _sessionNameCtrl.dispose();
    super.dispose();
  }
}
