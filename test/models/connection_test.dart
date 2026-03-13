import 'package:flutter_test/flutter_test.dart';
import 'package:unixshells/models/connection.dart';

void main() {
  group('Connection', () {
    test('toMap and fromMap round-trip', () {
      final conn = Connection(
        id: 'abc',
        label: 'My Server',
        type: ConnectionType.direct,
        host: '192.168.1.1',
        port: 2222,
        username: 'root',
        authMethod: AuthMethod.key,
        keyId: 'key1',
        sortOrder: 3,
      );

      final map = conn.toMap();
      final restored = Connection.fromMap(map);

      expect(restored.id, 'abc');
      expect(restored.label, 'My Server');
      expect(restored.type, ConnectionType.direct);
      expect(restored.host, '192.168.1.1');
      expect(restored.port, 2222);
      expect(restored.username, 'root');
      expect(restored.authMethod, AuthMethod.key);
      expect(restored.keyId, 'key1');
      expect(restored.passwordId, isNull);
      expect(restored.sortOrder, 3);
    });

    test('toMap and fromMap relay connection', () {
      final conn = Connection(
        id: 'r1',
        label: 'Relay Box',
        type: ConnectionType.relay,
        host: '',
        username: 'latch',
        authMethod: AuthMethod.password,
        passwordId: 'pw1',
        relayUsername: 'rasengan',
        relayDevice: 'macbook',
      );

      final map = conn.toMap();
      final restored = Connection.fromMap(map);

      expect(restored.type, ConnectionType.relay);
      expect(restored.authMethod, AuthMethod.password);
      expect(restored.passwordId, 'pw1');
      expect(restored.relayUsername, 'rasengan');
      expect(restored.relayDevice, 'macbook');
    });

    test('fromMap defaults sortOrder to 0', () {
      final map = {
        'id': 'x',
        'label': 'test',
        'type': 'direct',
        'host': 'h',
        'port': 22,
        'username': 'u',
        'authMethod': 'key',
      };
      final conn = Connection.fromMap(map);
      expect(conn.sortOrder, 0);
    });

    test('destination for direct connection', () {
      final conn = Connection(
        id: '1',
        label: 'x',
        host: 'example.com',
        port: 22,
        username: 'u',
      );
      expect(conn.destination, 'example.com');
    });

    test('destination for direct connection with non-default port', () {
      final conn = Connection(
        id: '1',
        label: 'x',
        host: 'example.com',
        port: 2222,
        username: 'u',
      );
      expect(conn.destination, 'example.com:2222');
    });

    test('destination for relay connection', () {
      final conn = Connection(
        id: '1',
        label: 'x',
        type: ConnectionType.relay,
        host: '',
        relayUsername: 'rasengan',
        relayDevice: 'macbook',
      );
      expect(conn.destination, 'macbook.rasengan');
    });

    test('destination for relay with empty device', () {
      final conn = Connection(
        id: '1',
        label: 'x',
        type: ConnectionType.relay,
        host: '',
        relayUsername: 'rasengan',
        relayDevice: '',
      );
      expect(conn.destination, 'rasengan');
    });

    test('copyWith preserves id and lastConnected', () {
      final conn = Connection(
        id: 'orig',
        label: 'Old',
        host: 'old.com',
        lastConnected: 12345,
        sortOrder: 5,
      );

      final copy = conn.copyWith(label: 'New', host: 'new.com');
      expect(copy.id, 'orig');
      expect(copy.label, 'New');
      expect(copy.host, 'new.com');
      expect(copy.lastConnected, 12345);
      expect(copy.sortOrder, 5);
    });

    test('copyWith overrides sortOrder', () {
      final conn = Connection(
        id: '1',
        label: 'x',
        host: 'h',
        sortOrder: 0,
      );
      final copy = conn.copyWith(sortOrder: 10);
      expect(copy.sortOrder, 10);
    });

    test('sessionName null by default', () {
      final conn = Connection(
        id: '1',
        label: 'x',
        host: 'h',
        username: 'u',
      );
      expect(conn.sessionName, isNull);
    });

    test('sessionName round-trips through toMap/fromMap', () {
      final conn = Connection(
        id: 's1',
        label: 'test',
        host: 'h',
        username: 'u',
        sessionName: 'work',
      );

      final map = conn.toMap();
      expect(map['sessionName'], 'work');

      final restored = Connection.fromMap(map);
      expect(restored.sessionName, 'work');
    });

    test('sessionName null round-trips through toMap/fromMap', () {
      final conn = Connection(
        id: 's2',
        label: 'test',
        host: 'h',
        username: 'u',
      );

      final map = conn.toMap();
      expect(map['sessionName'], isNull);

      final restored = Connection.fromMap(map);
      expect(restored.sessionName, isNull);
    });

    test('copyWith preserves sessionName', () {
      final conn = Connection(
        id: '1',
        label: 'x',
        host: 'h',
        sessionName: 'dev',
      );
      final copy = conn.copyWith(label: 'y');
      expect(copy.sessionName, 'dev');
    });

    test('copyWith overrides sessionName', () {
      final conn = Connection(
        id: '1',
        label: 'x',
        host: 'h',
        sessionName: 'dev',
      );
      final copy = conn.copyWith(sessionName: 'prod');
      expect(copy.sessionName, 'prod');
    });

    test('destination unaffected by sessionName', () {
      final conn = Connection(
        id: '1',
        label: 'x',
        host: 'example.com',
        port: 22,
        sessionName: 'work',
      );
      expect(conn.destination, 'example.com');
    });
  });
}
