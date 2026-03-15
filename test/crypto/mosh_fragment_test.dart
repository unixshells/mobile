import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:unixshells/crypto/mosh_fragment.dart';
import 'package:unixshells/crypto/mosh_transport.dart';
import 'package:unixshells/crypto/ocb.dart';

void main() {
  group('Fragment', () {
    test('marshal/unmarshal round-trip', () {
      final payload = Uint8List.fromList([1, 2, 3, 4, 5]);
      final f = Fragment(id: 42, fragmentNum: 3, isFinal: false, payload: payload);

      final wire = f.marshal();
      final got = Fragment.unmarshal(wire);

      expect(got.id, equals(42));
      expect(got.fragmentNum, equals(3));
      expect(got.isFinal, isFalse);
      expect(got.payload, equals(payload));
    });

    test('final bit sets high bit of uint16', () {
      final f = Fragment(id: 1, fragmentNum: 0, isFinal: true, payload: Uint8List(0));

      final wire = f.marshal();
      // Bytes 8-9 contain the numAndFinal field.
      final view = ByteData.sublistView(wire);
      final numAndFinal = view.getUint16(8);
      expect(numAndFinal & 0x8000, equals(0x8000));
      expect(numAndFinal & 0x7fff, equals(0));
    });

    test('non-final bit has high bit clear', () {
      final f = Fragment(id: 1, fragmentNum: 5, isFinal: false, payload: Uint8List(0));

      final wire = f.marshal();
      final view = ByteData.sublistView(wire);
      final numAndFinal = view.getUint16(8);
      expect(numAndFinal & 0x8000, equals(0));
      expect(numAndFinal & 0x7fff, equals(5));
    });

    test('final bit with non-zero fragment num', () {
      final f = Fragment(id: 1, fragmentNum: 7, isFinal: true, payload: Uint8List(0));

      final wire = f.marshal();
      final got = Fragment.unmarshal(wire);

      expect(got.fragmentNum, equals(7));
      expect(got.isFinal, isTrue);
    });

    test('unmarshal rejects short data', () {
      final short = Uint8List(5);
      expect(() => Fragment.unmarshal(short), throwsFormatException);
    });

    test('marshal wire length is header + payload', () {
      final payload = Uint8List.fromList([10, 20, 30]);
      final f = Fragment(id: 0, fragmentNum: 0, isFinal: true, payload: payload);

      final wire = f.marshal();
      expect(wire.length, equals(fragmentHeaderSize + payload.length));
    });
  });

  group('fragmentize', () {
    test('small data produces single fragment', () {
      final data = Uint8List.fromList(List.generate(100, (i) => i & 0xff));
      final frags = fragmentize(1, data);

      expect(frags.length, equals(1));
      expect(frags[0].id, equals(1));
      expect(frags[0].fragmentNum, equals(0));
      expect(frags[0].isFinal, isTrue);
      expect(frags[0].payload, equals(data));
    });

    test('large data produces multiple fragments', () {
      // 3000 bytes > 1300 maxFragmentPayload -> 3 fragments.
      final data = Uint8List.fromList(List.generate(3000, (i) => i & 0xff));
      final frags = fragmentize(5, data);

      expect(frags.length, equals(3));

      // First two are not final, last one is.
      expect(frags[0].isFinal, isFalse);
      expect(frags[0].fragmentNum, equals(0));
      expect(frags[0].payload.length, equals(1300));

      expect(frags[1].isFinal, isFalse);
      expect(frags[1].fragmentNum, equals(1));
      expect(frags[1].payload.length, equals(1300));

      expect(frags[2].isFinal, isTrue);
      expect(frags[2].fragmentNum, equals(2));
      expect(frags[2].payload.length, equals(400));

      // All share the same ID.
      for (final f in frags) {
        expect(f.id, equals(5));
      }
    });

    test('exactly maxFragmentPayload bytes produces one fragment', () {
      final data = Uint8List(maxFragmentPayload);
      final frags = fragmentize(1, data);

      expect(frags.length, equals(1));
      expect(frags[0].isFinal, isTrue);
      expect(frags[0].payload.length, equals(maxFragmentPayload));
    });

    test('maxFragmentPayload + 1 bytes produces two fragments', () {
      final data = Uint8List(maxFragmentPayload + 1);
      final frags = fragmentize(1, data);

      expect(frags.length, equals(2));
      expect(frags[0].payload.length, equals(maxFragmentPayload));
      expect(frags[1].payload.length, equals(1));
      expect(frags[1].isFinal, isTrue);
    });

    test('empty data produces single final fragment', () {
      final frags = fragmentize(9, Uint8List(0));

      expect(frags.length, equals(1));
      expect(frags[0].id, equals(9));
      expect(frags[0].fragmentNum, equals(0));
      expect(frags[0].isFinal, isTrue);
      expect(frags[0].payload.length, equals(0));
    });
  });

  group('FragmentAssembler', () {
    test('in-order assembly of single fragment', () {
      final asm = FragmentAssembler();
      final payload = Uint8List.fromList([1, 2, 3]);
      final f = Fragment(id: 1, fragmentNum: 0, isFinal: true, payload: payload);

      final result = asm.add(f);
      expect(result, isNotNull);
      expect(result, equals(payload));
    });

    test('in-order assembly of multiple fragments', () {
      final asm = FragmentAssembler();
      final data = Uint8List.fromList(List.generate(3000, (i) => i & 0xff));
      final frags = fragmentize(1, data);

      // First two return null.
      expect(asm.add(frags[0]), isNull);
      expect(asm.add(frags[1]), isNull);

      // Last one triggers reassembly.
      final result = asm.add(frags[2]);
      expect(result, isNotNull);
      expect(result, equals(data));
    });

    test('new ID resets state', () {
      final asm = FragmentAssembler();

      // Start with ID 1, send only first fragment.
      final f1 = Fragment(id: 1, fragmentNum: 0, isFinal: false, payload: Uint8List.fromList([1]));
      expect(asm.add(f1), isNull);

      // New ID 2 resets; single final fragment completes.
      final f2 = Fragment(id: 2, fragmentNum: 0, isFinal: true, payload: Uint8List.fromList([2]));
      final result = asm.add(f2);
      expect(result, isNotNull);
      expect(result, equals(Uint8List.fromList([2])));
    });

    test('stale ID is ignored', () {
      final asm = FragmentAssembler();

      // Establish current ID as 5.
      final f5 = Fragment(id: 5, fragmentNum: 0, isFinal: true, payload: Uint8List.fromList([5]));
      expect(asm.add(f5), isNotNull);

      // ID 3 is stale, should be ignored.
      final f3 = Fragment(id: 3, fragmentNum: 0, isFinal: true, payload: Uint8List.fromList([3]));
      expect(asm.add(f3), isNull);
    });

    test('out-of-order fragments assemble correctly', () {
      final asm = FragmentAssembler();
      final data = Uint8List.fromList(List.generate(3000, (i) => i & 0xff));
      final frags = fragmentize(1, data);

      // Deliver out of order: 2 (final), 0, 1.
      expect(asm.add(frags[2]), isNull);
      expect(asm.add(frags[0]), isNull);
      final result = asm.add(frags[1]);
      expect(result, isNotNull);
      expect(result, equals(data));
    });

    test('empty fragment payload assembles', () {
      final asm = FragmentAssembler();
      final f = Fragment(id: 1, fragmentNum: 0, isFinal: true, payload: Uint8List(0));

      final result = asm.add(f);
      expect(result, isNotNull);
      expect(result!.length, equals(0));
    });
  });

  group('MoshTransport', () {
    late AesOcb ocb;

    setUp(() {
      final key = Uint8List.fromList(List.generate(16, (i) => i));
      ocb = AesOcb(key);
    });

    test('tick returns empty when nothing to send', () {
      final t = MoshTransport.client(ocb);
      final datagrams = t.tick();
      expect(datagrams, isEmpty);
    });

    test('tick returns datagrams after sendNew', () {
      final t = MoshTransport.client(ocb);
      final diff = Uint8List.fromList('hello'.codeUnits);
      t.sendNew(diff);

      final datagrams = t.tick();
      expect(datagrams, isNotEmpty);
      // Each datagram must be at least minDatagram bytes.
      for (final dg in datagrams) {
        expect(dg.length, greaterThanOrEqualTo(minDatagram));
      }
    });

    test('client tick datagrams have direction bit 0 (TO_SERVER)', () {
      final t = MoshTransport.client(ocb);
      t.sendNew(Uint8List.fromList([1, 2, 3]));

      final datagrams = t.tick();
      expect(datagrams, isNotEmpty);

      for (final dg in datagrams) {
        final view = ByteData.sublistView(dg);
        final dirSeq = view.getUint64(0);
        // Bit 63 should be 0 for TO_SERVER.
        final dirBit = dirSeq >> 63;
        expect(dirBit, equals(0));
      }
    });

    test('consecutive ticks increment sequence number', () {
      final t = MoshTransport.client(ocb);

      t.sendNew(Uint8List.fromList([1]));
      final dg1 = t.tick();

      t.sendNew(Uint8List.fromList([2]));
      final dg2 = t.tick();

      expect(dg1, isNotEmpty);
      expect(dg2, isNotEmpty);

      // The nonce/sequence in the first 8 bytes should differ.
      final seq1 = ByteData.sublistView(dg1[0]).getUint64(0);
      final seq2 = ByteData.sublistView(dg2[0]).getUint64(0);
      expect(seq2, greaterThan(seq1));
    });

    test('setPending with null clears pending', () {
      final t = MoshTransport.client(ocb);

      t.sendNew(Uint8List.fromList([1, 2, 3]));
      t.setPending(null);

      // Nothing pending, no ack needed, no timeout -> empty.
      final datagrams = t.tick();
      expect(datagrams, isEmpty);
    });

    test('loopback: client tick fed to another client recv', () {
      // Two transports sharing the same key. Since we only have
      // MoshTransport.client(), both send TO_SERVER and expect TO_CLIENT.
      // The receiver won't accept datagrams with the wrong direction bit,
      // so this verifies the direction check works correctly.
      final sender = MoshTransport.client(ocb);
      final receiver = MoshTransport.client(ocb);

      sender.sendNew(Uint8List.fromList('test'.codeUnits));
      final datagrams = sender.tick();
      expect(datagrams, isNotEmpty);

      // A client receiver expects TO_CLIENT direction, but sender
      // sends TO_SERVER. So recv should reject these.
      for (final dg in datagrams) {
        final result = receiver.recv(dg);
        expect(result, isNull);
      }
    });

    test('recv rejects short datagram', () {
      final t = MoshTransport.client(ocb);
      final short = Uint8List(10);
      expect(t.recv(short), isNull);
    });

    test('recv rejects garbage datagram', () {
      final t = MoshTransport.client(ocb);
      final garbage = Uint8List.fromList(List.generate(100, (i) => i));
      expect(t.recv(garbage), isNull);
    });
  });
}
