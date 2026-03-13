import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/connection.dart';
import '../../services/storage_service.dart';
import '../../util/constants.dart';
import '../connect/connect_view.dart';
import '../account/account_view.dart';
import '../keys/key_list_view.dart';
import '../local/local_terminal_view.dart';
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
    _tabController = TabController(length: 2, vsync: this);
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
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Unix Shells'),
          ],
        ),
        actions: [
          if (Platform.isAndroid || Platform.isMacOS || Platform.isLinux)
            IconButton(
              icon: const Icon(Icons.terminal_outlined),
              tooltip: 'Local Terminal',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const LocalTerminalView()),
              ),
            ),
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
            icon: const Icon(Icons.person_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AccountView()),
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
                _buildConnectionList(_filter(_relayConnections)),
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
