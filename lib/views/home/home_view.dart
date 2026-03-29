import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/connection.dart';
import '../../models/device.dart';
import '../../models/shell.dart';
import '../../services/demo_service.dart';
import '../../services/discovery_service.dart';
import '../shells/shells_view.dart';
import '../../services/key_service.dart';
import '../../services/session_manager.dart';
import '../../services/storage_service.dart';
import '../../util/constants.dart';
import '../connect/connect_view.dart';
import '../keys/key_list_view.dart';
import '../settings/settings_view.dart';
import '../account/account_view.dart';
import '../terminal/terminal_view.dart';

class _Tab {
  final String label;
  final IconData icon;
  final Widget body;
  const _Tab(this.label, this.icon, this.body);
}

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  int _currentTab = 0;
  List<Connection> _connections = [];
  bool _signedIn = false;

  @override
  void initState() {
    super.initState();
    _loadConnections();
    _checkSignedIn();
  }

  Future<void> _checkSignedIn() async {
    final storage = context.read<StorageService>();
    final account = await storage.getAccount();
    if (mounted) setState(() => _signedIn = account != null);
  }

  Future<void> _loadConnections() async {
    final storage = context.read<StorageService>();
    final conns = await storage.listConnections();
    if (mounted) setState(() => _connections = conns);
  }

  void _connect(Connection conn) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TerminalPage(pendingConnection: conn)),
    );
  }

  void _connectToRelaySession(Device device, String sessionName) async {
    // In demo mode, go directly to terminal with a simple mock connection.
    if (DemoService().isActive) {
      final conn = Connection(
        id: 'demo-${device.name}-$sessionName',
        label: '${device.name}/$sessionName',
        host: '${device.name}.iapdemo.unixshells.com',
        port: 22,
        username: 'iapdemo',
        authMethod: AuthMethod.key,
        type: ConnectionType.relay,
        relayUsername: 'iapdemo',
        relayDevice: device.name,
        sessionName: sessionName,
      );
      _connect(conn);
      return;
    }

    final storage = context.read<StorageService>();
    final account = await storage.getAccount();
    if (account == null) return;
    final host = await storage.getSetting('relay_host');
    final relayHost = (host != null && host.isNotEmpty) ? host : 'unixshells.com';

    final prefs = await storage.getDevicePrefs(account.username, '${device.name}:$sessionName');
    final useMosh = prefs['useMosh'] == true;
    final keyId = prefs['keyId'] as String?;

    final conn = Connection(
      id: 'relay-${device.name}-$sessionName',
      label: '${device.name}/$sessionName',
      host: '${device.name}.${account.username}.$relayHost',
      port: defaultSSHPort,
      username: account.username,
      authMethod: AuthMethod.key,
      keyId: keyId,
      type: ConnectionType.relay,
      relayUsername: account.username,
      relayDevice: device.name,
      sessionName: sessionName,
      useMosh: useMosh,
    );
    _connect(conn);
  }

  void _editRelaySession(Device device, String sessionName) async {
    final storage = context.read<StorageService>();
    final keyService = context.read<KeyService>();
    final account = await storage.getAccount();
    if (account == null) return;

    final prefsKey = '${device.name}:$sessionName';
    final prefs = await storage.getDevicePrefs(account.username, prefsKey);
    var useMosh = prefs['useMosh'] == true;
    var keyId = prefs['keyId'] as String?;
    final keys = await keyService.list();

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: bgCard,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${device.name} / $sessionName',
                  style: const TextStyle(color: textBright, fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Use Mosh', style: TextStyle(color: textBright)),
                subtitle: const Text('Mobile shell — roaming, intermittent connectivity',
                    style: TextStyle(color: textMuted, fontSize: 12)),
                value: useMosh,
                onChanged: (v) => setSheetState(() => useMosh = v),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                value: keyId,
                hint: const Text('Default key', style: TextStyle(color: textMuted)),
                dropdownColor: bgCard,
                style: const TextStyle(color: textBright),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Default key')),
                  ...keys.map((k) => DropdownMenuItem(value: k.id, child: Text(k.label))),
                ],
                onChanged: (v) => setSheetState(() => keyId = v),
                decoration: InputDecoration(
                  labelText: 'SSH Key',
                  labelStyle: const TextStyle(color: textDim),
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
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () async {
                    await storage.saveDevicePrefs(account.username, prefsKey, {
                      'useMosh': useMosh,
                      if (keyId != null) 'keyId': keyId,
                    });
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _returnToTerminals([int? sessionIndex]) {
    if (sessionIndex != null) {
      final manager = context.read<SessionManager>();
      manager.switchTo(sessionIndex);
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TerminalPage()),
    );
  }

  Future<void> _deleteConnection(Connection conn) async {
    final storage = context.read<StorageService>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete connection'),
        content: Text('Delete "${conn.label}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;
    if (conn.passwordId != null) await storage.deletePassword(conn.passwordId!);
    await storage.deleteConnection(conn.id);
    _loadConnections();
  }

  List<_Tab> get _tabs {
    final base = [
      _Tab('terminal', Icons.terminal, _buildTerminalBody()),
    ];
    if (_signedIn) {
      base.add(_Tab('shells', Icons.dns_outlined, const ShellsTab()));
    }
    base.add(_Tab('account', Icons.person_outline, const AccountView()));
    base.add(_Tab('settings', Icons.settings_outlined, const SettingsView()));
    return base;
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs;
    // Clamp tab index if tabs changed (e.g. signed out)
    if (_currentTab >= tabs.length) _currentTab = 0;

    return Scaffold(
      backgroundColor: bgDark,
      drawer: _buildDrawer(),
      appBar: AppBar(
        backgroundColor: bgSidebar,
        title: Text(tabs[_currentTab].label),
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu, color: textDim),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
      ),
      body: IndexedStack(
        index: _currentTab,
        children: tabs.map((t) => t.body).toList(),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ── Bottom navigation ──

  Widget _buildBottomNav() {
    final tabs = _tabs;
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: borderColor, width: 1)),
        color: bgSidebar,
      ),
      child: SafeArea(
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              for (var i = 0; i < tabs.length; i++)
                _navItem(i, tabs[i].icon, tabs[i].label),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, String label) {
    final selected = _currentTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _currentTab = index);
          _checkSignedIn(); // refresh tabs after switching (catches sign in/out)
        },
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: selected ? accent : textMuted),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 10, color: selected ? accent : textMuted)),
          ],
        ),
      ),
    );
  }

  // ── Left drawer (devices) ──

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: bgSidebar,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('devices', style: TextStyle(color: textDim, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1)),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ConnectView()),
                      ).then((_) => _loadConnections());
                    },
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.add, color: accent, size: 16),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: borderColor),

            // Online relay devices
            Expanded(
              child: Consumer<DiscoveryService>(
                builder: (context, discovery, _) {
                  final online = discovery.onlineDevices;
                  return ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      // Online relay devices
                      if (online.isNotEmpty) ...[
                        _drawerSection('online'),
                        ...online.expand((device) {
                          final alive = device.sessions.where((s) => s.status == 'alive').toList();
                          return [
                            _drawerMachine(device, alive.length, true),
                            ...alive.map((s) => _drawerSession(device, s)),
                          ];
                        }),
                      ],

                      // Saved connections
                      if (_connections.isNotEmpty) ...[
                        _drawerSection('saved'),
                        ..._connections.map((c) => _drawerSavedConnection(c)),
                      ],

                      // Active sessions
                      Consumer<SessionManager>(
                        builder: (context, manager, _) {
                          if (manager.sessions.isEmpty) return const SizedBox.shrink();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _drawerSection('active sessions'),
                              ...manager.sessions.asMap().entries.map((e) {
                                final i = e.key;
                                final session = e.value;
                                return _drawerSessionItem(session.label, i);
                              }),
                            ],
                          );
                        },
                      ),

                      // Empty state
                      if (online.isEmpty && _connections.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child: Text('No devices.\nSign in and start latch.', textAlign: TextAlign.center, style: TextStyle(color: textMuted, fontSize: 12)),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerSection(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(label.toUpperCase(), style: const TextStyle(color: textMuted, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
    );
  }

  Widget _drawerMachine(Device device, int sessionCount, bool online) {
    return InkWell(
      onTap: () {
        debugPrint('DEMO TAP: device=${device.name} sessions=${device.sessions.length}');
        final alive = device.sessions.where((s) => s.status == 'alive').toList();
        debugPrint('DEMO TAP: alive=${alive.length} demo=${DemoService().isActive}');
        if (alive.isNotEmpty) {
          Navigator.pop(context);
          _connectToRelaySession(device, alive.first.name);
        }
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
        child: Row(
          children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: online ? accent : textMuted,
                boxShadow: online ? [BoxShadow(color: accent.withValues(alpha: 0.4), blurRadius: 6)] : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(device.name, style: const TextStyle(color: textBright, fontSize: 14, fontWeight: FontWeight.w500)),
            ),
            if (sessionCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('$sessionCount', style: const TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w500)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _drawerSession(Device device, DeviceSession session) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        _connectToRelaySession(device, session.name);
      },
      onLongPress: () {
        Navigator.pop(context);
        _editRelaySession(device, session.name);
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(40, 12, 20, 12),
        child: Row(
          children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.terminal, color: accent, size: 14),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(session.name, style: const TextStyle(color: textBright, fontSize: 13, fontWeight: FontWeight.w400)),
                  if (session.title.isNotEmpty)
                    Text(session.title, style: const TextStyle(color: textMuted, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: textMuted, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _drawerSavedConnection(Connection conn) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        _connect(conn);
      },
      onLongPress: () => _deleteConnection(conn),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: bgCard,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: borderColor),
              ),
              child: const Icon(Icons.link, color: textDim, size: 14),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(conn.label, style: const TextStyle(color: textBright, fontSize: 13, fontWeight: FontWeight.w400)),
                  Text(conn.destination, style: const TextStyle(color: textMuted, fontSize: 11)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: textMuted, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _drawerSessionItem(String label, int index) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        _returnToTerminals(index);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.terminal, color: accent, size: 14),
            ),
            const SizedBox(width: 12),
            Text(label, style: const TextStyle(color: textBright, fontSize: 13)),
            const Spacer(),
            const Icon(Icons.chevron_right, color: textMuted, size: 16),
          ],
        ),
      ),
    );
  }

  // ── Terminal tab body ──

  Widget _buildTerminalBody() {
    return Consumer<SessionManager>(
      builder: (context, manager, _) {
        if (manager.sessions.isEmpty) {
          // In demo mode, show devices and shells directly here.
          if (DemoService().isActive) {
            return _buildDemoDeviceList();
          }
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.terminal, size: 48, color: textMuted),
                const SizedBox(height: 16),
                const Text('no active sessions', style: TextStyle(color: textMuted, fontSize: 14)),
                const SizedBox(height: 8),
                const Text('swipe right to see devices', style: TextStyle(color: textMuted, fontSize: 12)),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: manager.sessions.length,
          itemBuilder: (context, i) {
            final session = manager.sessions[i];
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: bgCard,
                borderRadius: BorderRadius.circular(6),
              ),
              child: ListTile(
                leading: const Icon(Icons.terminal, color: accent, size: 20),
                title: Text(session.label, style: const TextStyle(color: textBright, fontSize: 13)),
                subtitle: Text(session.connection.destination, style: const TextStyle(color: textMuted, fontSize: 11)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 12, color: textMuted),
                onTap: () => _returnToTerminals(i),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDemoDeviceList() {
    final demo = DemoService();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text('RELAY DEVICES', style: TextStyle(color: textMuted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1)),
        ),
        ...demo.devices.expand((device) {
          return device.sessions.where((s) => s.status == 'alive').map((session) {
            return _buildDemoDeviceCard(device, session);
          });
        }),
        const SizedBox(height: 24),
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text('MANAGED SHELLS', style: TextStyle(color: textMuted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1)),
        ),
        ...demo.shells.where((s) => s.isRunning).map(_buildDemoShellCard),
      ],
    );
  }

  Widget _buildDemoDeviceCard(Device device, DeviceSession session) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: bgCard,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.computer, color: accent, size: 18),
        ),
        title: Text('${device.name} / ${session.name}', style: const TextStyle(color: textBright, fontSize: 14)),
        subtitle: Text(session.title, style: const TextStyle(color: textMuted, fontSize: 12)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: textMuted),
        onTap: () {
          final conn = Connection(
            id: 'demo-${device.name}-${session.name}',
            label: '${device.name}/${session.name}',
            host: '${device.name}.iapdemo.unixshells.com',
            port: 22,
            username: 'iapdemo',
            authMethod: AuthMethod.key,
            type: ConnectionType.relay,
            relayDevice: device.name,
            sessionName: session.name,
          );
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => TerminalPage(pendingConnection: conn)),
          );
        },
      ),
    );
  }

  Widget _buildDemoShellCard(Shell shell) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: bgCard,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.dns, color: accent, size: 18),
        ),
        title: Text(shell.id, style: const TextStyle(color: textBright, fontSize: 14, fontFamily: 'monospace')),
        subtitle: Text('${shell.plan} — ${shell.specs}', style: const TextStyle(color: textMuted, fontSize: 12)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: textMuted),
        onTap: () {
          final conn = Connection(
            id: 'shell-${shell.id}',
            label: shell.id,
            host: '${shell.id}.iapdemo.unixshells.com',
            port: 22,
            username: 'iapdemo',
            authMethod: AuthMethod.key,
            type: ConnectionType.relay,
            relayDevice: shell.id,
            sessionName: 'default',
          );
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => TerminalPage(pendingConnection: conn)),
          );
        },
      ),
    );
  }
}
