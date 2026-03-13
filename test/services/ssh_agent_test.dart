import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

// Re-implement the private helpers from SSHAgentHandler so we can test them.
// These mirror the exact logic in lib/services/ssh_agent.dart.

void writeUint32(BytesBuilder out, int value) {
  final bytes = Uint8List(4);
  ByteData.sublistView(bytes).setUint32(0, value);
  out.add(bytes);
}

void writeBytes(BytesBuilder out, Uint8List data) {
  writeUint32(out, data.length);
  out.add(data);
}

void writeString(BytesBuilder out, String s) {
  final bytes = Uint8List.fromList(s.codeUnits);
  writeBytes(out, bytes);
}

int readUint32(Uint8List data, int offset) {
  return ByteData.sublistView(data).getUint32(offset);
}

bool bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Build a framed agent message: [length:4][data].
Uint8List frameMessage(Uint8List data) {
  final msg = Uint8List(4 + data.length);
  ByteData.sublistView(msg).setUint32(0, data.length);
  msg.setRange(4, 4 + data.length, data);
  return msg;
}

/// Build a simple agent message with only a type byte and no payload.
Uint8List buildTypeOnlyMessage(int type) {
  return frameMessage(Uint8List.fromList([type]));
}

// Protocol constants (must match ssh_agent.dart).
const agentcRequestIdentities = 11;
const agentIdentitiesAnswer = 12;
const agentcSignRequest = 13;
const agentSignResponse = 14;
const agentFailure = 5;

