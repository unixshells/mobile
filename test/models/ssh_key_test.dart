import 'package:flutter_test/flutter_test.dart';
import 'package:unixshells/models/ssh_key.dart';

void main() {
  group('SSHKeyPair', () {
    test('toMap and fromMap round-trip', () {
      final key = SSHKeyPair(
        id: 'k1',
        label: 'test-key',
        publicKeyOpenSSH: 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA test-key',
        algorithm: 'ed25519',
        createdAt: 1700000000,
      );

      final map = key.toMap();
      final restored = SSHKeyPair.fromMap(map);

      expect(restored.id, 'k1');
      expect(restored.label, 'test-key');
      expect(restored.publicKeyOpenSSH,
          'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA test-key');
      expect(restored.algorithm, 'ed25519');
      expect(restored.createdAt, 1700000000);
    });

    test('fromMap defaults algorithm to ed25519', () {
      final map = {
        'id': 'k1',
        'label': 'l',
        'publicKeyOpenSSH': 'ssh-ed25519 AAAA l',
        'createdAt': 0,
      };
      final key = SSHKeyPair.fromMap(map);
      expect(key.algorithm, 'ed25519');
    });

    test('fingerprint extracts from public key', () {
      final key = SSHKeyPair(
        id: 'k1',
        label: 'l',
        publicKeyOpenSSH: 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAATEST l',
        createdAt: 0,
      );
      expect(key.fingerprint, startsWith('SHA256:'));
      expect(key.fingerprint, contains('...'));
    });

    test('fingerprint handles short key', () {
      final key = SSHKeyPair(
        id: 'k1',
        label: 'l',
        publicKeyOpenSSH: 'short',
        createdAt: 0,
      );
      // Should not throw.
      expect(key.fingerprint, isNotEmpty);
    });
  });
}
