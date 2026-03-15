import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:xterm/xterm.dart' as xterm;

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

  /// Each session owns its own terminal buffer so content persists
  /// across tab switches and navigation.
  final xterm.Terminal terminal;

  /// Stream subscriptions owned by this session — set up once, never
  /// re-subscribed. This avoids "Stream has already been listened to".
  StreamSubscription<Uint8List>? _stdoutSub;
  StreamSubscription<Uint8List>? _moshIncomingSub;
  StreamSubscription<Uint8List>? _moshPassthroughSub;
  bool ended = false;
  void Function()? onEnded;

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
        activeForwards = activeForwards ?? [],
        terminal = xterm.Terminal(maxLines: 10000);

  bool _listening = false;

  /// Start listening to output streams. Safe to call multiple times.
  void startListening() {
    if (_listening) return;
    _listening = true;
    if (isMosh) {
      _startMosh();
    } else {
      _startSSH();
    }
  }

  void _startSSH() {
    _stdoutSub = shell!.stdout.listen(
      (data) {
        terminal.write(utf8.decode(data, allowMalformed: true));
      },
      onError: (_) => _markEnded(),
      onDone: () => _markEnded(),
    );
  }

  void _startMosh() {
    final mosh = moshSession!;
    _moshIncomingSub = mosh.incoming.listen(
      (data) {
        try {
          terminal.write(utf8.decode(data, allowMalformed: true));
        } catch (_) {}
      },
      onError: (_) => _markEnded(),
      onDone: () => _markEnded(),
    );
    _moshPassthroughSub = mosh.passthroughEscapes.listen((_) {});
    if (!mosh.started) mosh.start();
  }

  void _markEnded() {
    if (ended) return;
    ended = true;
    terminal.write('\r\n\x1b[90m[Session ended. Close tab to disconnect.]\x1b[0m\r\n');
    onEnded?.call();
  }

  void close() {
    _stdoutSub?.cancel();
    _moshIncomingSub?.cancel();
    _moshPassthroughSub?.cancel();
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
