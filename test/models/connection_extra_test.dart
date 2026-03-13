import 'package:flutter_test/flutter_test.dart';
import 'package:unixshells/models/connection.dart';
import 'package:unixshells/models/port_forward.dart';

void main() {
  group('Connection destination', () {
    test('relay with device and username', () {
      final conn = Connection(
        id: '1',
        label: 'relay',
        type: ConnectionType.relay,
        host: '',
        relayUsername: 'rasengan',
        relayDevice: 'macbook',
      );
      expect(conn.destination, 'macbook.rasengan');
    });

    test('relay with only username (null device)', () {
      final conn = Connection(
        id: '1',
        label: 'relay',
        type: ConnectionType.relay,
        host: '',
        relayUsername: 'rasengan',
        relayDevice: null,
      );
      expect(conn.destination, 'rasengan');
    });

    test('relay with only username (empty device)', () {
      final conn = Connection(
        id: '1',
        label: 'relay',
        type: ConnectionType.relay,
        host: '',
        relayUsername: 'rasengan',
        relayDevice: '',
      );
      expect(conn.destination, 'rasengan');
    });

    test('direct with non-standard port', () {
      final conn = Connection(
        id: '1',
        label: 'srv',
        host: 'example.com',
        port: 2222,
      );
      expect(conn.destination, 'example.com:2222');
    });

    test('direct with default port 22', () {
      final conn = Connection(
        id: '1',
        label: 'srv',
        host: 'example.com',
        port: 22,
      );
      expect(conn.destination, 'example.com');
    });
  });

  group('Connection copyWith', () {
    test('preserves unchanged fields', () {
      final conn = Connection(
        id: 'orig',
        label: 'Original',
        type: ConnectionType.direct,
        host: 'host.com',
        port: 2222,
        username: 'admin',
        authMethod: AuthMethod.password,
        keyId: 'k1',
        passwordId: 'p1',
        relayUsername: 'ru',
        relayDevice: 'rd',
        agentForwarding: true,
        useMosh: true,
        sessionName: 'ops',
        lastConnected: 99999,
        sortOrder: 7,
      );

      final copy = conn.copyWith(label: 'Changed');

      expect(copy.id, 'orig');
      expect(copy.label, 'Changed');
      expect(copy.type, ConnectionType.direct);
      expect(copy.host, 'host.com');
      expect(copy.port, 2222);
      expect(copy.username, 'admin');
      expect(copy.authMethod, AuthMethod.password);
      expect(copy.keyId, 'k1');
      expect(copy.passwordId, 'p1');
      expect(copy.relayUsername, 'ru');
      expect(copy.relayDevice, 'rd');
      expect(copy.agentForwarding, isTrue);
      expect(copy.useMosh, isTrue);
      expect(copy.sessionName, 'ops');
      expect(copy.lastConnected, 99999);
      expect(copy.sortOrder, 7);
    });

    test('overrides multiple fields at once', () {
      final conn = Connection(
        id: '1',
        label: 'old',
        host: 'old.com',
        port: 22,
        username: 'olduser',
      );

      final copy = conn.copyWith(
        label: 'new',
        host: 'new.com',
        port: 3333,
        username: 'newuser',
      );

      expect(copy.id, '1');
      expect(copy.label, 'new');
      expect(copy.host, 'new.com');
      expect(copy.port, 3333);
      expect(copy.username, 'newuser');
    });
  });

  group('Connection toMap/fromMap', () {
    test('preserves agentForwarding true', () {
      final conn = Connection(
        id: 'af1',
        label: 'test',
        host: 'h',
        username: 'u',
        agentForwarding: true,
      );

      final map = conn.toMap();
      expect(map['agentForwarding'], 1);

      final restored = Connection.fromMap(map);
      expect(restored.agentForwarding, isTrue);
    });

    test('preserves agentForwarding false', () {
      final conn = Connection(
        id: 'af2',
        label: 'test',
        host: 'h',
        username: 'u',
        agentForwarding: false,
      );

      final map = conn.toMap();
      expect(map['agentForwarding'], 0);

      final restored = Connection.fromMap(map);
      expect(restored.agentForwarding, isFalse);
    });

    test('preserves useMosh true', () {
      final conn = Connection(
        id: 'm1',
        label: 'test',
        host: 'h',
        username: 'u',
        useMosh: true,
      );

      final map = conn.toMap();
      expect(map['useMosh'], 1);

      final restored = Connection.fromMap(map);
      expect(restored.useMosh, isTrue);
    });

    test('preserves useMosh false', () {
      final conn = Connection(
        id: 'm2',
        label: 'test',
        host: 'h',
        username: 'u',
        useMosh: false,
      );

      final map = conn.toMap();
      expect(map['useMosh'], 0);

      final restored = Connection.fromMap(map);
      expect(restored.useMosh, isFalse);
    });

    test('preserves portForwards through round-trip', () {
      final conn = Connection(
        id: 'pf1',
        label: 'test',
        host: 'h',
        username: 'u',
        portForwards: [
          const PortForward(
            type: ForwardType.local,
            localPort: 8080,
            remoteHost: 'localhost',
            remotePort: 80,
          ),
          const PortForward(
            type: ForwardType.remote,
            localPort: 5432,
            remoteHost: 'db.internal',
            remotePort: 3306,
          ),
        ],
      );

      final map = conn.toMap();
      final restored = Connection.fromMap(map);

      expect(restored.portForwards.length, 2);
      expect(restored.portForwards[0].type, ForwardType.local);
      expect(restored.portForwards[0].localPort, 8080);
      expect(restored.portForwards[0].remoteHost, 'localhost');
      expect(restored.portForwards[0].remotePort, 80);
      expect(restored.portForwards[1].type, ForwardType.remote);
      expect(restored.portForwards[1].localPort, 5432);
      expect(restored.portForwards[1].remoteHost, 'db.internal');
      expect(restored.portForwards[1].remotePort, 3306);
    });

    test('preserves empty portForwards', () {
      final conn = Connection(
        id: 'pf2',
        label: 'test',
        host: 'h',
        username: 'u',
        portForwards: [],
      );

      final map = conn.toMap();
      final restored = Connection.fromMap(map);

      expect(restored.portForwards, isEmpty);
    });

    test('fromMap handles null agentForwarding as false', () {
      final map = {
        'id': 'x',
        'label': 'test',
        'type': 'direct',
        'host': 'h',
        'port': 22,
        'username': 'u',
        'authMethod': 'key',
        'agentForwarding': null,
        'useMosh': null,
      };
      final conn = Connection.fromMap(map);
      expect(conn.agentForwarding, isFalse);
      expect(conn.useMosh, isFalse);
    });
  });
}
