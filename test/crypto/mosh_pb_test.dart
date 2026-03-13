import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:unixshells/crypto/mosh_pb.dart';

void main() {
  group('TransportInstruction', () {
    test('marshal/unmarshal round-trip with defaults', () {
      final ti = TransportInstruction(
        oldNum: 5,
        newNum: 10,
        ackNum: 3,
        throwawayNum: 1,
      );
      final data = ti.marshal();
      final got = TransportInstruction.unmarshal(data);

      expect(got.protocolVersion, equals(0));
      expect(got.oldNum, equals(5));
      expect(got.newNum, equals(10));
      expect(got.ackNum, equals(3));
      expect(got.throwawayNum, equals(1));
      expect(got.diff, isNull);
      expect(got.chaff, isNull);
    });

    test('marshal/unmarshal round-trip with diff', () {
      final diff = Uint8List.fromList('hello world'.codeUnits);
      final ti = TransportInstruction(
        oldNum: 1,
        newNum: 2,
        ackNum: 0,
        throwawayNum: 0,
        diff: diff,
      );
      final data = ti.marshal();
      final got = TransportInstruction.unmarshal(data);

      expect(got.diff, isNotNull);
      expect(got.diff, equals(diff));
    });

    test('marshal/unmarshal round-trip with protocol_version', () {
      final ti = TransportInstruction(
        protocolVersion: 2,
        oldNum: 0,
        newNum: 1,
        ackNum: 0,
        throwawayNum: 0,
      );
      final data = ti.marshal();
      final got = TransportInstruction.unmarshal(data);

      expect(got.protocolVersion, equals(2));
      expect(got.newNum, equals(1));
    });

    test('marshal/unmarshal with all fields set', () {
      final diff = Uint8List.fromList([1, 2, 3, 4, 5]);
      final chaff = Uint8List.fromList([0xde, 0xad, 0xbe, 0xef]);
      final ti = TransportInstruction(
        protocolVersion: 2,
        oldNum: 100,
        newNum: 200,
        ackNum: 150,
        throwawayNum: 50,
        diff: diff,
        chaff: chaff,
      );
      final data = ti.marshal();
      final got = TransportInstruction.unmarshal(data);

      expect(got.protocolVersion, equals(2));
      expect(got.oldNum, equals(100));
      expect(got.newNum, equals(200));
      expect(got.ackNum, equals(150));
      expect(got.throwawayNum, equals(50));
      expect(got.diff, equals(diff));
      expect(got.chaff, equals(chaff));
    });

    test('empty diff vs null diff', () {
      // Null diff: field 6 is omitted.
      final tiNull = TransportInstruction(diff: null);
      final datNull = tiNull.marshal();
      final gotNull = TransportInstruction.unmarshal(datNull);
      expect(gotNull.diff, isNull);

      // Empty diff: field 6 is omitted (same behavior as null).
      final tiEmpty = TransportInstruction(diff: Uint8List(0));
      final datEmpty = tiEmpty.marshal();
      final gotEmpty = TransportInstruction.unmarshal(datEmpty);
      expect(gotEmpty.diff, isNull);
    });

    test('empty message marshal/unmarshal', () {
      final ti = TransportInstruction();
      final data = ti.marshal();
      final got = TransportInstruction.unmarshal(data);

      expect(got.protocolVersion, equals(0));
      expect(got.oldNum, equals(0));
      expect(got.newNum, equals(0));
      expect(got.ackNum, equals(0));
      expect(got.throwawayNum, equals(0));
      expect(got.diff, isNull);
      expect(got.chaff, isNull);
    });

    test('large diff payload', () {
      final diff = Uint8List.fromList(List.generate(5000, (i) => i & 0xff));
      final ti = TransportInstruction(
        oldNum: 1,
        newNum: 2,
        ackNum: 1,
        throwawayNum: 0,
        diff: diff,
      );
      final data = ti.marshal();
      final got = TransportInstruction.unmarshal(data);

      expect(got.diff, isNotNull);
      expect(got.diff!.length, equals(5000));
      expect(got.diff, equals(diff));
    });

    test('large varint values', () {
      final ti = TransportInstruction(
        oldNum: 0x7fffffff,
        newNum: 0x7fffffff,
        ackNum: 12345678,
        throwawayNum: 0,
      );
      final data = ti.marshal();
      final got = TransportInstruction.unmarshal(data);

      expect(got.oldNum, equals(0x7fffffff));
      expect(got.newNum, equals(0x7fffffff));
      expect(got.ackNum, equals(12345678));
    });
  });

  group('UserMessage', () {
    test('marshal/unmarshal keystroke', () {
      final keys = Uint8List.fromList('ls -la\n'.codeUnits);
      final instrs = [UserInstruction(keys: keys)];

      final data = marshalUserMessage(instrs);
      final got = unmarshalUserMessage(data);

      expect(got.length, equals(1));
      expect(got[0].keys, equals(keys));
      expect(got[0].width, equals(0));
      expect(got[0].height, equals(0));
    });

    test('marshal/unmarshal resize', () {
      final instrs = [UserInstruction(width: 120, height: 40)];

      final data = marshalUserMessage(instrs);
      final got = unmarshalUserMessage(data);

      expect(got.length, equals(1));
      expect(got[0].keys, isNull);
      expect(got[0].width, equals(120));
      expect(got[0].height, equals(40));
    });

    test('marshal/unmarshal keystroke and resize', () {
      final keys = Uint8List.fromList('x'.codeUnits);
      final instrs = [
        UserInstruction(keys: keys),
        UserInstruction(width: 80, height: 24),
      ];

      final data = marshalUserMessage(instrs);
      final got = unmarshalUserMessage(data);

      expect(got.length, equals(2));
      expect(got[0].keys, equals(keys));
      expect(got[1].width, equals(80));
      expect(got[1].height, equals(24));
    });

    test('empty message list', () {
      final data = marshalUserMessage([]);
      final got = unmarshalUserMessage(data);
      expect(got, isEmpty);
    });

    test('empty keys are omitted', () {
      final instrs = [UserInstruction(keys: Uint8List(0))];
      final data = marshalUserMessage(instrs);
      final got = unmarshalUserMessage(data);

      expect(got.length, equals(1));
      expect(got[0].keys, isNull);
    });
  });

  group('HostMessage', () {
    test('marshal/unmarshal hoststring', () {
      final hs = Uint8List.fromList('terminal output\n'.codeUnits);
      final instrs = [HostInstruction(hoststring: hs)];

      final data = marshalHostMessage(instrs);
      final got = unmarshalHostMessage(data);

      expect(got.length, equals(1));
      expect(got[0].hoststring, equals(hs));
      expect(got[0].width, equals(0));
      expect(got[0].height, equals(0));
      expect(got[0].echoAckNum, equals(-1));
    });

    test('marshal/unmarshal resize', () {
      final instrs = [HostInstruction(width: 132, height: 50)];

      final data = marshalHostMessage(instrs);
      final got = unmarshalHostMessage(data);

      expect(got.length, equals(1));
      expect(got[0].hoststring, isNull);
      expect(got[0].width, equals(132));
      expect(got[0].height, equals(50));
    });

    test('marshal/unmarshal echo_ack', () {
      final instrs = [HostInstruction(echoAckNum: 42)];

      final data = marshalHostMessage(instrs);
      final got = unmarshalHostMessage(data);

      expect(got.length, equals(1));
      expect(got[0].echoAckNum, equals(42));
    });

    test('marshal/unmarshal hoststring, resize, and echo_ack', () {
      final hs = Uint8List.fromList('data'.codeUnits);
      final instrs = [
        HostInstruction(hoststring: hs),
        HostInstruction(width: 80, height: 24),
        HostInstruction(echoAckNum: 7),
      ];

      final data = marshalHostMessage(instrs);
      final got = unmarshalHostMessage(data);

      expect(got.length, equals(3));
      expect(got[0].hoststring, equals(hs));
      expect(got[1].width, equals(80));
      expect(got[1].height, equals(24));
      expect(got[2].echoAckNum, equals(7));
    });

    test('single instruction with all fields', () {
      final hs = Uint8List.fromList('output'.codeUnits);
      final instrs = [
        HostInstruction(hoststring: hs, width: 80, height: 24, echoAckNum: 99),
      ];

      final data = marshalHostMessage(instrs);
      final got = unmarshalHostMessage(data);

      expect(got.length, equals(1));
      expect(got[0].hoststring, equals(hs));
      expect(got[0].width, equals(80));
      expect(got[0].height, equals(24));
      expect(got[0].echoAckNum, equals(99));
    });

    test('empty message list', () {
      final data = marshalHostMessage([]);
      final got = unmarshalHostMessage(data);
      expect(got, isEmpty);
    });

    test('large hoststring payload', () {
      final hs = Uint8List.fromList(List.generate(10000, (i) => i & 0xff));
      final instrs = [HostInstruction(hoststring: hs)];

      final data = marshalHostMessage(instrs);
      final got = unmarshalHostMessage(data);

      expect(got.length, equals(1));
      expect(got[0].hoststring!.length, equals(10000));
      expect(got[0].hoststring, equals(hs));
    });
  });
}
