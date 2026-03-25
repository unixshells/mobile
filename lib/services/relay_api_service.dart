import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/account.dart';
import '../models/device.dart';
import '../models/shell.dart';
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
  Future<void> requestMagicLink({String? username, String? email}) async {
    final payload = <String, String>{'purpose': 'add-key'};
    if (username != null) payload['username'] = username;
    if (email != null) payload['email'] = email;
    final resp = await _client.post(
      Uri.parse('$_baseURL/api/magic-link'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    ).timeout(_timeout);
    if (resp.statusCode != 200) {
      final body = jsonDecode(resp.body);
      throw ApiException(body['error'] ?? 'request failed', resp.statusCode);
    }
  }

  /// Add a key using a magic link token. Returns {username, email}.
  Future<AddKeyResult> addKey({
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
    return AddKeyResult(
      username: body['username'] as String,
      email: body['email'] as String? ?? '',
    );
  }

  /// Get online sessions for a user. Requires auth token (timestamp:signature).
  Future<List<Device>> getSessions(String username, {required String token}) async {
    final resp = await _client.get(
      Uri.parse('$_baseURL/api/sessions/$username'),
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(_timeout);
    if (resp.statusCode != 200) {
      throw ApiException('sessions request failed', resp.statusCode);
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final devices = (body['devices'] as List)
        .map((d) => Device.fromJson(d as Map<String, dynamic>))
        .toList();
    return devices;
  }

  /// Create a device request (add-key). Server emails approval link.
  /// Returns the request ID for polling.
  Future<String> deviceRequest({
    required String username,
    required String pubkey,
    required String device,
  }) async {
    final resp = await _client.post(
      Uri.parse('$_baseURL/api/device-request'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'action': 'add-key',
        'pubkey': pubkey,
        'device': device,
      }),
    ).timeout(_timeout);
    if (resp.statusCode != 200) {
      final body = jsonDecode(resp.body);
      throw ApiException(body['error'] ?? 'request failed', resp.statusCode);
    }
    final body = jsonDecode(resp.body);
    return body['id'] as String;
  }

  /// Poll a device request until approved. Returns username on approval.
  Future<String?> getDeviceRequestStatus(String id) async {
    final resp = await _client.get(
      Uri.parse('$_baseURL/api/device-request/$id'),
    ).timeout(_timeout);
    if (resp.statusCode == 404) return null;
    if (resp.statusCode != 200) {
      throw ApiException('request expired', resp.statusCode);
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    if (body['status'] == 'approved') {
      return body['username'] as String?;
    }
    return null; // Still pending.
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

  /// List user's shells. Requires auth token.
  Future<List<Shell>> listShells({required String token}) async {
    final resp = await _client.get(
      Uri.parse('$_baseURL/api/shells'),
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(_timeout);
    if (resp.statusCode != 200) {
      throw ApiException('failed to list shells', resp.statusCode);
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    return (body['shells'] as List)
        .map((s) => Shell.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  /// Request shell checkout. Server sends email with checkout link.
  Future<String> requestShell({required String username, String plan = 'shell'}) async {
    final resp = await _client.post(
      Uri.parse('$_baseURL/api/request-shell'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'plan': plan}),
    ).timeout(_timeout);
    if (resp.statusCode != 200) {
      final body = jsonDecode(resp.body);
      throw ApiException(body['error'] ?? 'request failed', resp.statusCode);
    }
    final body = jsonDecode(resp.body);
    return body['message'] as String? ?? 'Check your email';
  }

  /// Destroy a shell (sends email verification).
  Future<String> destroyShell(String shellId, {required String token}) async {
    final resp = await _client.post(
      Uri.parse('$_baseURL/api/shells/$shellId/destroy'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({}),
    ).timeout(_timeout);
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode == 202) {
      return body['message'] as String? ?? 'Check your email to confirm';
    }
    if (resp.statusCode != 200) {
      throw ApiException(body['error'] ?? 'destroy failed', resp.statusCode);
    }
    return 'Shell destroyed';
  }

  /// Restart a shell (sends email verification).
  Future<String> restartShell(String shellId, {required String token}) async {
    final resp = await _client.post(
      Uri.parse('$_baseURL/api/shells/$shellId/restart'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({}),
    ).timeout(_timeout);
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode == 202) {
      return body['message'] as String? ?? 'Check your email to confirm';
    }
    if (resp.statusCode != 200) {
      throw ApiException(body['error'] ?? 'restart failed', resp.statusCode);
    }
    return 'Shell restarted';
  }

  /// Get account status and device list. Requires auth token (timestamp:signature).
  Future<AccountStatus> getStatus(String username, {required String token}) async {
    final resp = await _client.get(
      Uri.parse('$_baseURL/api/status/$username'),
      headers: {'Authorization': 'Bearer $token'},
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

class AddKeyResult {
  final String username;
  final String email;

  AddKeyResult({required this.username, required this.email});
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
