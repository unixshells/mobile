import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/connection.dart';
import '../../models/device.dart';
import '../../services/discovery_service.dart';
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
    _tabController = TabController(length: 3, vsync: this);
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
            style: TextStyle(color: Colors.white)),
        content: Text('Delete "${conn.label}"?',
            style: const TextStyle(color: Colors.white70)),
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
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Search connections...',
                  hintStyle: TextStyle(color: Colors.white38),
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              )
            : const Text('Unix Shells'),
        backgroundColor: bgCard,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.blue,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          tabs: [
            const Tab(text: 'All'),
            const Tab(text: 'Unix Shells'),
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
                _buildSessionList(),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.blue,
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ConnectView()),
          );
          _loadConnections();
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<Connection> _buildDeviceConnection(Device device) async {
    final storage = context.read<StorageService>();
    final account = await storage.getAccount();
    if (account == null) throw Exception('not signed in');
    final keyService = context.read<KeyService>();
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

  Future<void> _editDevicePrefs(Device device) async {
    final storage = context.read<StorageService>();
    final account = await storage.getAccount();
    if (account == null) return;
    final keyService = context.read<KeyService>();
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
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Use Mosh',
                    style: TextStyle(color: Colors.white)),
                value: useMosh,
                onChanged: (v) => setSheetState(() => useMosh = v),
              ),
              TextField(
                controller: sessionCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Session Name',
                  labelStyle: const TextStyle(color: Colors.white54),
                  hintText: 'default',
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
                  fillColor: bgDark,
                ),
              ),
              if (keys.length > 1) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: keyId,
                  dropdownColor: bgCard,
                  style: const TextStyle(color: Colors.white),
                  items: keys.map((k) => DropdownMenuItem(
                        value: k.id,
                        child: Text(k.label,
                            style: const TextStyle(color: Colors.white)),
                      )).toList(),
                  onChanged: (v) => setSheetState(() => keyId = v),
                  decoration: InputDecoration(
                    labelText: 'SSH Key',
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
                    fillColor: bgDark,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
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
                      style: TextStyle(color: Colors.white)),
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
                      Icon(Icons.cloud_outlined, size: 64, color: Colors.white24),
                      SizedBox(height: 16),
                      Text('No devices online',
                          style: TextStyle(color: Colors.white38, fontSize: 16)),
                      SizedBox(height: 8),
                      Text('Sign in and start latch on a machine',
                          style: TextStyle(color: Colors.white24, fontSize: 14)),
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
                ...onlineOnly.map((device) => ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.green.withValues(alpha: 0.2),
                        child: const Icon(Icons.circle, color: Colors.green, size: 12),
                      ),
                      title: Text(device.name,
                          style: const TextStyle(color: Colors.white, fontSize: 15)),
                      subtitle: Text(device.status,
                          style: const TextStyle(color: Colors.white38, fontSize: 13)),
                      trailing: PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, color: Colors.white38),
                        color: bgCard,
                        onSelected: (value) {
                          if (value == 'edit') _editDevicePrefs(device);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit', style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
                      onTap: () => _connectToDevice(device),
                    )),
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
                    trailing: isOnline
                        ? const Icon(Icons.circle, color: Colors.green, size: 8)
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
              color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildSessionList() {
    return Consumer<SessionManager>(
      builder: (context, manager, _) {
        if (manager.sessions.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.terminal, size: 64, color: Colors.white24),
                SizedBox(height: 16),
                Text(
                  'No active sessions',
                  style: TextStyle(color: Colors.white38, fontSize: 16),
                ),
                SizedBox(height: 8),
                Text(
                  'Connect to a server to start one',
                  style: TextStyle(color: Colors.white24, fontSize: 14),
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
                    isRelay ? Colors.blue.withValues(alpha: 0.2) : bgButton,
                child: Icon(
                  isRelay ? Icons.cloud : Icons.computer,
                  color: isRelay ? Colors.blue : Colors.white54,
                  size: 20,
                ),
              ),
              title: Text(
                session.label,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
              subtitle: Text(
                '${session.connection.destination} · $elapsed',
                style: const TextStyle(color: Colors.white38, fontSize: 13),
              ),
              trailing: const Icon(Icons.arrow_forward_ios,
                  size: 14, color: Colors.white24),
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
            const Icon(Icons.terminal, size: 64, color: Colors.white24),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isEmpty
                  ? 'No connections yet'
                  : 'No matches',
              style: const TextStyle(color: Colors.white38, fontSize: 16),
            ),
            if (_searchQuery.isEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'Tap + to add one',
                style: TextStyle(color: Colors.white24, fontSize: 14),
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
