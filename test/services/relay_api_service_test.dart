import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:unixshells/services/relay_api_service.dart';

void main() {
  group('RelayApiService', () {
    test('healthCheck returns true on 200', () async {
      final client = MockClient((_) async => http.Response('ok', 200));
      final api = RelayApiService(client: client, baseURL: 'http://test');
      expect(await api.healthCheck(), isTrue);
    });

    test('healthCheck returns false on 500', () async {
      final client = MockClient((_) async => http.Response('err', 500));
      final api = RelayApiService(client: client, baseURL: 'http://test');
      expect(await api.healthCheck(), isFalse);
    });

    test('healthCheck returns false on network error', () async {
      final client = MockClient((_) async => throw Exception('no network'));
      final api = RelayApiService(client: client, baseURL: 'http://test');
      expect(await api.healthCheck(), isFalse);
    });

    test('signup returns username on 201', () async {
      final client = MockClient((req) async {
        expect(req.url.path, '/api/signup');
        expect(req.method, 'POST');
        final body = jsonDecode(req.body);
        expect(body['username'], 'testuser');
        return http.Response(jsonEncode({'username': 'testuser'}), 201);
      });
      final api = RelayApiService(client: client, baseURL: 'http://test');
      final result = await api.signup(
        username: 'testuser',
        email: 'test@test.com',
        pubkey: 'ssh-ed25519 AAAA test',
        device: 'phone',
      );
      expect(result, 'testuser');
    });

    test('signup throws ApiException on 409', () async {
      final client = MockClient((_) async =>
          http.Response(jsonEncode({'error': 'username taken'}), 409));
      final api = RelayApiService(client: client, baseURL: 'http://test');
      expect(
        () => api.signup(
          username: 'taken',
          email: 'e',
          pubkey: 'p',
          device: 'd',
        ),
        throwsA(isA<ApiException>()),
      );
    });

    test('requestMagicLink succeeds on 200', () async {
      final client = MockClient((req) async {
        expect(req.url.path, '/api/magic-link');
        return http.Response('{}', 200);
      });
      final api = RelayApiService(client: client, baseURL: 'http://test');
      await api.requestMagicLink('test@test.com');
    });

    test('requestMagicLink throws on error', () async {
      final client = MockClient((_) async =>
          http.Response(jsonEncode({'error': 'not found'}), 404));
      final api = RelayApiService(client: client, baseURL: 'http://test');
      expect(
        () => api.requestMagicLink('bad@email'),
        throwsA(isA<ApiException>()),
      );
    });

    test('addKey returns username on 200', () async {
      final client = MockClient((req) async {
        expect(req.url.path, '/api/add-key');
        return http.Response(jsonEncode({'username': 'user1'}), 200);
      });
      final api = RelayApiService(client: client, baseURL: 'http://test');
      final result = await api.addKey(
        token: 'tok',
        pubkey: 'pk',
        device: 'dev',
      );
      expect(result, 'user1');
    });

    test('getStatus parses account and devices', () async {
      final client = MockClient((req) async {
        expect(req.url.path, '/api/status/user1');
        return http.Response(
          jsonEncode({
            'username': 'user1',
            'email': 'u@e.com',
            'subscription': 'active',
            'devices': [
              {'device': 'macbook', 'added_at': '2024-01-01', 'online': true},
              {'device': 'phone', 'added_at': '2024-02-01'},
            ],
          }),
          200,
        );
      });
      final api = RelayApiService(client: client, baseURL: 'http://test');
      final status = await api.getStatus('user1');

      expect(status.account.username, 'user1');
      expect(status.account.email, 'u@e.com');
      expect(status.account.subscriptionStatus, 'active');
      expect(status.account.isActive, isTrue);
      expect(status.devices.length, 2);
      expect(status.devices[0].name, 'macbook');
      expect(status.devices[0].online, isTrue);
      expect(status.devices[1].name, 'phone');
      expect(status.devices[1].online, isFalse);
    });

    test('getStatus throws on 404', () async {
      final client =
          MockClient((_) async => http.Response('not found', 404));
      final api = RelayApiService(client: client, baseURL: 'http://test');
      expect(
        () => api.getStatus('nobody'),
        throwsA(isA<ApiException>()),
      );
    });

    test('ApiException toString returns message', () {
      final ex = ApiException('bad request', 400);
      expect(ex.toString(), 'bad request');
      expect(ex.statusCode, 400);
    });
  });
}
