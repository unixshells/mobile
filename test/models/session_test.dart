import 'package:flutter_test/flutter_test.dart';
import 'package:unixshells/models/connection.dart';
import 'package:unixshells/models/session.dart';

void main() {
  Connection makeConnection() => Connection(
        id: 'conn1',
        label: 'Test Server',
        host: 'example.com',
        username: 'user',
      );

  group('ActiveSession', () {
    test('isMosh returns false when moshSession is null', () {
      final session = ActiveSession(
        id: 's1',
        connection: makeConnection(),
        label: 'test',
      );
      expect(session.isMosh, isFalse);
    });

    test('createdAt defaults to approximately now', () {
      final before = DateTime.now();
      final session = ActiveSession(
        id: 's1',
        connection: makeConnection(),
        label: 'test',
      );
      final after = DateTime.now();

      expect(session.createdAt.isAfter(before.subtract(const Duration(seconds: 1))), isTrue);
      expect(session.createdAt.isBefore(after.add(const Duration(seconds: 1))), isTrue);
    });

    test('createdAt uses provided value when given', () {
      final ts = DateTime(2025, 6, 15, 12, 0, 0);
      final session = ActiveSession(
        id: 's1',
        connection: makeConnection(),
        label: 'test',
        createdAt: ts,
      );
      expect(session.createdAt, ts);
    });

    test('activeForwards defaults to empty list', () {
      final session = ActiveSession(
        id: 's1',
        connection: makeConnection(),
        label: 'test',
      );
      expect(session.activeForwards, isEmpty);
    });

    test('close does not throw with all-null optional fields', () {
      final session = ActiveSession(
        id: 's1',
        connection: makeConnection(),
        label: 'test',
      );
      expect(() => session.close(), returnsNormally);
    });

    test('close does not throw with empty activeForwards', () {
      final session = ActiveSession(
        id: 's1',
        connection: makeConnection(),
        label: 'test',
        activeForwards: [],
      );
      expect(() => session.close(), returnsNormally);
    });
  });

  group('ActiveForward', () {
    test('close does not throw with null server', () {
      final fwd = ActiveForward(description: 'L8080:localhost:80');
      expect(() => fwd.close(), returnsNormally);
    });

    test('stores description correctly', () {
      final fwd = ActiveForward(description: 'R3306:db:3306');
      expect(fwd.description, 'R3306:db:3306');
    });

    test('server is null by default', () {
      final fwd = ActiveForward(description: 'test');
      expect(fwd.server, isNull);
    });
  });
}
