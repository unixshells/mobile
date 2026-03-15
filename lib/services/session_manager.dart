import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/connection.dart';
import '../models/session.dart';
import 'mosh_service.dart';
import 'ssh_service.dart';

class SessionManager extends ChangeNotifier {
  final SSHService _sshService;
  late final MoshService _moshService = MoshService(_sshService);
  final List<ActiveSession> _sessions = [];
  int _activeIndex = -1;

  SessionManager(this._sshService);

  /// Add a pre-built session (for testing or external use).
  @visibleForTesting
  void addSession(ActiveSession session) {
    _sessions.add(session);
    _activeIndex = _sessions.length - 1;
    notifyListeners();
  }

  List<ActiveSession> get sessions => List.unmodifiable(_sessions);
  int get activeIndex => _activeIndex;

  ActiveSession? get activeSession {
    if (_activeIndex < 0 || _activeIndex >= _sessions.length) return null;
    return _sessions[_activeIndex];
  }

  Future<ActiveSession> connect(Connection conn) async {
    if (conn.useMosh) {
      return _connectMosh(conn);
    }

    final result = await _sshService.connect(conn);
    final shell = await _sshService.openShell(result.targetClient,
        agentForwarding: conn.agentForwarding);
    // Start port forwards.
    final forwards = conn.portForwards.isNotEmpty
        ? await _sshService.startPortForwards(
            result.targetClient, conn.portForwards)
        : <ActiveForward>[];

    final session = ActiveSession(
      id: const Uuid().v4(),
      connection: conn,
      jumpClient: result.jumpClient,
      targetClient: result.targetClient,
      shell: shell,
      label: conn.label,
      activeForwards: forwards,
    );

    _sessions.add(session);
    _activeIndex = _sessions.length - 1;
    notifyListeners();
    return session;
  }

  Future<ActiveSession> _connectMosh(Connection conn) async {
    final mosh = await _moshService.connect(conn);

    final session = ActiveSession(
      id: const Uuid().v4(),
      connection: conn,
      label: '${conn.label} (mosh)',
      moshSession: mosh,
    );

    _sessions.add(session);
    _activeIndex = _sessions.length - 1;
    notifyListeners();
    return session;
  }

  void switchTo(int index) {
    if (index < 0 || index >= _sessions.length) return;
    _activeIndex = index;
    notifyListeners();
  }

  void disconnect(String sessionId) {
    final idx = _sessions.indexWhere((s) => s.id == sessionId);
    if (idx < 0) return;
    _sessions[idx].close();
    _sessions.removeAt(idx);
    if (_activeIndex >= _sessions.length) {
      _activeIndex = _sessions.length - 1;
    }
    notifyListeners();
  }

  void disconnectAll() {
    for (final s in _sessions) {
      s.close();
    }
    _sessions.clear();
    _activeIndex = -1;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnectAll();
    super.dispose();
  }
}
