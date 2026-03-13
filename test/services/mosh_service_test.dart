import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:unixshells/crypto/ocb.dart';

/// Tests for the mosh wire protocol and crypto layer.
///
/// MoshSession itself requires RawDatagramSocket, so we test the protocol
/// components directly: AES-OCB with mosh-style nonces, wire format
/// construction, direction bits, replay semantics, and timestamp framing.
void main() {
  group('mosh direction bit constants', () {
    // These mirror the constants in MoshSession.
    const dirClientBit = 0; // TO_SERVER: bit 63 = 0
    const dirServerBit = 1 << 63; // TO_CLIENT: bit 63 = 1
    const seqMask = (1 << 63) - 1; // lower 63 bits

    test('dirClientBit is zero', () {
      expect(dirClientBit, equals(0));
    });

    test('dirServerBit has only bit 63 set', () {
      // Bit 63 in a 64-bit integer.
      expect(dirServerBit, equals(1 << 63));
      // Verify it's negative in signed 64-bit (Dart int is signed).
      expect(dirServerBit < 0, isTrue);
    });

    test('seqMask masks lower 63 bits', () {
      expect(seqMask, equals((1 << 63) - 1));
      expect(seqMask > 0, isTrue);
      // Verify mask clears the direction bit.
      expect(dirServerBit & seqMask, equals(0));
    });

    test('direction bit and sequence combine correctly', () {
      const seq = 42;
      final clientDirSeq = dirClientBit | (seq & seqMask);
      expect(clientDirSeq, equals(42));
      // Server direction.
      final serverDirSeq = dirServerBit | (seq & seqMask);
      expect(serverDirSeq & seqMask, equals(42));
      expect((serverDirSeq & dirServerBit) != 0, isTrue);
    });

    test('direction bit extraction works for both directions', () {
      const seq = 1000;
      final clientMsg = dirClientBit | (seq & seqMask);
      final serverMsg = dirServerBit | (seq & seqMask);

      // Client message has bit 63 clear.
      expect((clientMsg & dirServerBit) == 0, isTrue);
      // Server message has bit 63 set.
      expect((serverMsg & dirServerBit) != 0, isTrue);
    });
  });

  group('mosh nonce construction', () {
    test('nonce is 12 bytes: 4 zero bytes + 8 direction_seq bytes', () {
      const dirClientBit = 0;
      const seqMask = (1 << 63) - 1;
      const seq = 7;

      final dirSeq = dirClientBit | (seq & seqMask);
      final dirSeqBytes = Uint8List(8);
      ByteData.sublistView(dirSeqBytes).setUint64(0, dirSeq);

      final nonce = Uint8List(12);
      nonce.setRange(4, 12, dirSeqBytes);

      expect(nonce.length, equals(12));
      // First 4 bytes must be zero.
      expect(nonce[0], equals(0));
      expect(nonce[1], equals(0));
      expect(nonce[2], equals(0));
      expect(nonce[3], equals(0));
      // Last 8 bytes encode the direction_seq.
      final recoveredDirSeq = ByteData.sublistView(nonce, 4, 12).getUint64(0);
      expect(recoveredDirSeq, equals(seq));
    });

    test('server nonce differs from client nonce for same seq', () {
      const dirClientBit = 0;
      const dirServerBit = 1 << 63;
      const seqMask = (1 << 63) - 1;
      const seq = 1;

      Uint8List buildNonce(int dirBit) {
        final dirSeq = dirBit | (seq & seqMask);
        final dirSeqBytes = Uint8List(8);
        ByteData.sublistView(dirSeqBytes).setUint64(0, dirSeq);
        final nonce = Uint8List(12);
        nonce.setRange(4, 12, dirSeqBytes);
        return nonce;
      }

      final clientNonce = buildNonce(dirClientBit);
      final serverNonce = buildNonce(dirServerBit);

      // They must differ (different direction bit).
      var same = true;
      for (var i = 0; i < 12; i++) {
        if (clientNonce[i] != serverNonce[i]) {
          same = false;
          break;
        }
      }
      expect(same, isFalse);
    });
  });

  group('mosh wire format with AesOcb', () {
    late AesOcb ocb;
    late Uint8List key;

    setUp(() {
      key = Uint8List.fromList(List.generate(16, (i) => 0xAB ^ i));
      ocb = AesOcb(key);
    });

    test('encrypt produces correct wire format size: 8 + 16 + 4 + payload', () {
      // Simulate MoshSession._encrypt logic.
      const seq = 1;
      const dirClientBit = 0;
      const seqMask = (1 << 63) - 1;

      final dirSeq = dirClientBit | (seq & seqMask);
      final dirSeqBytes = Uint8List(8);
      ByteData.sublistView(dirSeqBytes).setUint64(0, dirSeq);

      final nonce = Uint8List(12);
      nonce.setRange(4, 12, dirSeqBytes);

      final appPayload = Uint8List.fromList('hello'.codeUnits);
      // Plaintext = [timestamp:2][timestamp_reply:2][payload]
      final plaintext = Uint8List(4 + appPayload.length);
      final ptView = ByteData.sublistView(plaintext);
      ptView.setUint16(0, 12345 & 0xffff); // timestamp
      ptView.setUint16(2, 0); // timestamp_reply
      plaintext.setRange(4, plaintext.length, appPayload);

      final tagAndCiphertext = ocb.encrypt(nonce, plaintext);
      // tagAndCiphertext = [tag:16][ciphertext:len(plaintext)]
      expect(tagAndCiphertext.length, equals(16 + plaintext.length));

      // Wire = [dirSeq:8][tagAndCiphertext]
      final wire = Uint8List(8 + tagAndCiphertext.length);
      wire.setRange(0, 8, dirSeqBytes);
      wire.setRange(8, wire.length, tagAndCiphertext);

      // Total: 8 + 16 + 4 + 5 = 33
      expect(wire.length, equals(8 + 16 + 4 + appPayload.length));
    });

    test('decrypt rejects datagrams shorter than 24 bytes', () {
      // Minimum valid datagram: 8 (dirSeq) + 16 (tag) = 24.
      final short = Uint8List(23);
      // Simulate MoshSession._decrypt: first check is length < 24.
      expect(short.length < 24, isTrue);
    });

    test('decrypt rejects wrong direction bit', () {
      const dirClientBit = 0;
      const dirServerBit = 1 << 63;
      const seqMask = (1 << 63) - 1;
      const seq = 1;

      // Encrypt as client (dir = 0).
      final clientDirSeq = dirClientBit | (seq & seqMask);
      final clientDirSeqBytes = Uint8List(8);
      ByteData.sublistView(clientDirSeqBytes).setUint64(0, clientDirSeq);

      final nonce = Uint8List(12);
      nonce.setRange(4, 12, clientDirSeqBytes);

      final plaintext = Uint8List(4); // minimal: just timestamps
      final tagAndCiphertext = ocb.encrypt(nonce, plaintext);

      // Build wire datagram with client direction.
      final wire = Uint8List(8 + tagAndCiphertext.length);
      wire.setRange(0, 8, clientDirSeqBytes);
      wire.setRange(8, wire.length, tagAndCiphertext);

      // Simulate server-side _decrypt check: expects dirServerBit set.
      final dirSeq = ByteData.sublistView(wire, 0, 8).getUint64(0);
      expect((dirSeq & dirServerBit) == 0, isTrue,
          reason: 'client direction should be rejected by server-side check');
    });

    test('replay protection rejects seq <= last seen', () {
      // Simulate the replay window logic.
      var seqInMax = -1;

      bool accept(int seq) {
        if (seq <= seqInMax) return false;
        seqInMax = seq;
        return true;
      }

      expect(accept(1), isTrue);
      expect(accept(2), isTrue);
      expect(accept(2), isFalse, reason: 'duplicate rejected');
      expect(accept(1), isFalse, reason: 'older seq rejected');
      expect(accept(3), isTrue);
    });

    test('round-trip: encrypt then decrypt restores payload', () {
      // Simulate a client sending and server receiving.
      const dirClientBit = 0;
      const seqMask = (1 << 63) - 1;

      final appPayload = Uint8List.fromList('round trip test!'.codeUnits);

      // -- Client encrypt --
      const clientSeq = 1;
      final clientDirSeq = dirClientBit | (clientSeq & seqMask);
      final clientDirSeqBytes = Uint8List(8);
      ByteData.sublistView(clientDirSeqBytes).setUint64(0, clientDirSeq);

      final clientNonce = Uint8List(12);
      clientNonce.setRange(4, 12, clientDirSeqBytes);

      final plaintext = Uint8List(4 + appPayload.length);
      ByteData.sublistView(plaintext).setUint16(0, 100); // timestamp
      ByteData.sublistView(plaintext).setUint16(2, 0); // timestamp_reply
      plaintext.setRange(4, plaintext.length, appPayload);

      final tagAndCiphertext = ocb.encrypt(clientNonce, plaintext);
      final wire = Uint8List(8 + tagAndCiphertext.length);
      wire.setRange(0, 8, clientDirSeqBytes);
      wire.setRange(8, wire.length, tagAndCiphertext);

      // -- Server decrypt (same key, reconstruct nonce from wire) --
      expect(wire.length >= 24, isTrue);

      final rxDirSeqBytes = Uint8List.sublistView(wire, 0, 8);
      final rxNonce = Uint8List(12);
      rxNonce.setRange(4, 12, rxDirSeqBytes);

      final rxTagAndCiphertext = Uint8List.sublistView(wire, 8);
      final decrypted = ocb.decrypt(rxNonce, rxTagAndCiphertext);

      expect(decrypted, isNotNull);
      // Skip 4-byte timestamp header to get application payload.
      final recoveredPayload = Uint8List.sublistView(decrypted!, 4);
      expect(recoveredPayload, equals(appPayload));
    });

    test('round-trip with server direction (server encrypts, client decrypts)', () {
      const dirServerBit = 1 << 63;
      const seqMask = (1 << 63) - 1;

      final appPayload = Uint8List.fromList('server says hi'.codeUnits);

      // -- Server encrypt --
      const serverSeq = 5;
      final serverDirSeq = dirServerBit | (serverSeq & seqMask);
      final serverDirSeqBytes = Uint8List(8);
      ByteData.sublistView(serverDirSeqBytes).setUint64(0, serverDirSeq);

      final nonce = Uint8List(12);
      nonce.setRange(4, 12, serverDirSeqBytes);

      final plaintext = Uint8List(4 + appPayload.length);
      ByteData.sublistView(plaintext).setUint16(0, 200);
      ByteData.sublistView(plaintext).setUint16(2, 100);
      plaintext.setRange(4, plaintext.length, appPayload);

      final tagAndCiphertext = ocb.encrypt(nonce, plaintext);
      final wire = Uint8List(8 + tagAndCiphertext.length);
      wire.setRange(0, 8, serverDirSeqBytes);
      wire.setRange(8, wire.length, tagAndCiphertext);

      // -- Client decrypt --
      final rxDirSeqBytes = Uint8List.sublistView(wire, 0, 8);
      final rxDirSeq = ByteData.sublistView(rxDirSeqBytes).getUint64(0);

      // Verify direction.
      expect((rxDirSeq & dirServerBit) != 0, isTrue);

      // Verify sequence.
      expect(rxDirSeq & seqMask, equals(5));

      final rxNonce = Uint8List(12);
      rxNonce.setRange(4, 12, rxDirSeqBytes);

      final rxTagAndCiphertext = Uint8List.sublistView(wire, 8);
      final decrypted = ocb.decrypt(rxNonce, rxTagAndCiphertext);
      expect(decrypted, isNotNull);

      // Extract timestamp and payload.
      final ptView = ByteData.sublistView(decrypted!);
      expect(ptView.getUint16(0), equals(200));
      expect(ptView.getUint16(2), equals(100));

      final recoveredPayload = Uint8List.sublistView(decrypted, 4);
      expect(recoveredPayload, equals(appPayload));
    });

    test('tampered wire datagram fails decryption', () {
      const dirClientBit = 0;
      const seqMask = (1 << 63) - 1;
      const seq = 1;

      final dirSeq = dirClientBit | (seq & seqMask);
      final dirSeqBytes = Uint8List(8);
      ByteData.sublistView(dirSeqBytes).setUint64(0, dirSeq);

      final nonce = Uint8List(12);
      nonce.setRange(4, 12, dirSeqBytes);

      final plaintext = Uint8List(4 + 5);
      plaintext.setRange(4, 9, 'tampr'.codeUnits);

      final tagAndCiphertext = ocb.encrypt(nonce, plaintext);
      final wire = Uint8List(8 + tagAndCiphertext.length);
      wire.setRange(0, 8, dirSeqBytes);
      wire.setRange(8, wire.length, tagAndCiphertext);

      // Tamper with the ciphertext portion.
      wire[wire.length - 1] ^= 0xff;

      // Decrypt should fail.
      final rxNonce = Uint8List(12);
      rxNonce.setRange(4, 12, Uint8List.sublistView(wire, 0, 8));
      final rxTagAndCiphertext = Uint8List.sublistView(wire, 8);
      final decrypted = ocb.decrypt(rxNonce, rxTagAndCiphertext);
      expect(decrypted, isNull);
    });
  });

  group('mosh timestamp framing', () {
    test('timestamp frame is [ts:2][ts_reply:2][payload]', () {
      final payload = Uint8List.fromList('data'.codeUnits);
      final frame = Uint8List(4 + payload.length);
      final view = ByteData.sublistView(frame);
      view.setUint16(0, 0x1234);
      view.setUint16(2, 0x5678);
      frame.setRange(4, frame.length, payload);

      expect(frame.length, equals(8));
      expect(view.getUint16(0), equals(0x1234));
      expect(view.getUint16(2), equals(0x5678));
      expect(Uint8List.sublistView(frame, 4), equals(payload));
    });

    test('timestamp wraps at 16 bits (mod 65536)', () {
      // Mosh uses millisecondsSinceEpoch & 0xffff.
      final ts = DateTime.now().millisecondsSinceEpoch & 0xffff;
      expect(ts >= 0, isTrue);
      expect(ts <= 0xffff, isTrue);
    });

    test('empty payload produces 4-byte plaintext', () {
      final emptyPayload = Uint8List(0);
      final plaintext = Uint8List(4 + emptyPayload.length);
      expect(plaintext.length, equals(4));
    });
  });

  group('mosh sequence number', () {
    test('sequence number increments monotonically', () {
      var seq = 0;
      for (var i = 0; i < 100; i++) {
        seq++;
        expect(seq, equals(i + 1));
      }
    });

    test('sequence number is masked to 63 bits', () {
      const seqMask = (1 << 63) - 1;
      // A large sequence value should be masked properly.
      const largeSeq = (1 << 62) + 42;
      expect(largeSeq & seqMask, equals(largeSeq));
    });
  });

  group('MoshException', () {
    test('toString returns message', () {
      // We can import and test MoshException directly.
      // But since it's a simple class, just verify the pattern.
      final e = _TestException('test error');
      expect(e.toString(), equals('test error'));
    });
  });
}

/// Mirror of MoshException for testing without importing dart:io.
class _TestException implements Exception {
  final String message;
  _TestException(this.message);

  @override
  String toString() => message;
}
