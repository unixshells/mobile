import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:unixshells/crypto/ocb.dart';

void main() {
  group('AesOcb', () {
    late AesOcb ocb;
    late Uint8List key;

    setUp(() {
      // 16-byte test key.
      key = Uint8List.fromList(
          List.generate(16, (i) => i));
      ocb = AesOcb(key);
    });

    test('encrypt then decrypt returns original plaintext', () {
      final nonce = Uint8List.fromList(List.generate(12, (i) => i + 1));
      final plaintext = Uint8List.fromList('Hello, mosh!'.codeUnits);

      final encrypted = ocb.encrypt(nonce, plaintext);
      // encrypted = [tag:16][ciphertext]
      expect(encrypted.length, equals(16 + plaintext.length));

      final decrypted = ocb.decrypt(nonce, encrypted);
      expect(decrypted, isNotNull);
      expect(decrypted, equals(plaintext));
    });

    test('decrypt with wrong nonce fails', () {
      final nonce1 = Uint8List.fromList(List.generate(12, (i) => i + 1));
      final nonce2 = Uint8List.fromList(List.generate(12, (i) => i + 2));
      final plaintext = Uint8List.fromList('test data'.codeUnits);

      final encrypted = ocb.encrypt(nonce1, plaintext);
      final decrypted = ocb.decrypt(nonce2, encrypted);
      expect(decrypted, isNull);
    });

    test('decrypt with tampered ciphertext fails', () {
      final nonce = Uint8List.fromList(List.generate(12, (i) => i));
      final plaintext = Uint8List.fromList('sensitive'.codeUnits);

      final encrypted = ocb.encrypt(nonce, plaintext);
      // Flip a bit in the ciphertext.
      encrypted[20] ^= 0x01;
      final decrypted = ocb.decrypt(nonce, encrypted);
      expect(decrypted, isNull);
    });

    test('decrypt with tampered tag fails', () {
      final nonce = Uint8List.fromList(List.generate(12, (i) => i));
      final plaintext = Uint8List.fromList('auth check'.codeUnits);

      final encrypted = ocb.encrypt(nonce, plaintext);
      // Flip a bit in the tag.
      encrypted[0] ^= 0x01;
      final decrypted = ocb.decrypt(nonce, encrypted);
      expect(decrypted, isNull);
    });

    test('decrypt with wrong key fails', () {
      final nonce = Uint8List.fromList(List.generate(12, (i) => i));
      final plaintext = Uint8List.fromList('wrong key'.codeUnits);

      final encrypted = ocb.encrypt(nonce, plaintext);

      final wrongKey = Uint8List.fromList(List.generate(16, (i) => i + 100));
      final otherOcb = AesOcb(wrongKey);
      final decrypted = otherOcb.decrypt(nonce, encrypted);
      expect(decrypted, isNull);
    });

    test('empty plaintext encrypts and decrypts', () {
      final nonce = Uint8List.fromList(List.generate(12, (i) => i));
      final plaintext = Uint8List(0);

      final encrypted = ocb.encrypt(nonce, plaintext);
      expect(encrypted.length, equals(16)); // tag only

      final decrypted = ocb.decrypt(nonce, encrypted);
      expect(decrypted, isNotNull);
      expect(decrypted!.length, equals(0));
    });

    test('block-aligned plaintext encrypts and decrypts', () {
      final nonce = Uint8List.fromList(List.generate(12, (i) => i));
      // Exactly 32 bytes = 2 full blocks.
      final plaintext = Uint8List.fromList(List.generate(32, (i) => i));

      final encrypted = ocb.encrypt(nonce, plaintext);
      expect(encrypted.length, equals(16 + 32));

      final decrypted = ocb.decrypt(nonce, encrypted);
      expect(decrypted, equals(plaintext));
    });

    test('large plaintext encrypts and decrypts', () {
      final nonce = Uint8List.fromList(List.generate(12, (i) => i));
      final plaintext = Uint8List.fromList(List.generate(1000, (i) => i & 0xff));

      final encrypted = ocb.encrypt(nonce, plaintext);
      final decrypted = ocb.decrypt(nonce, encrypted);
      expect(decrypted, equals(plaintext));
    });

    test('different nonces produce different ciphertexts', () {
      final nonce1 = Uint8List.fromList(List.generate(12, (i) => 0));
      final nonce2 = Uint8List.fromList(List.generate(12, (i) => 1));
      final plaintext = Uint8List.fromList('same data'.codeUnits);

      final enc1 = ocb.encrypt(nonce1, plaintext);
      final enc2 = ocb.encrypt(nonce2, plaintext);

      // Ciphertexts (after tag) should differ.
      var same = true;
      for (var i = 16; i < enc1.length; i++) {
        if (enc1[i] != enc2[i]) {
          same = false;
          break;
        }
      }
      expect(same, isFalse);
    });
  });
}
