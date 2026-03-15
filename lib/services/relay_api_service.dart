import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/account.dart';
import '../models/device.dart';
import '../util/constants.dart';

/// TLS validation: Platform CA store validates the relay server certificate.
/// For custom relay hosts, the same platform validation applies.
/// Certificate pinning is intentionally omitted — the relay cert rotates
/// with Let's Encrypt, and pinning would break on renewal.
class RelayApiService {
  final http.Client _client;
  final String _baseURL;
  final Duration _timeout;

  RelayApiService({http.Client? client, String? baseURL, Duration? timeout})
      : _client = client ?? http.Client(),
        _baseURL = baseURL ?? apiBaseURL,
        _timeout = timeout ?? const Duration(seconds: 15);

  /// Create a RelayApiService that derives its base URL from a relay host.
  factory RelayApiService.fromHost({String? host, http.Client? client, Duration? timeout}) {
    final base = host != null && host.isNotEmpty ? 'https://$host' : apiBaseURL;
    return RelayApiService(client: client, baseURL: base, timeout: timeout);
  }

  Future<bool> healthCheck() async {
    try {
      final resp = await _client
          .get(Uri.parse('$_baseURL/health'))
          .timeout(const Duration(seconds: 5));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Request a magic link for adding a new device.
  Future<void> requestMagicLink(String email) async {
    final resp = await _client.post(
      Uri.parse('$_baseURL/api/magic-link'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'purpose': 'add-key'}),
    ).timeout(_timeout);
    if (resp.statusCode != 200) {
      final body = jsonDecode(resp.body);
      throw ApiException(body['error'] ?? 'request failed', resp.statusCode);
    }
  }

  /// Add a key using a magic link token.
  Future<String> addKey({
    required String token,
    required String pubkey,
    required String device,
  }) async {
    final resp = await _client.post(
      Uri.parse('$_baseURL/api/add-key'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'token': token,
        'pubkey': pubkey,
        'device': device,
      }),
    ).timeout(_timeout);
    if (resp.statusCode != 200) {
      final body = jsonDecode(resp.body);
      throw ApiException(body['error'] ?? 'add key failed', resp.statusCode);
    }
    final body = jsonDecode(resp.body);
    return body['username'] as String;
  }

  /// Push config to cloud. Requires auth token.
  Future<void> pushSync({
    required String username,
    required String token,
    required String data,
  }) async {
    final resp = await _client.put(
      Uri.parse('$_baseURL/api/sync/$username'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'data': data}),
    ).timeout(_timeout * 2);
    if (resp.statusCode != 200 && resp.statusCode != 204) {
      final body = jsonDecode(resp.body);
      throw ApiException(body['error'] ?? 'sync push failed', resp.statusCode);
    }
  }

  /// Pull config from cloud. Returns the stored data string.
  Future<String?> pullSync({
    required String username,
    required String token,
  }) async {
    final resp = await _client.get(
      Uri.parse('$_baseURL/api/sync/$username'),
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(_timeout);
    if (resp.statusCode == 404) return null;
    if (resp.statusCode != 200) {
      final body = jsonDecode(resp.body);
      throw ApiException(body['error'] ?? 'sync pull failed', resp.statusCode);
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    return body['data'] as String?;
  }

  /// Request a mosh UDP relay session.
  /// Returns the relay host and port for the client to connect to.
  Future<MoshRelaySession> moshRelay({
    required String username,
    required String device,
    required int targetPort,
  }) async {
    final resp = await _client.post(
      Uri.parse('$_baseURL/api/mosh-relay'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'device': device,
        'target_port': targetPort,
      }),
    ).timeout(_timeout);
    if (resp.statusCode != 200) {
      String msg;
      try {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        msg = body['error'] as String? ?? 'mosh relay failed';
      } catch (_) {
        msg = resp.body.isNotEmpty ? resp.body : 'mosh relay failed (${resp.statusCode})';
      }
      throw ApiException(msg, resp.statusCode);
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    return MoshRelaySession(
      sessionId: body['session_id'] as String,
      relayHost: body['relay_host'] as String,
      relayPort: body['relay_port'] as int,
    );
  }

  /// Get account status and device list.
  Future<AccountStatus> getStatus(String username) async {
    final resp = await _client.get(
      Uri.parse('$_baseURL/api/status/$username'),
    ).timeout(_timeout);
    if (resp.statusCode != 200) {
      throw ApiException('account not found', resp.statusCode);
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final devices = (body['devices'] as List)
        .map((d) => Device.fromJson(d as Map<String, dynamic>))
        .toList();
    return AccountStatus(
      account: UnixShellsAccount(
        username: body['username'] as String,
        email: body['email'] as String,
        subscriptionStatus: body['subscription'] as String? ?? '',
      ),
      devices: devices,
    );
  }
}

class AccountStatus {
  final UnixShellsAccount account;
  final List<Device> devices;

  AccountStatus({required this.account, required this.devices});
}

class MoshRelaySession {
  final String sessionId;
  final String relayHost;
  final int relayPort;

  MoshRelaySession({
    required this.sessionId,
    required this.relayHost,
    required this.relayPort,
  });
}

class ApiException implements Exception {
  final String message;
  final int statusCode;

  ApiException(this.message, this.statusCode);

  @override
  String toString() => message;
}
