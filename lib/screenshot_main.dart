/// Screenshot mode entry point.
///
/// Uses custom screens with pre-loaded data for authentic App Store screenshots.
///
/// Usage:
///   ./scripts/take_screenshots.sh "iPhone 16 Pro Max"
///   ./scripts/take_screenshots.sh "iPad Pro 13-inch (M4)"
///   ./scripts/take_android_screenshots.sh [emulator_id]
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart' as xterm;

import 'models/connection.dart';
import 'models/session.dart';
import 'services/discovery_service.dart';
import 'services/key_service.dart';
import 'services/relay_api_service.dart';
import 'services/session_manager.dart';
import 'services/ssh_service.dart';
import 'services/storage_service.dart';
import 'models/terminal_theme.dart';
import 'util/constants.dart';

/// Check if running on Android.
bool get _isAndroid => !kIsWeb && Platform.isAndroid;

/// Signal file directory for screenshot coordination (iOS only).
const _signalDir = '/tmp/screenshot_signals';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _cleanupSignals();
  await _setupScreenshotData();
  runApp(const ScreenshotApp());
}

late StorageService _storage;
late KeyService _keyService;
late SSHService _sshService;
late RelayApiService _api;
late DiscoveryService _discovery;
late SessionManager _sessionManager;

Future<void> _setupScreenshotData() async {
  _storage = StorageService();
  _keyService = KeyService(_storage);
  _sshService = SSHService(_keyService, _storage);
  _api = RelayApiService();
  _discovery = DiscoveryService(_api, _storage, _keyService);
  _sessionManager = SessionManager(_sshService);

  final d = await _storage.db;

  // Clear existing connections.
  await d.delete('connections');

  // Insert sample connections.
  final connections = [
    Connection(
      id: 'demo_1',
      label: 'Production Server',
      type: ConnectionType.direct,
      host: 'prod.example.com',
      username: 'deploy',
      authMethod: AuthMethod.key,
      lastConnected: DateTime.now()
          .subtract(const Duration(minutes: 12))
          .millisecondsSinceEpoch,
      sortOrder: 0,
    ),
    Connection(
      id: 'demo_2',
      label: 'Dev Workstation',
      type: ConnectionType.relay,
      host: '',
      username: 'mark',
      authMethod: AuthMethod.key,
      relayUsername: 'mark',
      relayDevice: 'dev-workstation',
      useMosh: true,
      lastConnected: DateTime.now()
          .subtract(const Duration(hours: 1))
          .millisecondsSinceEpoch,
      sortOrder: 1,
    ),
    Connection(
      id: 'demo_3',
      label: 'Raspberry Pi',
      type: ConnectionType.direct,
      host: '192.168.1.50',
      username: 'pi',
      authMethod: AuthMethod.key,
      lastConnected: DateTime.now()
          .subtract(const Duration(hours: 3))
          .millisecondsSinceEpoch,
      sortOrder: 2,
    ),
    Connection(
      id: 'demo_4',
      label: 'CI Runner',
      type: ConnectionType.relay,
      host: '',
      username: 'mark',
      authMethod: AuthMethod.key,
      relayUsername: 'mark',
      relayDevice: 'ci-runner',
      sessionName: 'builds',
      lastConnected: DateTime.now()
          .subtract(const Duration(days: 1))
          .millisecondsSinceEpoch,
      sortOrder: 3,
    ),
    Connection(
      id: 'demo_5',
      label: 'Database Server',
      type: ConnectionType.direct,
      host: 'db.example.com',
      port: 2222,
      username: 'admin',
      authMethod: AuthMethod.key,
      portForwards: [],
      sortOrder: 4,
    ),
    Connection(
      id: 'demo_6',
      label: 'GPU Cluster',
      type: ConnectionType.relay,
      host: '',
      username: 'mark',
      authMethod: AuthMethod.key,
      relayUsername: 'mark',
      relayDevice: 'gpu-node-01',
      useMosh: true,
      sortOrder: 5,
    ),
  ];

  for (final conn in connections) {
    await d.insert('connections', conn.toMap());
  }

  // Create mock active sessions with pre-populated terminal content.
  _createMockSessions(connections);

  debugPrint('Screenshot data setup complete');
}

