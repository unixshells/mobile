import 'package:flutter_test/flutter_test.dart';
import 'package:unixshells/models/account.dart';

void main() {
  group('UnixShellsAccount', () {
    test('toJson and fromJson round-trip', () {
      final account = UnixShellsAccount(
        username: 'rasengan',
        email: 'test@example.com',
        subscriptionStatus: 'active',
      );

      final json = account.toJson();
      final restored = UnixShellsAccount.fromJson(json);

      expect(restored.username, 'rasengan');
      expect(restored.email, 'test@example.com');
      expect(restored.subscriptionStatus, 'active');
    });

    test('fromJson defaults subscriptionStatus', () {
      final json = {'username': 'u', 'email': 'e@e.com'};
      final account = UnixShellsAccount.fromJson(json);
      expect(account.subscriptionStatus, '');
    });

    test('isActive true for active subscription', () {
      final account = UnixShellsAccount(
        username: 'u',
        email: 'e',
        subscriptionStatus: 'active',
      );
      expect(account.isActive, isTrue);
    });

    test('isActive false for empty subscription', () {
      final account = UnixShellsAccount(
        username: 'u',
        email: 'e',
      );
      expect(account.isActive, isFalse);
    });

    test('isActive false for other status', () {
      final account = UnixShellsAccount(
        username: 'u',
        email: 'e',
        subscriptionStatus: 'expired',
      );
      expect(account.isActive, isFalse);
    });
  });
}
