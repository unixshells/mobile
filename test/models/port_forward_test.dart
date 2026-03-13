import 'package:flutter_test/flutter_test.dart';
import 'package:unixshells/models/port_forward.dart';

void main() {
  group('PortForward', () {
    test('toMap/fromMap round-trip for local forward', () {
      const fwd = PortForward(
        type: ForwardType.local,
        localPort: 8080,
        remoteHost: 'localhost',
        remotePort: 80,
      );

      final map = fwd.toMap();
      final restored = PortForward.fromMap(map);

      expect(restored.type, ForwardType.local);
      expect(restored.localPort, 8080);
      expect(restored.remoteHost, 'localhost');
      expect(restored.remotePort, 80);
    });

    test('toMap/fromMap round-trip for remote forward', () {
      const fwd = PortForward(
        type: ForwardType.remote,
        localPort: 5432,
        remoteHost: 'db.internal',
        remotePort: 3306,
      );

      final map = fwd.toMap();
      final restored = PortForward.fromMap(map);

      expect(restored.type, ForwardType.remote);
      expect(restored.localPort, 5432);
      expect(restored.remoteHost, 'db.internal');
      expect(restored.remotePort, 3306);
    });

    test('toMap produces expected keys and values', () {
      const fwd = PortForward(
        type: ForwardType.local,
        localPort: 9090,
        remoteHost: '10.0.0.1',
        remotePort: 443,
      );

      final map = fwd.toMap();

      expect(map['type'], 'local');
      expect(map['localPort'], 9090);
      expect(map['remoteHost'], '10.0.0.1');
      expect(map['remotePort'], 443);
    });

    test('encodeList/decodeList round-trip', () {
      final list = [
        const PortForward(
          type: ForwardType.local,
          localPort: 8080,
          remoteHost: 'localhost',
          remotePort: 80,
        ),
        const PortForward(
          type: ForwardType.remote,
          localPort: 5432,
          remoteHost: 'db.host',
          remotePort: 3306,
        ),
      ];

      final encoded = PortForward.encodeList(list);
      final decoded = PortForward.decodeList(encoded);

      expect(decoded.length, 2);
      expect(decoded[0].type, ForwardType.local);
      expect(decoded[0].localPort, 8080);
      expect(decoded[0].remoteHost, 'localhost');
      expect(decoded[0].remotePort, 80);
      expect(decoded[1].type, ForwardType.remote);
      expect(decoded[1].localPort, 5432);
      expect(decoded[1].remoteHost, 'db.host');
      expect(decoded[1].remotePort, 3306);
    });

    test('encodeList/decodeList round-trip with empty list', () {
      final encoded = PortForward.encodeList([]);
      final decoded = PortForward.decodeList(encoded);
      expect(decoded, isEmpty);
    });

    test('decodeList with null returns empty list', () {
      final result = PortForward.decodeList(null);
      expect(result, isEmpty);
    });

    test('decodeList with empty string returns empty list', () {
      final result = PortForward.decodeList('');
      expect(result, isEmpty);
    });

    test('toString for local forward', () {
      const fwd = PortForward(
        type: ForwardType.local,
        localPort: 8080,
        remoteHost: 'localhost',
        remotePort: 80,
      );
      expect(fwd.toString(), 'L8080:localhost:80');
    });

    test('toString for remote forward', () {
      const fwd = PortForward(
        type: ForwardType.remote,
        localPort: 5432,
        remoteHost: 'localhost',
        remotePort: 3306,
      );
      expect(fwd.toString(), 'R3306:localhost:5432');
    });
  });
}
