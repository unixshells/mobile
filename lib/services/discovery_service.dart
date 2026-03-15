import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/device.dart';
import 'key_service.dart';
import 'relay_api_service.dart';
import 'storage_service.dart';

class DiscoveryService extends ChangeNotifier {
  final RelayApiService _api;
  final StorageService _storage;
  final KeyService _keyService;
  Timer? _timer;
  List<Device> _onlineDevices = [];
  bool _loading = false;

  DiscoveryService(this._api, this._storage, this._keyService);

  List<Device> get onlineDevices => _onlineDevices;
  bool get loading => _loading;

  /// Sign a timestamp with the relay key for auth.
  /// Uses the key saved during sign-in, falling back to any relay-* key.
  /// Sign a timestamp with the relay key for auth.
  /// Uses the key saved during sign-in, falling back to any relay-* key.
  Future<String?> _getAuthToken() async {
    final keys = await _keyService.list();
    if (keys.isEmpty) return null;

    // Prefer the key used during sign-in.
    final savedKeyId = await _storage.getSetting('relay_key_id');
    var key = savedKeyId != null
        ? keys.where((k) => k.id == savedKeyId).firstOrNull
        : null;
    // Fall back to any relay-prefixed key.
    key ??= keys.where((k) => k.label.startsWith('relay-')).firstOrNull;
    if (key == null) return null;

    final identities = await _keyService.loadIdentity(key.id);
    if (identities.isEmpty) return null;

    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final sig = identities.first.sign(Uint8List.fromList(utf8.encode(timestamp)));
    final token = base64Encode(sig.encode());
    return '$timestamp:$token';
  }

  Future<void> refresh() async {
    final account = await _storage.getAccount();
    if (account == null) {
      _onlineDevices = [];
      notifyListeners();
      return;
    }
    final token = await _getAuthToken();
    if (token == null) {
      _onlineDevices = [];
      notifyListeners();
      return;
    }
    _loading = true;
    notifyListeners();
    try {
      _onlineDevices = await _api.getSessions(account.username, token: token);
    } catch (_) {
      // Keep stale list on error.
    }
    _loading = false;
    notifyListeners();
  }

  void start() {
    refresh();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => refresh());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
