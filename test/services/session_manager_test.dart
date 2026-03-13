import 'package:flutter_test/flutter_test.dart';
import 'package:unixshells/models/connection.dart';
import 'package:unixshells/services/relay_api_service.dart';
import 'package:unixshells/services/session_manager.dart';
import 'package:unixshells/services/ssh_service.dart';

void main() {
  group('SessionManager', () {
    test('starts empty with index -1', () {
      final m = SessionManager(_FakeSSHService(), _FakeRelayApi());
      expect(m.sessions, isEmpty);
      expect(m.activeIndex, -1);
      expect(m.activeSession, isNull);
    });

    test('switchTo ignores invalid indices when empty', () {
      final m = SessionManager(_FakeSSHService(), _FakeRelayApi());
      m.switchTo(0);
      expect(m.activeIndex, -1);
      m.switchTo(-1);
      expect(m.activeIndex, -1);
    });

    test('disconnect nonexistent id is no-op', () {
      final m = SessionManager(_FakeSSHService(), _FakeRelayApi());
      m.disconnect('nope');
      expect(m.sessions, isEmpty);
      expect(m.activeIndex, -1);
    });

    test('disconnectAll on empty is safe', () {
      final m = SessionManager(_FakeSSHService(), _FakeRelayApi());
      m.disconnectAll();
      expect(m.sessions, isEmpty);
      expect(m.activeIndex, -1);
    });

    test('sessions list is unmodifiable', () {
      final m = SessionManager(_FakeSSHService(), _FakeRelayApi());
      expect(() => (m.sessions as List).add(null), throwsA(anything));
    });

    test('notifies listeners on switchTo', () {
      final m = SessionManager(_FakeSSHService(), _FakeRelayApi());
      // switchTo with invalid index should not notify.
      var count = 0;
      m.addListener(() => count++);
      m.switchTo(0);
      expect(count, 0);
    });
  });

  group('Connection model (used by SessionManager)', () {
    test('connection preserves fields', () {
      final conn = Connection(
        id: '1',
        label: 'Test',
        host: 'localhost',
        port: 2222,
        username: 'user',
      );
      expect(conn.label, 'Test');
      expect(conn.id, '1');
      expect(conn.port, 2222);
      expect(conn.username, 'user');
      expect(conn.sessionName, isNull);
    });

    test('relay connection fields', () {
      final conn = Connection(
        id: '2',
        label: 'Relay',
        type: ConnectionType.relay,
        host: '',
        relayUsername: 'rasengan',
        relayDevice: 'macbook',
      );
      expect(conn.type, ConnectionType.relay);
      expect(conn.relayUsername, 'rasengan');
      expect(conn.relayDevice, 'macbook');
    });

    test('connection with sessionName', () {
      final conn = Connection(
        id: '3',
        label: 'Latch',
        host: 'latch.local',
        sessionName: 'work',
      );
      expect(conn.sessionName, 'work');
    });
  });
}

class _FakeSSHService extends Fake implements SSHService {}

class _FakeRelayApi extends Fake implements RelayApiService {}