void _createMockSessions(List<Connection> connections) {
  // Session 1: Claude Code running on dev workstation.
  final session1 = ActiveSession(
    id: 'session_1',
    connection: connections[1], // Dev Workstation
    label: 'Dev Workstation (mosh)',
    createdAt: DateTime.now().subtract(const Duration(minutes: 45)),
  );
  _writeClaudioTerminal(session1.terminal);
  _sessionManager.addSession(session1);

  // Session 2: Production server.
  final session2 = ActiveSession(
    id: 'session_2',
    connection: connections[0], // Production Server
    label: 'Production Server',
    createdAt: DateTime.now().subtract(const Duration(minutes: 12)),
  );
  _writeServerTerminal(session2.terminal);
  _sessionManager.addSession(session2);

  // Session 3: Raspberry Pi.
  final session3 = ActiveSession(
    id: 'session_3',
    connection: connections[2], // Raspberry Pi
    label: 'Raspberry Pi',
    createdAt: DateTime.now().subtract(const Duration(hours: 2)),
  );
  _writePiTerminal(session3.terminal);
  _sessionManager.addSession(session3);

  // Switch to session 1 (Claude Code) as active.
  _sessionManager.switchTo(0);
}

/// Simulate Claude Code terminal output.
void _writeClaudioTerminal(xterm.Terminal term) {
  term.write('\x1b[32mmark@dev-workstation\x1b[0m:\x1b[34m~/projects/api\x1b[0m\$ claude\r\n');
  term.write('\r\n');
  term.write('\x1b[1;36m╭─────────────────────────────────────────╮\x1b[0m\r\n');
  term.write('\x1b[1;36m│\x1b[0m  \x1b[1mClaude Code\x1b[0m \x1b[90mv1.0.33\x1b[0m                   \x1b[1;36m│\x1b[0m\r\n');
  term.write('\x1b[1;36m│\x1b[0m  \x1b[90m/projects/api\x1b[0m                         \x1b[1;36m│\x1b[0m\r\n');
  term.write('\x1b[1;36m╰─────────────────────────────────────────╯\x1b[0m\r\n');
  term.write('\r\n');
  term.write('\x1b[1;35m>\x1b[0m add rate limiting to the /api/upload endpoint\r\n');
  term.write('\r\n');
  term.write('\x1b[90mI\'ll add rate limiting to the upload endpoint. Let me\x1b[0m\r\n');
  term.write('\x1b[90mcheck the current implementation first.\x1b[0m\r\n');
  term.write('\r\n');
  term.write(' \x1b[36mRead\x1b[0m src/routes/upload.ts\r\n');
  term.write(' \x1b[36mRead\x1b[0m src/middleware/auth.ts\r\n');
  term.write(' \x1b[33mEdit\x1b[0m src/routes/upload.ts \x1b[32m+15 -3\x1b[0m\r\n');
  term.write(' \x1b[33mEdit\x1b[0m src/middleware/rate_limit.ts \x1b[32m(new)\x1b[0m\r\n');
  term.write(' \x1b[36mBash\x1b[0m npm test -- --grep "upload"\r\n');
  term.write('\r\n');
  term.write('  \x1b[32m✓\x1b[0m upload rate limiting (48ms)\r\n');
  term.write('  \x1b[32m✓\x1b[0m rejects after 10 requests per minute (52ms)\r\n');
  term.write('  \x1b[32m✓\x1b[0m allows requests after window expires (61ms)\r\n');
  term.write('\r\n');
  term.write('  \x1b[32m3 passing\x1b[0m \x1b[90m(161ms)\x1b[0m\r\n');
  term.write('\r\n');
  term.write('\x1b[90mDone. I\'ve added a sliding window rate limiter to\x1b[0m\r\n');
  term.write('\x1b[90m/api/upload — 10 requests per minute per API key.\x1b[0m\r\n');
  term.write('\x1b[90mAll 3 tests pass.\x1b[0m\r\n');
  term.write('\r\n');
  term.write('\x1b[1;35m>\x1b[0m \x1b[5m▋\x1b[0m');
}

/// Simulate a production server terminal.
void _writeServerTerminal(xterm.Terminal term) {
  term.write('\x1b[32mdeploy@prod\x1b[0m:\x1b[34m~\x1b[0m\$ docker ps --format "table {{.Names}}\\t{{.Status}}\\t{{.Ports}}"\r\n');
  term.write('NAMES              STATUS          PORTS\r\n');
  term.write('api-gateway        Up 14 days      0.0.0.0:443->443/tcp\r\n');
  term.write('app-server-1       Up 14 days      8080/tcp\r\n');
  term.write('app-server-2       Up 14 days      8080/tcp\r\n');
  term.write('postgres-primary   Up 31 days      5432/tcp\r\n');
  term.write('redis-cache        Up 31 days      6379/tcp\r\n');
  term.write('nginx-lb           Up 14 days      0.0.0.0:80->80/tcp\r\n');
  term.write('\x1b[32mdeploy@prod\x1b[0m:\x1b[34m~\x1b[0m\$ \x1b[5m▋\x1b[0m');
}

