import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'key_service.dart';
import 'relay_api_service.dart';
import 'storage_service.dart';

/// Syncs app config (connections, keys, settings) via the relay API.
///
/// Auth: signs a timestamp with the relay SSH key. The server verifies
/// the signature against the registered public key.
class SyncService {
  final StorageService _storage;
  final RelayApiService _api;
  final KeyService _keyService;

  SyncService(this._storage, this._api, this._keyService);

  /// Find the relay key — the key generated during signup/addKey.
  Future<_SyncAuth> _getAuth() async {
    final account = await _storage.getAccount();
    if (account == null) throw Exception('not signed in');

    // Find the relay key by label convention (relay-<device>).
    final keys = await _keyService.list();
    final relayKey = keys.where((k) => k.label.startsWith('relay-')).firstOrNull;
    if (relayKey == null) {
      throw Exception('no relay key found — sign in again');
    }

    // Load the private key to sign.
    final identities = await _keyService.loadIdentity(relayKey.id);
    if (identities.isEmpty) throw Exception('relay key not loadable');

    // Sign current timestamp as auth proof.
    // NOTE: The token is timestamp:signature(timestamp). A server-side nonce
    // or method+path binding would strengthen replay protection. Currently
    // the server should enforce a tight time window (e.g. 30 seconds).
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final sig = identities.first.sign(Uint8List.fromList(utf8.encode(timestamp)));
    final token = base64Encode(sig.encode());

    return _SyncAuth(
      username: account.username,
      token: '$timestamp:$token',
    );
  }

  /// Push local config to the cloud.
  Future<void> push() async {
    final auth = await _getAuth();
    final data = await _storage.exportData();

    await _api.pushSync(
      username: auth.username,
      token: auth.token,
      data: data,
    );

    await _storage.saveSetting(
      'last_sync',
      DateTime.now().toIso8601String(),
    );
  }

  /// Pull cloud config and merge into local storage.
  Future<bool> pull() async {
    final auth = await _getAuth();

    final data = await _api.pullSync(
      username: auth.username,
      token: auth.token,
    );
    if (data == null) return false;

    // Validate before importing.
    try {
      final parsed = jsonDecode(data);
      if (parsed is! Map<String, dynamic>) return false;
    } catch (_) {
      return false;
    }

    await _storage.importData(data);
    await _storage.saveSetting(
      'last_sync',
      DateTime.now().toIso8601String(),
    );
    return true;
  }

  /// Auto-sync: push. Swallows errors.
  Future<void> autoSync() async {
    try {
      final enabled = await _storage.getSetting('sync_enabled');
      if (enabled != 'true') return;
      await push();
    } catch (e) {
      debugPrint('SyncService.autoSync: $e');
    }
  }

  /// Last sync timestamp.
  Future<String?> lastSync() => _storage.getSetting('last_sync');
}

class _SyncAuth {
  final String username;
  final String token;
  _SyncAuth({required this.username, required this.token});
}