void main() {
  group('SSH Agent Protocol Constants', () {
    test('constants match SSH agent protocol spec', () {
      // RFC draft-miller-ssh-agent, section 5.1
      expect(agentFailure, equals(5));
      expect(agentcRequestIdentities, equals(11));
      expect(agentIdentitiesAnswer, equals(12));
      expect(agentcSignRequest, equals(13));
      expect(agentSignResponse, equals(14));
    });
  });

  group('bytesEqual', () {
    test('returns true for identical byte arrays', () {
      final a = Uint8List.fromList([1, 2, 3, 4, 5]);
      final b = Uint8List.fromList([1, 2, 3, 4, 5]);
      expect(bytesEqual(a, b), isTrue);
    });

    test('returns true for empty byte arrays', () {
      final a = Uint8List(0);
      final b = Uint8List(0);
      expect(bytesEqual(a, b), isTrue);
    });

    test('returns false for different lengths', () {
      final a = Uint8List.fromList([1, 2, 3]);
      final b = Uint8List.fromList([1, 2, 3, 4]);
      expect(bytesEqual(a, b), isFalse);
    });

    test('returns false for same length but different content', () {
      final a = Uint8List.fromList([1, 2, 3]);
      final b = Uint8List.fromList([1, 2, 4]);
      expect(bytesEqual(a, b), isFalse);
    });

    test('returns false when only first byte differs', () {
      final a = Uint8List.fromList([0, 2, 3]);
      final b = Uint8List.fromList([1, 2, 3]);
      expect(bytesEqual(a, b), isFalse);
    });

    test('returns false when only last byte differs', () {
      final a = Uint8List.fromList([1, 2, 3]);
      final b = Uint8List.fromList([1, 2, 0]);
      expect(bytesEqual(a, b), isFalse);
    });

    test('handles single-byte arrays', () {
      expect(bytesEqual(Uint8List.fromList([42]), Uint8List.fromList([42])), isTrue);
      expect(bytesEqual(Uint8List.fromList([42]), Uint8List.fromList([43])), isFalse);
    });
  });

  group('writeUint32 / readUint32', () {
    test('round-trips zero', () {
      final out = BytesBuilder();
      writeUint32(out, 0);
      final bytes = Uint8List.fromList(out.takeBytes());
      expect(bytes.length, equals(4));
      expect(readUint32(bytes, 0), equals(0));
    });

    test('round-trips small value', () {
      final out = BytesBuilder();
      writeUint32(out, 42);
      final bytes = Uint8List.fromList(out.takeBytes());
      expect(readUint32(bytes, 0), equals(42));
    });

    test('round-trips large value', () {
      final out = BytesBuilder();
      writeUint32(out, 0xDEADBEEF);
      final bytes = Uint8List.fromList(out.takeBytes());
      expect(readUint32(bytes, 0), equals(0xDEADBEEF));
    });

    test('round-trips max uint32', () {
      final out = BytesBuilder();
      writeUint32(out, 0xFFFFFFFF);
      final bytes = Uint8List.fromList(out.takeBytes());
      expect(readUint32(bytes, 0), equals(0xFFFFFFFF));
    });

    test('writes big-endian', () {
      final out = BytesBuilder();
      writeUint32(out, 0x01020304);
      final bytes = out.takeBytes();
      expect(bytes[0], equals(0x01));
      expect(bytes[1], equals(0x02));
      expect(bytes[2], equals(0x03));
      expect(bytes[3], equals(0x04));
    });

    test('readUint32 at non-zero offset', () {
      // [padding:4][value:4]
      final data = Uint8List(8);
      ByteData.sublistView(data).setUint32(4, 12345);
      expect(readUint32(data, 4), equals(12345));
    });

    test('multiple sequential writes and reads', () {
      final out = BytesBuilder();
      writeUint32(out, 100);
      writeUint32(out, 200);
      writeUint32(out, 300);
      final bytes = Uint8List.fromList(out.takeBytes());
      expect(bytes.length, equals(12));
      expect(readUint32(bytes, 0), equals(100));
      expect(readUint32(bytes, 4), equals(200));
      expect(readUint32(bytes, 8), equals(300));
    });
  });

  group('writeBytes', () {
    test('writes length-prefixed data', () {
      final out = BytesBuilder();
      final data = Uint8List.fromList([0xCA, 0xFE, 0xBA, 0xBE]);
      writeBytes(out, data);
      final result = Uint8List.fromList(out.takeBytes());

      // First 4 bytes = length.
      expect(readUint32(result, 0), equals(4));
      // Next 4 bytes = data.
      expect(result[4], equals(0xCA));
      expect(result[5], equals(0xFE));
      expect(result[6], equals(0xBA));
      expect(result[7], equals(0xBE));
      expect(result.length, equals(8));
    });

    test('writes empty data with zero length', () {
      final out = BytesBuilder();
      writeBytes(out, Uint8List(0));
      final result = Uint8List.fromList(out.takeBytes());
      expect(result.length, equals(4));
      expect(readUint32(result, 0), equals(0));
    });
  });

  group('writeString', () {
    test('writes ASCII string as length-prefixed bytes', () {
      final out = BytesBuilder();
      writeString(out, 'ssh-ed25519');
      final result = Uint8List.fromList(out.takeBytes());

      final len = readUint32(result, 0);
      expect(len, equals(11)); // 'ssh-ed25519'.length
      final str = String.fromCharCodes(result.sublist(4, 4 + len));
      expect(str, equals('ssh-ed25519'));
    });

    test('writes empty string', () {
      final out = BytesBuilder();
      writeString(out, '');
      final result = Uint8List.fromList(out.takeBytes());
      expect(result.length, equals(4));
      expect(readUint32(result, 0), equals(0));
    });
  });

  group('Message Framing', () {
    test('frameMessage wraps data with 4-byte length prefix', () {
      final data = Uint8List.fromList([agentcRequestIdentities]);
      final framed = frameMessage(data);

      expect(framed.length, equals(5));
      // Length field = 1.
      expect(ByteData.sublistView(framed).getUint32(0), equals(1));
      // Type byte.
      expect(framed[4], equals(agentcRequestIdentities));
    });

    test('frameMessage with payload', () {
      final data = Uint8List.fromList([agentcSignRequest, 0xDE, 0xAD]);
      final framed = frameMessage(data);

      expect(framed.length, equals(7));
      expect(ByteData.sublistView(framed).getUint32(0), equals(3));
      expect(framed[4], equals(agentcSignRequest));
      expect(framed[5], equals(0xDE));
      expect(framed[6], equals(0xAD));
    });

    test('frameMessage with empty data', () {
      final framed = frameMessage(Uint8List(0));
      expect(framed.length, equals(4));
      expect(ByteData.sublistView(framed).getUint32(0), equals(0));
    });

    test('REQUEST_IDENTITIES message is exactly 5 bytes', () {
      final msg = buildTypeOnlyMessage(agentcRequestIdentities);
      expect(msg.length, equals(5));

      final len = ByteData.sublistView(msg).getUint32(0);
      expect(len, equals(1));
      expect(msg[4], equals(agentcRequestIdentities));
    });

    test('type byte is correctly extracted from framed message', () {
      for (final type in [agentcRequestIdentities, agentcSignRequest, agentFailure]) {
        final msg = buildTypeOnlyMessage(type);
        expect(msg[4], equals(type));
      }
    });
  });

  group('_processBuffer logic (simulated)', () {
    // Simulate the buffer processing logic from SSHAgentHandler._processBuffer
    // without needing a real SSHChannel. We track which messages get parsed.

    /// Parse framed messages from a buffer, returning a list of (type, payload)
    /// pairs. Leftover bytes are left in the buffer.
    List<(int, Uint8List?)> parseMessages(BytesBuilder buffer) {
      final results = <(int, Uint8List?)>[];
      while (true) {
        final bytes = buffer.takeBytes();
        if (bytes.length < 5) {
          buffer.add(bytes);
          return results;
        }
        final view = ByteData.sublistView(bytes);
        final msgLen = view.getUint32(0);
        if (bytes.length < 4 + msgLen) {
          buffer.add(bytes);
          return results;
        }
        final type = bytes[4];
        final payload =
            msgLen > 1 ? Uint8List.sublistView(bytes, 5, 4 + msgLen) : null;
        results.add((type, payload));
        if (bytes.length > 4 + msgLen) {
          buffer.add(Uint8List.sublistView(bytes, 4 + msgLen));
        }
      }
    }

    test('handles a complete single message', () {
      final buffer = BytesBuilder(copy: false);
      buffer.add(buildTypeOnlyMessage(agentcRequestIdentities));

      final msgs = parseMessages(buffer);
      expect(msgs.length, equals(1));
      expect(msgs[0].$1, equals(agentcRequestIdentities));
      expect(msgs[0].$2, isNull); // no payload for type-only message
      // Buffer should be empty.
      expect(buffer.takeBytes().length, equals(0));
    });

    test('buffers incomplete message (less than 5 bytes)', () {
      final buffer = BytesBuilder(copy: false);
      // Only 3 bytes -- not enough for length + type.
      buffer.add(Uint8List.fromList([0, 0, 0]));

      final msgs = parseMessages(buffer);
      expect(msgs, isEmpty);
      // Bytes should remain in buffer.
      expect(buffer.takeBytes().length, equals(3));
    });

    test('buffers incomplete message (has header but not full payload)', () {
      final buffer = BytesBuilder(copy: false);
      // Header says length=10, but we only provide 5 bytes total.
      final incomplete = Uint8List(5);
      ByteData.sublistView(incomplete).setUint32(0, 10); // need 14 bytes total
      incomplete[4] = agentcSignRequest;
      buffer.add(incomplete);

      final msgs = parseMessages(buffer);
      expect(msgs, isEmpty);
      expect(buffer.takeBytes().length, equals(5));
    });

    test('handles multiple messages in one chunk', () {
      final buffer = BytesBuilder(copy: false);
      // Two REQUEST_IDENTITIES messages back-to-back.
      buffer.add(buildTypeOnlyMessage(agentcRequestIdentities));
      buffer.add(buildTypeOnlyMessage(agentcRequestIdentities));

      final msgs = parseMessages(buffer);
      expect(msgs.length, equals(2));
      expect(msgs[0].$1, equals(agentcRequestIdentities));
      expect(msgs[1].$1, equals(agentcRequestIdentities));
      expect(buffer.takeBytes().length, equals(0));
    });

    test('handles multiple messages followed by incomplete data', () {
      final buffer = BytesBuilder(copy: false);
      buffer.add(buildTypeOnlyMessage(agentcRequestIdentities));
      buffer.add(buildTypeOnlyMessage(agentFailure));
      // Incomplete trailing data (only 2 bytes).
      buffer.add(Uint8List.fromList([0, 0]));

      final msgs = parseMessages(buffer);
      expect(msgs.length, equals(2));
      // Leftover bytes.
      expect(buffer.takeBytes().length, equals(2));
    });

    test('message with payload extracts payload correctly', () {
      final buffer = BytesBuilder(copy: false);
      // Build a message with type + 4 bytes of payload.
      final payload = Uint8List.fromList([0x01, 0x02, 0x03, 0x04]);
      final data = Uint8List(1 + payload.length);
      data[0] = agentcSignRequest;
      data.setRange(1, 1 + payload.length, payload);
      buffer.add(frameMessage(data));

      final msgs = parseMessages(buffer);
      expect(msgs.length, equals(1));
      expect(msgs[0].$1, equals(agentcSignRequest));
      expect(msgs[0].$2, isNotNull);
      expect(msgs[0].$2!.length, equals(4));
      expect(bytesEqual(msgs[0].$2!, payload), isTrue);
    });

    test('unknown message type is still parsed', () {
      final buffer = BytesBuilder(copy: false);
      buffer.add(buildTypeOnlyMessage(99)); // unknown type

      final msgs = parseMessages(buffer);
      expect(msgs.length, equals(1));
      expect(msgs[0].$1, equals(99));
      // In real handler, this triggers _sendFailure.
    });

    test('incremental feeding of bytes works', () {
      final buffer = BytesBuilder(copy: false);
      final fullMsg = buildTypeOnlyMessage(agentcRequestIdentities);

      // Feed one byte at a time.
      for (var i = 0; i < fullMsg.length - 1; i++) {
        buffer.add(Uint8List.fromList([fullMsg[i]]));
        final msgs = parseMessages(buffer);
        expect(msgs, isEmpty, reason: 'should not parse with only ${i + 1} bytes');
      }

      // Feed final byte.
      buffer.add(Uint8List.fromList([fullMsg[fullMsg.length - 1]]));
      final msgs = parseMessages(buffer);
      expect(msgs.length, equals(1));
      expect(msgs[0].$1, equals(agentcRequestIdentities));
    });
  });

  group('_handleMessage dispatch (simulated)', () {
    // Simulate the dispatch logic from _handleMessage.
    String simulateDispatch(int type, Uint8List? payload) {
      switch (type) {
        case agentcRequestIdentities:
          return 'identities';
        case agentcSignRequest:
          if (payload != null) return 'sign';
          return 'failure';
        default:
          return 'failure';
      }
    }

    test('REQUEST_IDENTITIES dispatches to identities handler', () {
      expect(simulateDispatch(agentcRequestIdentities, null), equals('identities'));
    });

    test('SIGN_REQUEST with payload dispatches to sign handler', () {
      expect(simulateDispatch(agentcSignRequest, Uint8List.fromList([1, 2, 3])), equals('sign'));
    });

    test('SIGN_REQUEST without payload returns failure', () {
      expect(simulateDispatch(agentcSignRequest, null), equals('failure'));
    });

    test('unknown type returns failure', () {
      expect(simulateDispatch(99, null), equals('failure'));
      expect(simulateDispatch(0, null), equals('failure'));
      expect(simulateDispatch(255, null), equals('failure'));
    });
  });

  group('IDENTITIES_ANSWER format (empty list)', () {
    test('empty identities answer has correct structure', () {
      // Simulate _handleRequestIdentities with zero identities.
      final out = BytesBuilder();
      out.addByte(agentIdentitiesAnswer);
      writeUint32(out, 0); // zero identities
      final body = Uint8List.fromList(out.takeBytes());
      final framed = frameMessage(body);

      // Total: 4 (length) + 1 (type) + 4 (count) = 9 bytes.
      expect(framed.length, equals(9));

      // Length field = 5 (type + count).
      final msgLen = ByteData.sublistView(framed).getUint32(0);
      expect(msgLen, equals(5));

      // Type byte.
      expect(framed[4], equals(agentIdentitiesAnswer));

      // Identity count = 0.
      expect(readUint32(Uint8List.fromList(framed.sublist(5)), 0), equals(0));
    });
  });

  group('FAILURE message format', () {
    test('failure message has correct structure', () {
      final body = Uint8List.fromList([agentFailure]);
      final framed = frameMessage(body);

      expect(framed.length, equals(5));
      expect(ByteData.sublistView(framed).getUint32(0), equals(1));
      expect(framed[4], equals(agentFailure));
    });
  });

  group('SIGN_REQUEST payload parsing (simulated)', () {
    test('correctly parses key blob and data from sign request payload', () {
      // Build a sign request payload: [key_blob_len:4][key_blob][data_len:4][data][flags:4]
      final keyBlob = Uint8List.fromList([0xAA, 0xBB, 0xCC]);
      final dataToSign = Uint8List.fromList([0x01, 0x02, 0x03, 0x04, 0x05]);
      final flags = 0;

      final out = BytesBuilder();
      writeBytes(out, keyBlob);
      writeBytes(out, dataToSign);
      writeUint32(out, flags);
      final payload = Uint8List.fromList(out.takeBytes());

      // Parse it the same way _handleSignRequest does.
      var offset = 0;
      final keyBlobLen = readUint32(payload, offset);
      offset += 4;
      expect(keyBlobLen, equals(3));

      final parsedKeyBlob = Uint8List.sublistView(payload, offset, offset + keyBlobLen);
      offset += keyBlobLen;
      expect(bytesEqual(parsedKeyBlob, keyBlob), isTrue);

      final dataLen = readUint32(payload, offset);
      offset += 4;
      expect(dataLen, equals(5));

      final parsedData = Uint8List.sublistView(payload, offset, offset + dataLen);
      offset += dataLen;
      expect(bytesEqual(parsedData, dataToSign), isTrue);

      // Flags.
      final parsedFlags = readUint32(payload, offset);
      expect(parsedFlags, equals(flags));
    });

    test('parses sign request with large key blob', () {
      final keyBlob = Uint8List(256);
      for (var i = 0; i < 256; i++) {
        keyBlob[i] = i & 0xFF;
      }
      final data = Uint8List.fromList([0xFF]);

      final out = BytesBuilder();
      writeBytes(out, keyBlob);
      writeBytes(out, data);
      writeUint32(out, 0);
      final payload = Uint8List.fromList(out.takeBytes());

      final keyBlobLen = readUint32(payload, 0);
      expect(keyBlobLen, equals(256));
      final parsedBlob = Uint8List.sublistView(payload, 4, 4 + keyBlobLen);
      expect(bytesEqual(parsedBlob, keyBlob), isTrue);
    });
  });
}