/// Simulate a Raspberry Pi terminal.
void _writePiTerminal(xterm.Terminal term) {
  term.write('\x1b[32mpi@raspberrypi\x1b[0m:\x1b[34m~\x1b[0m\$ neofetch\r\n');
  term.write('\x1b[32m  .~~.   .~~.\x1b[0m    pi@raspberrypi\r\n');
  term.write('\x1b[32m .\'. \\ \' .\' /\'\x1b[0m    ───────────────\r\n');
  term.write('\x1b[31m .~~..\'   \'.~~.\x1b[0m   OS: Raspbian 12 aarch64\r\n');
  term.write('\x1b[31m\'. \\  \'  / .\'\x1b[0m    Kernel: 6.6.51-v8+\r\n');
  term.write('\x1b[31m .~ ..  \'.. ~.\x1b[0m    Uptime: 47 days, 3 hours\r\n');
  term.write('\x1b[31m.\'   ..  .\'   .\x1b[0m   Packages: 1284\r\n');
  term.write('\x1b[31m :   ~ :: ~   :\x1b[0m   Shell: bash 5.2.15\r\n');
  term.write('\x1b[31m \'~ ..\' \'.. ~\'\x1b[0m   Memory: 412MiB / 3736MiB\r\n');
  term.write('\x1b[31m  \'~  ..  ~\'\x1b[0m\r\n');
  term.write('\r\n');
  term.write('\x1b[32mpi@raspberrypi\x1b[0m:\x1b[34m~\x1b[0m\$ \x1b[5m▋\x1b[0m');
}

/// Signal that a screen is ready for screenshot.
Future<void> _signalReady(int screenNumber) async {
  if (_isAndroid) {
    // On Android, log the signal — the script monitors logcat.
    debugPrint('SCREENSHOT_SIGNAL: Screen $screenNumber ready');
    return;
  }

  final dir = Directory(_signalDir);
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  final file = File('$_signalDir/ready_$screenNumber');
  await file.writeAsString(DateTime.now().toIso8601String());
  debugPrint('SCREENSHOT_SIGNAL: Screen $screenNumber ready');
}

/// Wait for screenshot to be taken (signal file deleted).
Future<void> _waitForCapture(int screenNumber) async {
  if (_isAndroid) {
    // On Android, use fixed timing since signal files don't cross the
    // host/emulator boundary.
    await Future.delayed(const Duration(seconds: 5));
    debugPrint('SCREENSHOT_SIGNAL: Screen $screenNumber capture window complete');
    return;
  }

  final file = File('$_signalDir/ready_$screenNumber');
  for (var i = 0; i < 600; i++) {
    await Future.delayed(const Duration(milliseconds: 100));
    if (!file.existsSync()) {
      debugPrint('SCREENSHOT_SIGNAL: Screen $screenNumber captured');
      return;
    }
  }
  debugPrint('SCREENSHOT_SIGNAL: Timeout waiting for capture of screen $screenNumber');
}

/// Clean up signal files.
void _cleanupSignals() {
  if (_isAndroid) return;

  try {
    final dir = Directory(_signalDir);
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  } catch (e) {
    debugPrint('Signal cleanup error: $e');
  }
}

class ScreenshotApp extends StatelessWidget {
  const ScreenshotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider.value(value: _storage),
        Provider.value(value: _keyService),
        Provider.value(value: _sshService),
        Provider.value(value: _api),
        ChangeNotifierProvider.value(value: _discovery),
        ChangeNotifierProvider.value(value: _sessionManager),
      ],
      child: MaterialApp(
        title: 'Unix Shells',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: bgDark,
          colorScheme: const ColorScheme.dark(
            primary: Colors.blue,
            surface: bgCard,
          ),
          useMaterial3: true,
        ),
        home: const ScreenshotOrchestrator(),
      ),
    );
  }
}

class ScreenshotOrchestrator extends StatefulWidget {
  const ScreenshotOrchestrator({super.key});

  @override
  State<ScreenshotOrchestrator> createState() =>
      _ScreenshotOrchestratorState();
}

