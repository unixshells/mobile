import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/connection.dart';
import '../../models/device.dart';
import '../../services/discovery_service.dart';
import '../shells/shells_view.dart';
import '../../services/key_service.dart';
import '../../services/session_manager.dart';
import '../../services/storage_service.dart';
import '../../util/constants.dart';
import '../connect/connect_view.dart';
import '../keys/key_list_view.dart';
import '../settings/settings_view.dart';
import '../terminal/terminal_view.dart';
import 'connection_tile.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Connection> _connections = [];
  bool _loading = true;
  String _searchQuery = '';
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadConnections();
  }

  Future<void> _loadConnections() async {
    final storage = context.read<StorageService>();
    final conns = await storage.listConnections();
    setState(() {
      _connections = conns;
      _loading = false;
    });
  }

  List<Connection> get _relayConnections =>
      _connections.where((c) => c.type == ConnectionType.relay).toList();

  List<Connection> _filter(List<Connection> conns) {
    if (_searchQuery.isEmpty) return conns;
    final q = _searchQuery.toLowerCase();
    return conns
        .where((c) =>
            c.label.toLowerCase().contains(q) ||
            c.destination.toLowerCase().contains(q) ||
            c.username.toLowerCase().contains(q))
        .toList();
  }

  void _connect(Connection conn) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TerminalPage(pendingConnection: conn),
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
        backgroundColor: bgCard,
        title: const Text('Delete Connection',
            style: TextStyle(color: textBright)),
        content: Text('Delete "${conn.label}"?',
            style: const TextStyle(color: textDim)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (conn.passwordId != null) {
      await storage.deletePassword(conn.passwordId!);
    }
    await storage.deleteConnection(conn.id);
    await _loadConnections();
  }

  Future<void> _resetHostKeyForConnection(Connection conn) async {
    final storage = context.read<StorageService>();
    final messenger = ScaffoldMessenger.of(context);
    if (conn.type == ConnectionType.relay) {
      final host = await storage.getSetting('relay_host');
      final relayHost = (host != null && host.isNotEmpty) ? host : 'unixshells.com';
      final dest = '${conn.relayDevice}.${conn.relayUsername}.$relayHost';
      await storage.deleteHostKey(dest, defaultSSHPort);
    } else {
      await storage.deleteHostKey(conn.host, conn.port);
    }
    messenger.showSnackBar(
      const SnackBar(content: Text('Host key cleared')),
    );
  }

  Future<void> _resetHostKeyForSession(Device device, String sessionName) async {
    final storage = context.read<StorageService>();
    final account = await storage.getAccount();
    final messenger = ScaffoldMessenger.of(context);
    if (account == null) return;
    final host = await storage.getSetting('relay_host');
    final relayHost = (host != null && host.isNotEmpty) ? host : 'unixshells.com';
    final dest = '${device.name}.${account.username}.$relayHost';
    await storage.deleteHostKey(dest, defaultSSHPort);
    messenger.showSnackBar(
      const SnackBar(content: Text('Host key cleared')),
    );
  }

  Future<void> _onReorder(List<Connection> conns, int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    final item = conns.removeAt(oldIndex);
    conns.insert(newIndex, item);
    for (var i = 0; i < conns.length; i++) {
      conns[i].sortOrder = i;
    }
    final storage = context.read<StorageService>();
    await storage.reorderConnections(conns);
    await _loadConnections();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgDark,
      appBar: AppBar(
        title: _searching
            ? TextField(
                autofocus: true,
                style: const TextStyle(color: textBright),
                decoration: const InputDecoration(
                  hintText: 'Search connections...',
                  hintStyle: TextStyle(color: textMuted),
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              )
            : const Text('Unix Shells'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            const Tab(text: 'All'),
            const Tab(text: 'Relay'),
            const Tab(text: 'Shells'),
            Consumer<SessionManager>(
              builder: (context, manager, _) {
                final count = manager.sessions.length;
                return Tab(
                  text: count > 0 ? 'Sessions ($count)' : 'Sessions',
                );
              },
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _searching = !_searching;
                if (!_searching) _searchQuery = '';
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.vpn_key_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const KeyListView()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsView()),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildConnectionList(_filter(_connections)),
                _buildUnixShellsTab(),
                _buildShellsTab(),
                _buildSessionList(),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddMenu(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<Connection> _buildDeviceConnection(Device device) async {
    final storage = context.read<StorageService>();
    final keyService = context.read<KeyService>();
    final account = await storage.getAccount();
    if (account == null) throw Exception('not signed in');
    final keys = await keyService.list();
    final prefs = await storage.getDevicePrefs(account.username, device.name);
    return Connection(
      id: 'discovered_${device.name}',
      label: device.name,
      type: ConnectionType.relay,
      host: '',
      username: account.username,
      authMethod: AuthMethod.key,
      keyId: prefs['keyId'] as String? ?? (keys.isNotEmpty ? keys.first.id : null),
      relayUsername: account.username,
      relayDevice: device.name,
      useMosh: prefs['useMosh'] as bool? ?? false,
      sessionName: prefs['sessionName'] as String?,
    );
  }

  Future<void> _connectToDevice(Device device) async {
    final conn = await _buildDeviceConnection(device);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TerminalPage(pendingConnection: conn),
      ),
    );
  }

  Future<void> _connectToDeviceSession(Device device, String sessionName) async {
    final storage = context.read<StorageService>();
    final account = await storage.getAccount();
    final conn = await _buildDeviceConnection(device);
    // Check per-session prefs (mosh, key) — fall back to device prefs,
    // then to first available key.
    if (account != null) {
      final sessionPrefs = await storage.getDevicePrefs(
          account.username, '${device.name}:$sessionName');
      final useMosh = sessionPrefs['useMosh'] as bool? ?? conn.useMosh;
      var keyId = sessionPrefs['keyId'] as String? ?? conn.keyId;
      // Verify the key still exists, fall back to first available.
      if (keyId != null) {
        final keyService = context.read<KeyService>();
        final identities = await keyService.loadIdentity(keyId);
        if (identities.isEmpty) {
          final keys = await keyService.list();
          keyId = keys.isNotEmpty ? keys.first.id : null;
        }
      }
      final withSession = conn.copyWith(
          sessionName: sessionName, useMosh: useMosh, keyId: keyId);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TerminalPage(pendingConnection: withSession),
        ),
      );
      return;
    }
    final withSession = conn.copyWith(sessionName: sessionName);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TerminalPage(pendingConnection: withSession),
      ),
    );
  }

  Future<void> _editSessionPrefs(Device device, String sessionName) async {
    final storage = context.read<StorageService>();
    final keyService = context.read<KeyService>();
    final account = await storage.getAccount();
    if (account == null) return;
    final keys = await keyService.list();
    final prefs = await storage.getDevicePrefs(account.username, '${device.name}:$sessionName');

    var useMosh = prefs['useMosh'] as bool? ?? false;
    var keyId = prefs['keyId'] as String? ?? (keys.isNotEmpty ? keys.first.id : null);

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: bgCard,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${device.name} / $sessionName',
                  style: const TextStyle(
                      color: textBright,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Use Mosh',
                    style: TextStyle(color: textBright)),
                value: useMosh,
                onChanged: (v) => setSheetState(() => useMosh = v),
              ),
              if (keys.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: keyId,
                  dropdownColor: bgCard,
                  style: const TextStyle(color: textBright),
                  items: keys.map((k) => DropdownMenuItem(
                        value: k.id,
                        child: Text(k.label,
                            style: const TextStyle(color: textBright)),
                      )).toList(),
                  onChanged: (v) => setSheetState(() => keyId = v),
                  decoration: InputDecoration(
                    labelText: 'SSH Key',
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
                    fillColor: bgDark,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: accent),
                  onPressed: () async {
                    final newPrefs = <String, dynamic>{
                      'useMosh': useMosh,
                      if (keyId != null) 'keyId': keyId,
                    };
                    await storage.saveDevicePrefs(
                        account.username, '${device.name}:$sessionName', newPrefs);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('Save',
                      style: TextStyle(color: textBright)),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () async {
                    await _resetHostKeyForSession(device, sessionName);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('Reset Host Key',
                      style: TextStyle(color: textMuted, fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editDevicePrefs(Device device) async {
    final storage = context.read<StorageService>();
    final keyService = context.read<KeyService>();
    final account = await storage.getAccount();
    if (account == null) return;
    final keys = await keyService.list();
    final prefs = await storage.getDevicePrefs(account.username, device.name);

    var useMosh = prefs['useMosh'] as bool? ?? false;
    var sessionName = prefs['sessionName'] as String? ?? '';
    var keyId = prefs['keyId'] as String? ?? (keys.isNotEmpty ? keys.first.id : null);
    final sessionCtrl = TextEditingController(text: sessionName);

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: bgCard,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(device.name,
                  style: const TextStyle(
                      color: textBright,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Use Mosh',
                    style: TextStyle(color: textBright)),
                value: useMosh,
                onChanged: (v) => setSheetState(() => useMosh = v),
              ),
              TextField(
                controller: sessionCtrl,
                style: const TextStyle(color: textBright),
                decoration: InputDecoration(
                  labelText: 'Session Name',
                  labelStyle: const TextStyle(color: textDim),
                  hintText: 'default',
                  hintStyle: const TextStyle(color: borderColor),
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
              if (keys.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: keyId,
                  dropdownColor: bgCard,
                  style: const TextStyle(color: textBright),
                  items: keys.map((k) => DropdownMenuItem(
                        value: k.id,
                        child: Text(k.label,
                            style: const TextStyle(color: textBright)),
                      )).toList(),
                  onChanged: (v) => setSheetState(() => keyId = v),
                  decoration: InputDecoration(
                    labelText: 'SSH Key',
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
                    fillColor: bgDark,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: accent),
                  onPressed: () async {
                    final newPrefs = <String, dynamic>{
                      'useMosh': useMosh,
                      'sessionName': sessionCtrl.text.trim(),
                      if (keyId != null) 'keyId': keyId,
                    };
                    await storage.saveDevicePrefs(
                        account.username, device.name, newPrefs);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('Save',
                      style: TextStyle(color: textBright)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUnixShellsTab() {
    return Consumer<DiscoveryService>(
      builder: (context, discovery, _) {
        final online = discovery.onlineDevices;
        final saved = _filter(_relayConnections);
        // Filter out saved connections that match an online device.
        final savedDeviceNames = <String>{};
        for (final c in saved) {
          if (c.relayDevice != null) savedDeviceNames.add(c.relayDevice!);
        }
        final onlineOnly = online
            .where((d) => !savedDeviceNames.contains(d.name))
            .toList();

        if (online.isEmpty && saved.isEmpty) {
          return RefreshIndicator(
            onRefresh: () async {
              await discovery.refresh();
              await _loadConnections();
            },
            child: ListView(
              children: const [
                SizedBox(height: 120),
                Center(
                  child: Column(
                    children: [
                      Icon(Icons.cloud_outlined, size: 64, color: borderColor),
                      SizedBox(height: 16),
                      Text('No devices online',
                          style: TextStyle(color: textMuted, fontSize: 16)),
                      SizedBox(height: 8),
                      Text('Sign in and start latch on a machine',
                          style: TextStyle(color: borderColor, fontSize: 14)),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            await discovery.refresh();
            await _loadConnections();
          },
          child: ListView(
            children: [
              if (onlineOnly.isNotEmpty) ...[
                _tabSectionHeader('Online'),
                ...onlineOnly.expand((device) {
                  final alive = device.sessions
                      .where((s) => s.status == 'alive')
                      .toList();
                  return [
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: accent.withValues(alpha: 0.2),
                        child: const Icon(Icons.computer, color: accent, size: 18),
                      ),
                      title: Text(device.name,
                          style: const TextStyle(color: textBright, fontSize: 15)),
                      subtitle: Text(
                          alive.isEmpty
                              ? 'no sessions'
                              : '${alive.length} session${alive.length == 1 ? '' : 's'}',
                          style: const TextStyle(color: textMuted, fontSize: 13)),
                    ),
                    ...alive.map((session) => ListTile(
                          contentPadding: const EdgeInsets.only(left: 32, right: 16),
                          leading: const Icon(Icons.terminal, color: textMuted, size: 20),
                          title: Text(session.name,
                              style: const TextStyle(color: textDim, fontSize: 14)),
                          subtitle: session.title.isNotEmpty
                              ? Text(session.title,
                                  style: const TextStyle(color: textMuted, fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis)
                              : null,
                          trailing: PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert, color: textMuted),
                            color: bgCard,
                            onSelected: (value) {
                              if (value == 'edit') _editSessionPrefs(device, session.name);
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'edit',
                                child: Text('Edit', style: TextStyle(color: textBright)),
                              ),
                            ],
                          ),
                          onTap: () => _connectToDeviceSession(device, session.name),
                        )),
                  ];
                }),
              ],
              if (saved.isNotEmpty) ...[
                if (onlineOnly.isNotEmpty) _tabSectionHeader('Saved'),
                ...saved.map((conn) {
                  // Mark saved connections that are online.
                  final isOnline = online.any((d) => d.name == conn.relayDevice);
                  return ConnectionTile(
                    key: ValueKey(conn.id),
                    connection: conn,
                    onTap: () => _connect(conn),
                    onDelete: () => _deleteConnection(conn),
                    onEdit: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ConnectView(existing: conn),
                        ),
                      );
                      _loadConnections();
                    },
                    onResetHostKey: () => _resetHostKeyForConnection(conn),
                    trailing: isOnline
                        ? const Icon(Icons.circle, color: accent, size: 8)
                        : null,
                  );
                }),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _tabSectionHeader(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(text,
          style: const TextStyle(
              color: textDim, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  void _showAddMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32, height: 4, margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: textMuted, borderRadius: BorderRadius.circular(2)),
              ),
              _addMenuItem(ctx, Icons.terminal, 'SSH connection', 'Connect to a host via SSH', () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ConnectView()),
                ).then((_) => _loadConnections());
              }),
              _addMenuItem(ctx, Icons.cloud_outlined, 'Relay device', 'Add a device via latch relay', () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ConnectView()),
                ).then((_) => _loadConnections());
              }),
              _addMenuItem(ctx, Icons.dns_outlined, 'New shell', 'Provision a managed Linux VM', () {
                Navigator.pop(ctx);
                _tabController.animateTo(2); // Switch to Shells tab
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _addMenuItem(BuildContext ctx, IconData icon, String title, String subtitle, VoidCallback onTap) {
    return ListTile(
      leading: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: accent, size: 20),
      ),
      title: Text(title, style: const TextStyle(color: textBright, fontSize: 14, fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle, style: const TextStyle(color: textMuted, fontSize: 12)),
      onTap: onTap,
    );
  }

  Widget _buildShellsTab() {
    return const ShellsTab();
  }

  Widget _buildSessionList() {
    return Consumer<SessionManager>(
      builder: (context, manager, _) {
        if (manager.sessions.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.terminal, size: 64, color: borderColor),
                SizedBox(height: 16),
                Text(
                  'No active sessions',
                  style: TextStyle(color: textMuted, fontSize: 16),
                ),
                SizedBox(height: 8),
                Text(
                  'Connect to a server to start one',
                  style: TextStyle(color: borderColor, fontSize: 14),
                ),
              ],
            ),
          );
        }
        return ListView.builder(
          itemCount: manager.sessions.length,
          itemBuilder: (context, i) {
            final session = manager.sessions[i];
            final isRelay = session.connection.type == ConnectionType.relay;
            final duration = DateTime.now().difference(session.createdAt);
            String elapsed;
            if (duration.inHours > 0) {
              elapsed = '${duration.inHours}h ${duration.inMinutes % 60}m';
            } else if (duration.inMinutes > 0) {
              elapsed = '${duration.inMinutes}m';
            } else {
              elapsed = 'just now';
            }
            return ListTile(
              leading: CircleAvatar(
                backgroundColor:
                    isRelay ? accent.withValues(alpha: 0.2) : bgButton,
                child: Icon(
                  isRelay ? Icons.cloud : Icons.computer,
                  color: isRelay ? accent : textDim,
                  size: 20,
                ),
              ),
              title: Text(
                session.label,
                style: const TextStyle(color: textBright, fontSize: 15),
              ),
              subtitle: Text(
                '${session.connection.destination} · $elapsed',
                style: const TextStyle(color: textMuted, fontSize: 13),
              ),
              trailing: const Icon(Icons.arrow_forward_ios,
                  size: 14, color: borderColor),
              onTap: () => _returnToTerminals(i),
            );
          },
        );
      },
    );
  }

  Widget _buildConnectionList(List<Connection> connections) {
    if (connections.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.terminal, size: 64, color: borderColor),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isEmpty
                  ? 'No connections yet'
                  : 'No matches',
              style: const TextStyle(color: textMuted, fontSize: 16),
            ),
            if (_searchQuery.isEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'Tap + to add one',
                style: TextStyle(color: borderColor, fontSize: 14),
              ),
            ],
          ],
        ),
      );
    }

    if (_searchQuery.isNotEmpty) {
      return RefreshIndicator(
        onRefresh: _loadConnections,
        child: ListView.builder(
          itemCount: connections.length,
          itemBuilder: (context, i) => ConnectionTile(
            key: ValueKey(connections[i].id),
            connection: connections[i],
            onTap: () => _connect(connections[i]),
            onDelete: () => _deleteConnection(connections[i]),
            onEdit: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ConnectView(existing: connections[i]),
                ),
              );
              _loadConnections();
            },
            onResetHostKey: () => _resetHostKeyForConnection(connections[i]),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadConnections,
      child: ReorderableListView.builder(
        itemCount: connections.length,
        onReorder: (oldIndex, newIndex) =>
            _onReorder(connections, oldIndex, newIndex),
        itemBuilder: (context, i) => ConnectionTile(
          key: ValueKey(connections[i].id),
          connection: connections[i],
          onTap: () => _connect(connections[i]),
          onDelete: () => _deleteConnection(connections[i]),
          onEdit: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    ConnectView(existing: connections[i]),
              ),
            );
            _loadConnections();
          },
          onResetHostKey: () => _resetHostKeyForConnection(connections[i]),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}
