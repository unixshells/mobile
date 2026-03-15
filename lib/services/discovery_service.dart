import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

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
  Future<String?> _getAuthToken() async {
    final keys = await _keyService.list();
    final relayKey = keys.where((k) => k.label.startsWith('relay-')).firstOrNull;
    if (relayKey == null) return null;

    final identities = await _keyService.loadIdentity(relayKey.id);
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
    } catch (e) {
      debugPrint('discovery error: $e');
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