class _ScreenshotOrchestratorState extends State<ScreenshotOrchestrator> {
  int _currentStep = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(seconds: 2), _runScreenshotSequence);
    });
  }

  Future<void> _runScreenshotSequence() async {
    // Screenshot 1: Connections list.
    setState(() => _currentStep = 1);
    await Future.delayed(const Duration(milliseconds: 500));
    await _signalReady(1);
    await _waitForCapture(1);

    // Screenshot 2: Terminal with Claude Code.
    _sessionManager.switchTo(0);
    setState(() => _currentStep = 2);
    await Future.delayed(const Duration(milliseconds: 500));
    await _signalReady(2);
    await _waitForCapture(2);

    // Screenshot 3: Terminal with server (second session tab active).
    _sessionManager.switchTo(1);
    setState(() => _currentStep = 3);
    await Future.delayed(const Duration(milliseconds: 500));
    await _signalReady(3);
    await _waitForCapture(3);

    // Screenshot 4: Active sessions list.
    setState(() => _currentStep = 4);
    await Future.delayed(const Duration(milliseconds: 500));
    await _signalReady(4);
    await _waitForCapture(4);

    debugPrint('SCREENSHOT_SIGNAL: All screenshots complete');
  }

  @override
  Widget build(BuildContext context) {
    return switch (_currentStep) {
      0 => const Scaffold(
          backgroundColor: bgDark,
          body: Center(child: CircularProgressIndicator()),
        ),
      1 => const _ConnectionsScreen(),
      2 => const _TerminalScreen(),
      3 => const _TerminalScreen(),
      4 => const _SessionsScreen(),
      _ => const Scaffold(
          backgroundColor: bgDark,
          body: Center(child: Text('Done')),
        ),
    };
  }
}

/// Fake tab bar that looks like the real one but needs no TabController.
class _FakeTabBar extends StatelessWidget implements PreferredSizeWidget {
  final int selectedIndex;
  final List<String> labels;

  const _FakeTabBar({required this.selectedIndex, required this.labels});

