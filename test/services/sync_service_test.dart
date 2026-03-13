import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart' as ssh;
import 'package:dartssh2/src/ssh_hostkey.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:unixshells/models/account.dart';
import 'package:unixshells/models/ssh_key.dart';
import 'package:unixshells/services/key_service.dart';
import 'package:unixshells/services/relay_api_service.dart';
import 'package:unixshells/services/storage_service.dart';
import 'package:unixshells/services/sync_service.dart';

// -- Fakes --

class FakeStorageService extends Fake implements StorageService {
  final Map<String, String> _settings = {};
  UnixShellsAccount? _account;
  String? _exportedData;
  String? _importedData;

  @override
  Future<String?> getSetting(String key) async => _settings[key];

  @override
  Future<void> saveSetting(String key, String value) async {
    _settings[key] = value;
  }

  @override
  Future<UnixShellsAccount?> getAccount() async => _account;

  @override
  Future<void> saveAccount(UnixShellsAccount account) async {
    _account = account;
  }

  @override
  Future<String> exportData() async => _exportedData ?? '{}';

  @override
  Future<void> importData(String json, {bool merge = false}) async {
    _importedData = json;
  }

  @override
  Future<List<SSHKeyPair>> listKeys() async => [];
}

class FakeRelayApiService extends Fake implements RelayApiService {
  int pushSyncCalls = 0;
  String? lastPushUsername;
  String? lastPushToken;
  String? lastPushData;
  bool pushSyncThrows = false;

  String? pullSyncData;
  int pullSyncCalls = 0;

  @override
  Future<void> pushSync({
    required String username,
    required String token,
    required String data,
  }) async {
    pushSyncCalls++;
    lastPushUsername = username;
    lastPushToken = token;
    lastPushData = data;
    if (pushSyncThrows) throw Exception('push failed');
  }

  @override
  Future<String?> pullSync({
    required String username,
    required String token,
  }) async {
    pullSyncCalls++;
    return pullSyncData;
  }
}

/// Fake SSH signature that encodes to known bytes.
class _FakeSignature implements SSHSignature {
  @override
  Uint8List encode() => Uint8List.fromList([0x00, 0x00, 0x00, 0x03, 0xAA, 0xBB, 0xCC]);
}

/// Fake dartssh2 SSHKeyPair that produces a deterministic signature.
class _FakeSSHKeyPair implements ssh.SSHKeyPair {
  @override
  String get name => 'ssh-ed25519';

  @override
  String get type => 'ssh-ed25519';

  @override
  SSHSignature sign(Uint8List data) => _FakeSignature();

  @override
  SSHHostKey toPublicKey() => throw UnimplementedError();

  @override
  String toPem() => throw UnimplementedError();
}

class FakeKeyService extends Fake implements KeyService {
  List<SSHKeyPair> _keys = [];
  List<ssh.SSHKeyPair> _identities = [];

  @override
  Future<List<SSHKeyPair>> list() async => _keys;

  @override
  Future<List<ssh.SSHKeyPair>> loadIdentity(String keyId) async => _identities;
}

