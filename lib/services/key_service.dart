import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart' as ssh;
import 'package:pinenacl/ed25519.dart' as ed25519;
import 'package:uuid/uuid.dart';

import '../models/ssh_key.dart';
import 'storage_service.dart';

class KeyService {
  final StorageService _storage;

  KeyService(this._storage);

  /// Generate a new ed25519 key pair and store it.
  Future<SSHKeyPair> generate(String label) async {
    final signingKey = ed25519.SigningKey.generate();
    final publicBytes = Uint8List.fromList(signingKey.verifyKey.asTypedList);
    final privateBytes = Uint8List.fromList(signingKey.asTypedList);

    final keyPair = ssh.OpenSSHEd25519KeyPair(publicBytes, privateBytes, label);
    final id = const Uuid().v4();
    final pubStr =
        'ssh-ed25519 ${base64Encode(keyPair.toPublicKey().encode())} $label';

    final model = SSHKeyPair(
      id: id,
      label: label,
      publicKeyOpenSSH: pubStr,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    await _storage.saveKeyPair(model, keyPair.toPem());
    return model;
  }

  /// Import a private key from PEM/OpenSSH format.
  Future<SSHKeyPair> importKey(String label, String privateKeyData) async {
    final identities = ssh.SSHKeyPair.fromPem(privateKeyData);
    if (identities.isEmpty) throw Exception('No keys found in PEM data');

    final kp = identities.first;
    final pubStr =
        '${kp.name} ${base64Encode(kp.toPublicKey().encode())} $label';
    final id = const Uuid().v4();

    final model = SSHKeyPair(
      id: id,
      label: label,
      publicKeyOpenSSH: pubStr,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    await _storage.saveKeyPair(model, privateKeyData);
    return model;
  }

  Future<List<SSHKeyPair>> list() => _storage.listKeys();

  Future<void> delete(String id) => _storage.deleteKey(id);

  /// Load dartssh2 identities from a stored key.
  Future<List<ssh.SSHKeyPair>> loadIdentity(String keyId) async {
    final pem = await _storage.getPrivateKey(keyId);
    if (pem == null) return [];
    return ssh.SSHKeyPair.fromPem(pem);
  }
}
