import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../models/connection.dart';
import '../models/port_forward.dart';
import '../models/session.dart';
import '../util/constants.dart';
import 'key_service.dart';
import 'ssh_agent.dart';
import 'storage_service.dart';

class SSHService {
  final KeyService _keyService;
  final StorageService _storage;

  SSHService(this._keyService, this._storage);

  /// Build a TOFU host key verifier for the given host:port.
  /// On first connect, stores the fingerprint. On subsequent connects,
  /// rejects if the fingerprint has changed.
  FutureOr<bool> Function(String type, Uint8List fingerprint)
      _makeHostKeyVerifier(String host, int port) {
    return (String type, Uint8List fingerprint) async {
      final fpHex = fingerprint
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(':');
      final stored = await _storage.getHostKey(host, port);
      if (stored == null) {
        await _storage.saveHostKey(host, port, fpHex);
        return true;
      }
      return stored == fpHex;
    };
  }

  /// Connect to a host. Returns the client and optionally the jump client.
  /// For relay connections, uses ProxyJump via forwardLocal.
  Future<SSHConnectResult> connect(Connection conn) async {
    final identity = await _loadIdentity(conn);

    // Load all keys for agent forwarding if enabled.
    List<SSHKeyPair>? agentKeys;
    if (conn.agentForwarding) {
      agentKeys = await _loadAllIdentities();
    }

    if (conn.type == ConnectionType.relay) {
      return _connectRelay(conn, identity, agentKeys: agentKeys);
    }
    return _connectDirect(conn, identity, agentKeys: agentKeys);
  }

  Future<SSHConnectResult> _connectDirect(
      Connection conn, List<SSHKeyPair> identity,
      {List<SSHKeyPair>? agentKeys}) async {
    final client = SSHClient(
      await SSHSocket.connect(conn.host, conn.port).timeout(const Duration(seconds: 15)),
      username: conn.username,
      identities: identity.isNotEmpty ? identity : null,
      onVerifyHostKey: _makeHostKeyVerifier(conn.host, conn.port),
      onPasswordRequest: conn.authMethod == AuthMethod.password
          ? () async {
              final pw = await _storage.getPassword(conn.passwordId ?? '');
              if (pw == null) throw Exception('password not found');
              return pw;
            }
          : null,
      onAgentChannel: agentKeys != null
          ? (channel) => SSHAgentHandler(agentKeys).handle(channel)
          : null,
    );
    return SSHConnectResult(targetClient: client);
  }

  Future<String> _getRelayHost() async {
    final custom = await _storage.getSetting('relay_host');
    return (custom != null && custom.isNotEmpty) ? custom : relayHost;
  }

  Future<String> _getRelayJumpHost() async {
    final custom = await _storage.getSetting('relay_host');
    return (custom != null && custom.isNotEmpty) ? custom : relayJumpHost;
  }

  Future<SSHConnectResult> _connectRelay(
      Connection conn, List<SSHKeyPair> identity,
      {List<SSHKeyPair>? agentKeys}) async {
    final host = await _getRelayHost();
    final jumpHost = await _getRelayJumpHost();
    final dest = '${conn.relayDevice}.${conn.relayUsername}.$host';

    // Step 1: Connect to jump host (no auth on jump leg).
    final jumpClient = SSHClient(
      await SSHSocket.connect(jumpHost, relaySSHPort).timeout(const Duration(seconds: 15)),
      username: 'jump',
      onVerifyHostKey: _makeHostKeyVerifier(jumpHost, relaySSHPort),
    );

    // Step 2: Open direct-tcpip tunnel through the relay.
    final tunnel = await jumpClient.forwardLocal(dest, defaultSSHPort).timeout(const Duration(seconds: 30));

    // Step 3: SSH through the tunnel (end-to-end encrypted).
    final targetClient = SSHClient(
      tunnel,
      username: conn.sessionName?.isNotEmpty == true ? conn.sessionName! : 'default',
      identities: identity.isNotEmpty ? identity : null,
      onVerifyHostKey: _makeHostKeyVerifier(dest, defaultSSHPort),
      onPasswordRequest: conn.authMethod == AuthMethod.password
          ? () async {
              final pw = await _storage.getPassword(conn.passwordId ?? '');
              if (pw == null) throw Exception('password not found');
              return pw;
            }
          : null,
      onAgentChannel: agentKeys != null
          ? (channel) => SSHAgentHandler(agentKeys).handle(channel)
          : null,
    );

    return SSHConnectResult(
      jumpClient: jumpClient,
      targetClient: targetClient,
    );
  }

  /// Open an interactive shell on the client.
  /// Session selection is handled by the SSH username, so this always
  /// opens a plain shell.
  Future<SSHSession> openShell(SSHClient client,
      {int cols = 80,
      int rows = 24,
      bool agentForwarding = false}) async {
    final pty = SSHPtyConfig(
      width: cols,
      height: rows,
      type: terminalType,
    );

    return await client.shell(
      pty: pty,
      agentForwarding: agentForwarding,
    );
  }

  /// Start port forwards for a connection. Returns list of active forwards.
  Future<List<ActiveForward>> startPortForwards(
      SSHClient client, List<PortForward> forwards) async {
    final active = <ActiveForward>[];
    for (final fwd in forwards) {
      if (fwd.type == ForwardType.local) {
        final af = await _startLocalForward(client, fwd);
        active.add(af);
      } else {
        final af = await _startRemoteForward(client, fwd);
        if (af != null) active.add(af);
      }
    }
    return active;
  }

  Future<ActiveForward> _startLocalForward(
      SSHClient client, PortForward fwd) async {
    final server =
        await ServerSocket.bind(InternetAddress.loopbackIPv4, fwd.localPort);
    server.listen((socket) async {
      try {
        final channel =
            await client.forwardLocal(fwd.remoteHost, fwd.remotePort);
        socket.addStream(channel.stream).catchError((_) {});
        channel.sink.addStream(socket).catchError((_) {});
      } catch (_) {
        socket.destroy();
      }
    });
    return ActiveForward(
      description: 'L${fwd.localPort}:${fwd.remoteHost}:${fwd.remotePort}',
      server: server,
    );
  }

  Future<ActiveForward?> _startRemoteForward(
      SSHClient client, PortForward fwd) async {
    final remote = await client.forwardRemote(port: fwd.remotePort);
    if (remote == null) return null;
    remote.connections.listen((conn) async {
      try {
        final socket = await Socket.connect(
            InternetAddress.loopbackIPv4, fwd.localPort);
        socket.addStream(conn.stream).catchError((_) {});
        conn.sink.addStream(socket).catchError((_) {});
      } catch (_) {
        conn.sink.close();
      }
    });
    return ActiveForward(
      description: 'R${fwd.remotePort}:${fwd.remoteHost}:${fwd.localPort}',
    );
  }

  Future<List<SSHKeyPair>> _loadIdentity(Connection conn) async {
    if (conn.authMethod != AuthMethod.key || conn.keyId == null) return [];
    return await _keyService.loadIdentity(conn.keyId!);
  }

  /// Load all stored keys for agent forwarding.
  Future<List<SSHKeyPair>> _loadAllIdentities() async {
    final keys = await _keyService.list();
    final all = <SSHKeyPair>[];
    for (final key in keys) {
      final identities = await _keyService.loadIdentity(key.id);
      all.addAll(identities);
    }
    return all;
  }
}

class SSHConnectResult {
  final SSHClient? jumpClient;
  final SSHClient targetClient;

  SSHConnectResult({this.jumpClient, required this.targetClient});
}