void main() {
  group('SyncService.autoSync', () {
    late FakeStorageService storage;
    late FakeRelayApiService api;
    late FakeKeyService keyService;
    late SyncService syncService;

    setUp(() {
      storage = FakeStorageService();
      api = FakeRelayApiService();
      keyService = FakeKeyService();
      syncService = SyncService(storage, api, keyService);
    });

    test('does nothing when sync_enabled is not set', () async {
      await syncService.autoSync();
      expect(api.pushSyncCalls, equals(0));
    });

    test('does nothing when sync_enabled is false', () async {
      storage._settings['sync_enabled'] = 'false';
      await syncService.autoSync();
      expect(api.pushSyncCalls, equals(0));
    });

    test('does nothing when sync_enabled is empty string', () async {
      storage._settings['sync_enabled'] = '';
      await syncService.autoSync();
      expect(api.pushSyncCalls, equals(0));
    });

    test('swallows errors from push gracefully', () async {
      storage._settings['sync_enabled'] = 'true';
      storage._account = UnixShellsAccount(
        username: 'testuser',
        email: 'test@example.com',
      );
      keyService._keys = [
        SSHKeyPair(
          id: 'k1',
          label: 'relay-mydevice',
          publicKeyOpenSSH: 'ssh-ed25519 AAAA relay-mydevice',
          createdAt: 1000,
        ),
      ];
      keyService._identities = [_FakeSSHKeyPair()];
      api.pushSyncThrows = true;

      // Should not throw.
      await syncService.autoSync();
      expect(api.pushSyncCalls, equals(1));
    });

    test('swallows errors when not signed in', () async {
      storage._settings['sync_enabled'] = 'true';
      storage._account = null;

      // Should not throw (autoSync catches all errors).
      await syncService.autoSync();
      expect(api.pushSyncCalls, equals(0));
    });

    test('swallows errors when no relay key exists', () async {
      storage._settings['sync_enabled'] = 'true';
      storage._account = UnixShellsAccount(
        username: 'testuser',
        email: 'test@example.com',
      );
      keyService._keys = [
        SSHKeyPair(
          id: 'k1',
          label: 'my-server-key',
          publicKeyOpenSSH: 'ssh-ed25519 AAAA my-server-key',
          createdAt: 1000,
        ),
      ];

      await syncService.autoSync();
      expect(api.pushSyncCalls, equals(0));
    });
  });

  group('SyncService.pull', () {
    late FakeStorageService storage;
    late FakeRelayApiService api;
    late FakeKeyService keyService;
    late SyncService syncService;

    setUp(() {
      storage = FakeStorageService();
      api = FakeRelayApiService();
      keyService = FakeKeyService();
      syncService = SyncService(storage, api, keyService);

      storage._account = UnixShellsAccount(
        username: 'testuser',
        email: 'test@example.com',
      );
      keyService._keys = [
        SSHKeyPair(
          id: 'k1',
          label: 'relay-dev',
          publicKeyOpenSSH: 'ssh-ed25519 AAAA relay-dev',
          createdAt: 1000,
        ),
      ];
      keyService._identities = [_FakeSSHKeyPair()];
    });

    test('returns false when server returns null', () async {
      api.pullSyncData = null;
      final result = await syncService.pull();
      expect(result, isFalse);
    });

    test('returns false for invalid JSON', () async {
      api.pullSyncData = 'not json {{{';
      final result = await syncService.pull();
      expect(result, isFalse);
    });

    test('returns false for non-map JSON', () async {
      api.pullSyncData = '"just a string"';
      final result = await syncService.pull();
      expect(result, isFalse);
    });

    test('imports valid data and records last_sync', () async {
      api.pullSyncData = jsonEncode({'version': 2, 'connections': []});
      final result = await syncService.pull();
      expect(result, isTrue);
      expect(storage._importedData, isNotNull);
      expect(storage._settings['last_sync'], isNotNull);
    });
  });

  group('SyncService.push', () {
    late FakeStorageService storage;
    late FakeRelayApiService api;
    late FakeKeyService keyService;
    late SyncService syncService;

    setUp(() {
      storage = FakeStorageService();
      api = FakeRelayApiService();
      keyService = FakeKeyService();
      syncService = SyncService(storage, api, keyService);

      storage._account = UnixShellsAccount(
        username: 'testuser',
        email: 'test@example.com',
      );
      keyService._keys = [
        SSHKeyPair(
          id: 'k1',
          label: 'relay-dev',
          publicKeyOpenSSH: 'ssh-ed25519 AAAA relay-dev',
          createdAt: 1000,
        ),
      ];
      keyService._identities = [_FakeSSHKeyPair()];
      storage._exportedData = '{"version":2}';
    });

    test('sends data to API and records last_sync', () async {
      await syncService.push();
      expect(api.pushSyncCalls, equals(1));
      expect(api.lastPushUsername, equals('testuser'));
      expect(api.lastPushData, equals('{"version":2}'));
      expect(storage._settings['last_sync'], isNotNull);
    });

    test('auth token has timestamp:base64 format', () async {
      await syncService.push();
      final token = api.lastPushToken!;

      // Token format: "timestamp:base64signature"
      expect(token.contains(':'), isTrue);
      final parts = token.split(':');
      expect(parts.length, equals(2));

      // First part is a millisecond timestamp (parseable as int).
      final timestamp = int.tryParse(parts[0]);
      expect(timestamp, isNotNull);
      expect(timestamp! > 0, isTrue);

      // Second part is valid base64.
      expect(() => base64Decode(parts[1]), returnsNormally);
    });

    test('throws when not signed in', () async {
      storage._account = null;
      expect(() => syncService.push(), throwsException);
    });

    test('throws when no relay key found', () async {
      keyService._keys = [];
      expect(() => syncService.push(), throwsException);
    });

    test('throws when key not loadable', () async {
      keyService._identities = [];
      expect(() => syncService.push(), throwsException);
    });
  });

  group('SyncService.lastSync', () {
    test('returns null when never synced', () async {
      final storage = FakeStorageService();
      final api = FakeRelayApiService();
      final keyService = FakeKeyService();
      final syncService = SyncService(storage, api, keyService);

      final result = await syncService.lastSync();
      expect(result, isNull);
    });

    test('returns stored timestamp after sync', () async {
      final storage = FakeStorageService();
      storage._settings['last_sync'] = '2026-01-01T00:00:00.000';
      final api = FakeRelayApiService();
      final keyService = FakeKeyService();
      final syncService = SyncService(storage, api, keyService);

      final result = await syncService.lastSync();
      expect(result, equals('2026-01-01T00:00:00.000'));
    });
  });
}
