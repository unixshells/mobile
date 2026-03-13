import 'port_forward.dart';

enum ConnectionType { direct, relay }

enum AuthMethod { key, password }

class Connection {
  final String id;
  String label;
  ConnectionType type;
  String host;
  int port;
  String username;
  AuthMethod authMethod;
  String? keyId;
  String? passwordId;

  // Relay-specific fields.
  String? relayUsername;
  String? relayDevice;

  // Forwarding.
  List<PortForward> portForwards;
  bool agentForwarding;

  // Mosh.
  bool useMosh;

  // Latch session name (null or empty = "default").
  String? sessionName;

  int? lastConnected;
  int sortOrder;

  Connection({
    required this.id,
    required this.label,
    this.type = ConnectionType.direct,
    required this.host,
    this.port = 22,
    this.username = '',
    this.authMethod = AuthMethod.key,
    this.keyId,
    this.passwordId,
    this.relayUsername,
    this.relayDevice,
    this.portForwards = const [],
    this.agentForwarding = false,
    this.useMosh = false,
    this.sessionName,
    this.lastConnected,
    this.sortOrder = 0,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'type': type.name,
        'host': host,
        'port': port,
        'username': username,
        'authMethod': authMethod.name,
        'keyId': keyId,
        'passwordId': passwordId,
        'relayUsername': relayUsername,
        'relayDevice': relayDevice,
        'portForwards': PortForward.encodeList(portForwards),
        'agentForwarding': agentForwarding ? 1 : 0,
        'useMosh': useMosh ? 1 : 0,
        'sessionName': sessionName,
        'lastConnected': lastConnected,
        'sortOrder': sortOrder,
      };

  factory Connection.fromMap(Map<String, dynamic> m) => Connection(
        id: m['id'] as String,
        label: m['label'] as String,
        type: ConnectionType.values.byName(m['type'] as String),
        host: m['host'] as String,
        port: m['port'] as int,
        username: m['username'] as String,
        authMethod: AuthMethod.values.byName(m['authMethod'] as String),
        keyId: m['keyId'] as String?,
        passwordId: m['passwordId'] as String?,
        relayUsername: m['relayUsername'] as String?,
        relayDevice: m['relayDevice'] as String?,
        portForwards:
            PortForward.decodeList(m['portForwards'] as String?),
        agentForwarding: (m['agentForwarding'] as int?) == 1,
        useMosh: (m['useMosh'] as int?) == 1,
        sessionName: m['sessionName'] as String?,
        lastConnected: m['lastConnected'] as int?,
        sortOrder: m['sortOrder'] as int? ?? 0,
      );

  Connection copyWith({
    String? label,
    ConnectionType? type,
    String? host,
    int? port,
    String? username,
    AuthMethod? authMethod,
    String? keyId,
    String? passwordId,
    String? relayUsername,
    String? relayDevice,
    List<PortForward>? portForwards,
    bool? agentForwarding,
    bool? useMosh,
    String? sessionName,
    int? sortOrder,
  }) {
    return Connection(
      id: id,
      label: label ?? this.label,
      type: type ?? this.type,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      authMethod: authMethod ?? this.authMethod,
      keyId: keyId ?? this.keyId,
      passwordId: passwordId ?? this.passwordId,
      relayUsername: relayUsername ?? this.relayUsername,
      relayDevice: relayDevice ?? this.relayDevice,
      portForwards: portForwards ?? this.portForwards,
      agentForwarding: agentForwarding ?? this.agentForwarding,
      useMosh: useMosh ?? this.useMosh,
      sessionName: sessionName ?? this.sessionName,
      lastConnected: lastConnected,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  /// Display string for the connection destination.
  String get destination {
    if (type == ConnectionType.relay) {
      final dev = relayDevice ?? '';
      final user = relayUsername ?? '';
      if (dev.isNotEmpty) return '$dev.$user';
      return user;
    }
    if (port != 22) return '$host:$port';
    return host;
  }
}
