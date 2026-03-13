import 'package:flutter_test/flutter_test.dart';
import 'package:unixshells/models/device.dart';

void main() {
  group('Device', () {
    test('fromJson parses all fields', () {
      final json = {
        'device': 'macbook',
        'added_at': '2024-01-15',
        'online': true,
      };
      final device = Device.fromJson(json);
      expect(device.name, 'macbook');
      expect(device.addedAt, '2024-01-15');
      expect(device.online, isTrue);
    });

    test('fromJson defaults addedAt and online', () {
      final json = {'device': 'phone'};
      final device = Device.fromJson(json);
      expect(device.name, 'phone');
      expect(device.addedAt, '');
      expect(device.online, isFalse);
    });
  });
}
