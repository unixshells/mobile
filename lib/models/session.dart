import 'dart:io';

import 'package:dartssh2/dartssh2.dart';

import '../services/mosh_service.dart';
import 'connection.dart';

class ActiveSession {
  final String id;
  final Connection connection;
  final SSHClient? jumpClient;
  final SSHClient? targetClient;
  final SSHSession? shell;
  final MoshSession? moshSession;
  final String label;
  final DateTime createdAt;
  final List<ActiveForward> activeForwards;

  bool get isMosh => moshSession != null;

  ActiveSession({
    required this.id,
    required this.connection,
    this.jumpClient,
    this.targetClient,
    this.shell,
    this.moshSession,
    required this.label,
    DateTime? createdAt,
    List<ActiveForward>? activeForwards,
  })  : createdAt = createdAt ?? DateTime.now(),
        activeForwards = activeForwards ?? [];

  void close() {
    for (final fwd in activeForwards) {
      fwd.close();
    }
    moshSession?.close();
    shell?.close();
    targetClient?.close();
    jumpClient?.close();
  }
}

class ActiveForward {
  final String description;
  final ServerSocket? server;

  ActiveForward({required this.description, this.server});

  void close() {
    server?.close();
  }
}