  @override
  Size get preferredSize => const Size.fromHeight(46);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: bgCard,
      child: Row(
        children: labels.asMap().entries.map((entry) {
          final i = entry.key;
          final label = entry.value;
          final selected = i == selectedIndex;
          return Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: selected ? Colors.blue : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: selected ? Colors.white : Colors.white54,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Screenshot 1: Connections list (All tab).
class _ConnectionsScreen extends StatelessWidget {
  const _ConnectionsScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgDark,
      appBar: AppBar(
        title: const Text('Unix Shells'),
        backgroundColor: bgCard,
        foregroundColor: Colors.white,
        bottom: const _FakeTabBar(
          selectedIndex: 0,
          labels: ['All', 'Unix Shells', 'Sessions (3)'],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: () {}),
          IconButton(
              icon: const Icon(Icons.vpn_key_outlined), onPressed: () {}),
          IconButton(
              icon: const Icon(Icons.settings_outlined), onPressed: () {}),
        ],
      ),
      body: FutureBuilder<List<Connection>>(
        future: _storage.listConnections(),
        builder: (context, snapshot) {
          final connections = snapshot.data ?? [];
          return ListView.builder(
            itemCount: connections.length,
            itemBuilder: (context, i) {
              final conn = connections[i];
              final isRelay = conn.type == ConnectionType.relay;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      isRelay ? Colors.blue.withValues(alpha: 0.2) : bgButton,
                  child: Icon(
                    isRelay ? Icons.cloud : Icons.computer,
                    color: isRelay ? Colors.blue : Colors.white54,
                    size: 20,
                  ),
                ),
                title: Text(
                  conn.label,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
                subtitle: Text(
                  conn.sessionName != null && conn.sessionName!.isNotEmpty
                      ? '${conn.destination} · ${conn.sessionName}'
                      : conn.destination,
                  style: const TextStyle(color: Colors.white38, fontSize: 13),
                ),
                trailing: const Icon(Icons.more_vert, color: Colors.white38),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.blue,
        onPressed: () {},
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// Screenshots 2 & 3: Terminal screen with session tabs and extra keys.
class _TerminalScreen extends StatelessWidget {
  const _TerminalScreen();

  @override
  Widget build(BuildContext context) {
    return Consumer<SessionManager>(
      builder: (context, manager, _) {
        final session = manager.activeSession;
        if (session == null) {
          return const Scaffold(
            backgroundColor: bgDark,
            body: Center(child: Text('No session')),
          );
        }

        final t = terminalThemes['default']!;
        final xtermTheme = xterm.TerminalTheme(
          cursor: t.cursor,
          selection: t.selection,
          foreground: t.foreground,
          background: t.background,
          black: t.black,
          red: t.red,
          green: t.green,
          yellow: t.yellow,
          blue: t.blue,
          magenta: t.magenta,
          cyan: t.cyan,
          white: t.white,
          brightBlack: t.brightBlack,
          brightRed: t.brightRed,
          brightGreen: t.brightGreen,
          brightYellow: t.brightYellow,
          brightBlue: t.brightBlue,
          brightMagenta: t.brightMagenta,
          brightCyan: t.brightCyan,
          brightWhite: t.brightWhite,
          searchHitBackground: const Color(0xFFFFDF5D),
          searchHitBackgroundCurrent: const Color(0xFFFF9632),
          searchHitForeground: const Color(0xFF000000),
        );

        return Scaffold(
          backgroundColor: bgDark,
          body: SafeArea(
            child: Column(
              children: [
                // Session tabs.
                Container(
                  color: bgCard,
                  height: 36,
                  child: Row(
                    children: [
                      Expanded(
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: manager.sessions.length,
                          itemBuilder: (context, i) {
                            final s = manager.sessions[i];
                            final active = i == manager.activeIndex;
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: active ? bgDark : Colors.transparent,
                                border: Border(
                                  bottom: BorderSide(
                                    color: active
                                        ? Colors.blue
                                        : Colors.transparent,
                                    width: 2,
                                  ),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    s.label,
                                    style: TextStyle(
                                      color: active
                                          ? Colors.white
                                          : Colors.white54,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(Icons.close,
                                      size: 14, color: Colors.white38),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.folder_outlined,
                            color: Colors.white54, size: 18),
                        onPressed: () {},
                      ),
                      IconButton(
                        icon: const Icon(Icons.search,
                            color: Colors.white54, size: 18),
                        onPressed: () {},
                      ),
                      IconButton(
                        icon: const Icon(Icons.keyboard_hide,
                            color: Colors.white54, size: 18),
                        onPressed: () {},
                      ),
                    ],
                  ),
                ),
                // Terminal.
                Expanded(
                  child: xterm.TerminalView(
                    session.terminal,
                    theme: xtermTheme,
                    textStyle: const xterm.TerminalStyle(
                      fontSize: 14,
                      fontFamily: 'monospace',
                    ),
                    autofocus: false,
                    deleteDetection: false,
                  ),
                ),
                // Extra keys bar.
                Container(
                  color: bgCard,
                  padding:
                      const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _extraKey('Esc'),
                        _extraKey('Tab'),
                        _extraKey('Ctrl'),
                        _extraKey('|'),
                        _extraKey('/'),
                        _extraKey('-'),
                        _extraKey('_'),
                        _extraKey('~'),
                        _extraKey('.'),
                        _extraKey(':'),
                        _extraKey('@'),
                        _extraKey('#'),
                        _extraKey('\$'),
                        _extraKey('\u2190'),
                        _extraKey('\u2191'),
                        _extraKey('\u2193'),
                        _extraKey('\u2192'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _extraKey(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: bgButton,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: const TextStyle(
              color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}

/// Screenshot 4: Active sessions list.
class _SessionsScreen extends StatelessWidget {
  const _SessionsScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgDark,
      appBar: AppBar(
        title: const Text('Unix Shells'),
        backgroundColor: bgCard,
        foregroundColor: Colors.white,
        bottom: const _FakeTabBar(
          selectedIndex: 2,
          labels: ['All', 'Unix Shells', 'Sessions (3)'],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: () {}),
          IconButton(
              icon: const Icon(Icons.vpn_key_outlined), onPressed: () {}),
          IconButton(
              icon: const Icon(Icons.settings_outlined), onPressed: () {}),
        ],
      ),
      body: Consumer<SessionManager>(
        builder: (context, manager, _) {
          return ListView.builder(
            itemCount: manager.sessions.length,
            itemBuilder: (context, i) {
              final session = manager.sessions[i];
              final isRelay =
                  session.connection.type == ConnectionType.relay;
              final duration =
                  DateTime.now().difference(session.createdAt);
              String elapsed;
              if (duration.inHours > 0) {
                elapsed =
                    '${duration.inHours}h ${duration.inMinutes % 60}m';
              } else if (duration.inMinutes > 0) {
                elapsed = '${duration.inMinutes}m';
              } else {
                elapsed = 'just now';
              }
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: isRelay
                      ? Colors.blue.withValues(alpha: 0.2)
                      : bgButton,
                  child: Icon(
                    isRelay ? Icons.cloud : Icons.computer,
                    color: isRelay ? Colors.blue : Colors.white54,
                    size: 20,
                  ),
                ),
                title: Text(
                  session.label,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 15),
                ),
                subtitle: Text(
                  '${session.connection.destination} · $elapsed',
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 13),
                ),
                trailing: const Icon(Icons.arrow_forward_ios,
                    size: 14, color: Colors.white24),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.blue,
        onPressed: () {},
        child: const Icon(Icons.add),
      ),
    );
  }
}
