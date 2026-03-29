import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart' as xterm;

import '../../models/connection.dart';
import '../../models/terminal_theme.dart';
import '../../services/demo_service.dart';
import '../../services/session_manager.dart';
import '../../services/sftp_service.dart';
import '../../services/storage_service.dart';
import '../../util/constants.dart';
import '../sftp/sftp_view.dart';
import 'prefix_drawer.dart';
import 'terminal_bridge.dart';

class TerminalPage extends StatefulWidget {
  final Connection? pendingConnection;

  const TerminalPage({super.key, this.pendingConnection});

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage>
    with WidgetsBindingObserver {
  late TerminalBridge _bridge;
  final _termController = xterm.TerminalController();
  bool _showExtraKeys = true;
  bool _ctrlActive = false;
  bool _connecting = false;
  String? _connectError;
  bool _showSearch = false;
  final _searchCtrl = TextEditingController();
  final _searchHighlights = <xterm.TerminalHighlight>[];

  /// Temporary terminal used only during the "Connecting..." phase
  /// before a session exists.
  xterm.Terminal? _connectingTerminal;

  String _themeId = 'default';
  double _fontSize = 14;
  String _fontFamily = 'monospace';

  /// The terminal currently being displayed.
  xterm.Terminal get _activeTerminal {
    final manager = context.read<SessionManager>();
    return manager.activeSession?.terminal ?? _connectingTerminal!;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bridge = TerminalBridge();
    _bridge.onDisconnect = _handleDisconnect;
    _bridge.onSessionEnded = _handleSessionEnded;
    _bridge.outputInterceptor = _interceptCtrl;

    _loadSettings();

    if (widget.pendingConnection != null) {
      _connectPending(widget.pendingConnection!);
    } else {
      _attachCurrentSession();
    }
  }

  Future<void> _connectPending(Connection conn) async {
    // Demo mode: show a mock terminal instead of connecting.
    if (DemoService().isActive) {
      _connectingTerminal = xterm.Terminal(maxLines: 10000);
      setState(() { _connecting = true; _connectError = null; });
      _connectingTerminal!.write('Connecting to ${conn.label}...\r\n');
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      _connectingTerminal!.write('\x1b[32mConnected.\x1b[0m\r\n\r\n');
      _writeDemoContent(_connectingTerminal!, conn);
      setState(() => _connecting = false);
      return;
    }

    _connectingTerminal = xterm.Terminal(maxLines: 10000);
    setState(() {
      _connecting = true;
      _connectError = null;
    });
    _connectingTerminal!.write('Connecting to ${conn.label}...\r\n');

    try {
      final manager = context.read<SessionManager>();
      final storage = context.read<StorageService>();
      await manager.connect(conn);
      await storage.updateLastConnected(conn.id);
      if (!mounted) return;
      _connectingTerminal = null;
      setState(() => _connecting = false);
      _attachCurrentSession();
    } catch (e) {
      if (!mounted) return;
      final msg = _friendlyError(e.toString());
      setState(() {
        _connecting = false;
        _connectError = msg;
      });
      _connectingTerminal?.write('\x1b[31mConnection failed: $msg\x1b[0m\r\n');
    }
  }

  void _writeDemoContent(xterm.Terminal term, Connection conn) {
    final session = conn.sessionName ?? 'default';
    final device = conn.relayDevice ?? conn.label;

    if (device.contains('workstation') && session == 'dev') {
      term.write('\x1b[1m$device\x1b[0m ~ \x1b[36mvim ~/project/main.go\x1b[0m\r\n\r\n');
      term.write('  \x1b[34mpackage\x1b[0m main\r\n\r\n');
      term.write('  \x1b[34mimport\x1b[0m (\r\n');
      term.write('      \x1b[33m"fmt"\x1b[0m\r\n');
      term.write('      \x1b[33m"net/http"\x1b[0m\r\n');
      term.write('  )\r\n\r\n');
      term.write('  \x1b[34mfunc\x1b[0m \x1b[32mmain\x1b[0m() {\r\n');
      term.write('      http.HandleFunc(\x1b[33m"/"\x1b[0m, handler)\r\n');
      term.write('      fmt.Println(\x1b[33m"Listening on :8080"\x1b[0m)\r\n');
      term.write('      http.ListenAndServe(\x1b[33m":8080"\x1b[0m, \x1b[34mnil\x1b[0m)\r\n');
      term.write('  }\r\n');
    } else if (device.contains('prod')) {
      term.write('\x1b[1m$device\x1b[0m ~ \x1b[36mtail -f /var/log/nginx/access.log\x1b[0m\r\n\r\n');
      term.write('192.168.1.42 - - [28/Mar/2026:10:15:32 +0000] "GET /api/status HTTP/2.0" 200 1523\r\n');
      term.write('10.0.0.8 - - [28/Mar/2026:10:15:33 +0000] "POST /api/sessions HTTP/2.0" 201 842\r\n');
      term.write('192.168.1.42 - - [28/Mar/2026:10:15:35 +0000] "GET /api/devices HTTP/2.0" 200 3201\r\n');
      term.write('172.16.0.3 - - [28/Mar/2026:10:15:36 +0000] "GET /health HTTP/2.0" 200 2\r\n');
      term.write('10.0.0.12 - - [28/Mar/2026:10:15:38 +0000] "PUT /api/shell/renew HTTP/2.0" 200 156\r\n');
      term.write('192.168.1.42 - - [28/Mar/2026:10:15:40 +0000] "GET /api/status HTTP/2.0" 200 1523\r\n');
    } else if (device.contains('raspberry') || device.contains('pi')) {
      term.write('\x1b[1m$device\x1b[0m ~ \x1b[36mmonitoring\x1b[0m\r\n\r\n');
      term.write('\x1b[32mCPU:\x1b[0m  12% [####                                ]\r\n');
      term.write('\x1b[32mMEM:\x1b[0m  41% [################                    ]  412MB / 1024MB\r\n');
      term.write('\x1b[32mDISK:\x1b[0m 23% [#########                           ]  7.2G / 32G\r\n');
      term.write('\x1b[32mTEMP:\x1b[0m 48.3°C\r\n');
      term.write('\x1b[32mUP:\x1b[0m   14 days, 6:32:15\r\n\r\n');
      term.write('\x1b[33mServices:\x1b[0m\r\n');
      term.write('  pihole-FTL    \x1b[32mactive (running)\x1b[0m\r\n');
      term.write('  homebridge    \x1b[32mactive (running)\x1b[0m\r\n');
      term.write('  tailscaled    \x1b[32mactive (running)\x1b[0m\r\n');
    } else if (device.contains('shell-demo')) {
      term.write('\x1b[32miapdemo@$device\x1b[0m:\x1b[34m~\x1b[0m\$ neofetch\r\n');
      term.write('       \x1b[34m_,met\$\$\$\$\$gg.\x1b[0m           iapdemo@$device\r\n');
      term.write('    \x1b[34m,g\$\$\$\$\$\$\$\$\$\$\$\$\$\$p.\x1b[0m       \x1b[34mOS:\x1b[0m Debian GNU/Linux 12\r\n');
      term.write('  \x1b[34m,g\$\$P""\x1b[0m     \x1b[34m"""Y\$\$.".\x1b[0m    \x1b[34mKernel:\x1b[0m 6.1.0-18-cloud-amd64\r\n');
      term.write(' \x1b[34m,\$\$P\'\x1b[0m              \x1b[34m`\$\$\$.\x1b[0m  \x1b[34mUptime:\x1b[0m 23 days, 4:12\r\n');
      term.write(' \x1b[34m\'\$\$,\x1b[0m       \x1b[34m____\x1b[0m    \x1b[34m\$\$P\x1b[0m   \x1b[34mShell:\x1b[0m bash 5.2.15\r\n');
      term.write('  \x1b[34m`Y\$\$b,\x1b[0m           \x1b[34m,\$\$P\'\x1b[0m   \x1b[34mCPU:\x1b[0m AMD EPYC (2) @ 2.45GHz\r\n');
      term.write('   \x1b[34m`"Y\$\$\x1b[0m         \x1b[34m\$\$\'\x1b[0m     \x1b[34mMemory:\x1b[0m 142MiB / 1024MiB\r\n\r\n');
      term.write('\x1b[32miapdemo@$device\x1b[0m:\x1b[34m~\x1b[0m\$ ls\r\n');
      term.write('\x1b[34mDocuments\x1b[0m  \x1b[34mprojects\x1b[0m  \x1b[34m.ssh\x1b[0m  README.md  setup.sh\r\n\r\n');
      term.write('\x1b[32miapdemo@$device\x1b[0m:\x1b[34m~\x1b[0m\$ _\r\n');
    } else {
      term.write('\x1b[32miapdemo@$device\x1b[0m:\x1b[34m~\x1b[0m\$ uptime\r\n');
      term.write(' 10:15:42 up 14 days,  6:32,  1 user,  load average: 0.12, 0.08, 0.05\r\n\r\n');
      term.write('\x1b[32miapdemo@$device\x1b[0m:\x1b[34m~\x1b[0m\$ _\r\n');
    }
  }

  Future<void> _loadSettings() async {
    final storage = context.read<StorageService>();
    final theme = await storage.getSetting('theme');
    final fontSize = await storage.getSetting('font_size');
    final fontFamily = await storage.getSetting('font_family');
    if (mounted) {
      setState(() {
        _themeId = theme ?? 'default';
        _fontSize = double.tryParse(fontSize ?? '') ?? 14;
        _fontFamily = fontFamily ?? 'monospace';
      });
    }
  }

  static String _friendlyError(String error) {
    if (error.contains('Connection refused')) {
      return 'Connection refused \u2014 is the server running?';
    }
    if (error.contains('Connection timed out') || error.contains('timed out')) {
      return 'Connection timed out \u2014 check host and port';
    }
    if (error.contains('No route to host')) {
      return 'Host unreachable \u2014 check network connection';
    }
    if (error.contains('Authentication failed') ||
        error.contains('authentication')) {
      return 'Authentication failed \u2014 check credentials';
    }
    if (error.contains('Connection reset')) {
      return 'Connection reset by remote host';
    }
    return error;
  }

  void _handleDisconnect(String sessionId) {
    if (!mounted) return;
    final manager = context.read<SessionManager>();
    manager.disconnect(sessionId);
    if (manager.sessions.isEmpty) {
      Navigator.of(context).pop();
    } else if (manager.activeSession != null) {
      _switchToSession(manager.activeSession!);
    }
  }

  void _handleSessionEnded(String sessionId) {
    if (!mounted) return;
    setState(() {});
  }

  void _attachCurrentSession() {
    final manager = context.read<SessionManager>();
    final session = manager.activeSession;
    if (session == null) return;
    _switchToSession(session);
  }

  void _switchToSession(dynamic session) {
    _bridge.attach(session);
    session.terminal.onResize = (cols, rows, pixelWidth, pixelHeight) {
      _bridge.handleResize(cols, rows);
    };
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bridge.syncDimensions();
      session.startListening();
    });
  }

  /// Intercept soft keyboard output when Ctrl modifier is active.
  String _interceptCtrl(String data) {
    if (_ctrlActive && data.length == 1) {
      final code = data.codeUnitAt(0);
      if (code >= 0x40 && code <= 0x7e) {
        setState(() => _ctrlActive = false);
        return String.fromCharCode(code & 0x1f);
      }
    }
    return data;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _bridge.syncDimensions();
      _bridge.checkAlive();
      _loadSettings();
    }
  }

  xterm.TerminalTheme _buildXtermTheme() {
    final t = terminalThemes[_themeId] ?? terminalThemes['default']!;
    return xterm.TerminalTheme(
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
  }

  @override
  Widget build(BuildContext context) {
    final isDemoTerminal = DemoService().isActive && _connectingTerminal != null && !_connecting;
    return Scaffold(
      backgroundColor: bgDark,
      appBar: isDemoTerminal
          ? AppBar(
              backgroundColor: bgCard,
              title: Text(widget.pendingConnection?.label ?? 'Demo'),
            )
          : null,
      body: SafeArea(
        child: PrefixDrawer(
          onSend: (sequence) => _activeTerminal.textInput(sequence),
          child: Column(
            children: [
              if (_connecting || _connectError != null)
                _buildConnectingBar()
              else if (!isDemoTerminal)
                _buildSessionTabs(),
              if (_showSearch) _buildSearchBar(),
              Expanded(
                child: _buildTerminalView(),
              ),
              if (_showExtraKeys && !_connecting) _buildExtraKeys(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTerminalView() {
    final term = _connectingTerminal ?? context.read<SessionManager>().activeSession?.terminal;
    if (term == null) {
      return const Center(
        child: Text('No active session', style: TextStyle(color: Colors.white38)),
      );
    }
    return xterm.TerminalView(
      term,
      key: ValueKey(term.hashCode),
      controller: _termController,
      theme: _buildXtermTheme(),
      textStyle: xterm.TerminalStyle(
        fontSize: _fontSize,
        fontFamily: _fontFamily,
      ),
      autofocus: !_connecting,
      deleteDetection: true,
    );
  }

  Widget _buildConnectingBar() {
    return Container(
      color: bgCard,
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white54, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
          if (_connecting) ...[
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue),
            ),
            const SizedBox(width: 12),
            Text(
              'Connecting to ${widget.pendingConnection?.label ?? ""}...',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ] else if (_connectError != null) ...[
            const Icon(Icons.error_outline, color: Colors.red, size: 18),
            const SizedBox(width: 8),
            const Text(
              'Connection failed',
              style: TextStyle(color: Colors.red, fontSize: 14),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSessionTabs() {
    return Consumer<SessionManager>(
      builder: (context, manager, _) {
        if (manager.sessions.isEmpty) return const SizedBox.shrink();
        return Container(
          color: bgCard,
          height: 36,
          child: Row(
            children: [
              Expanded(
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: manager.sessions.length,
                  itemBuilder: (context, i) {
                    final session = manager.sessions[i];
                    final active = i == manager.activeIndex;
                    return GestureDetector(
                      onTap: () {
                        manager.switchTo(i);
                        _switchToSession(session);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: active ? bgDark : Colors.transparent,
                          border: Border(
                            bottom: BorderSide(
                              color:
                                  active ? Colors.blue : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              session.label,
                              style: TextStyle(
                                color:
                                    active ? Colors.white : Colors.white54,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () => _handleDisconnect(session.id),
                              child: const Icon(Icons.close,
                                  size: 14, color: Colors.white38),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (manager.activeSession != null &&
                  !manager.activeSession!.isMosh)
                IconButton(
                  icon: const Icon(
                    Icons.folder_outlined,
                    color: Colors.white54,
                    size: 18,
                  ),
                  onPressed: () {
                    final session = manager.activeSession;
                    if (session == null || session.targetClient == null) return;
                    final sftp = SftpService(session.targetClient!);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SftpView(
                          sftp: sftp,
                          title: session.label,
                        ),
                      ),
                    );
                  },
                ),
              IconButton(
                icon: Icon(
                  Icons.search,
                  color: _showSearch ? Colors.blue : Colors.white54,
                  size: 18,
                ),
                onPressed: () {
                  setState(() {
                    _showSearch = !_showSearch;
                    if (!_showSearch) _clearSearch();
                  });
                },
              ),
              IconButton(
                icon: Icon(
                  _showExtraKeys ? Icons.keyboard_hide : Icons.keyboard,
                  color: Colors.white54,
                  size: 18,
                ),
                onPressed: () =>
                    setState(() => _showExtraKeys = !_showExtraKeys),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: bgCard,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'Search...',
                hintStyle: TextStyle(color: Colors.white38),
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: InputBorder.none,
              ),
              onChanged: (_) => _performSearch(),
            ),
          ),
          Text(
            '${_searchHighlights.length}',
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54, size: 18),
            onPressed: () => setState(() {
              _showSearch = false;
              _clearSearch();
            }),
          ),
        ],
      ),
    );
  }

  void _performSearch() {
    _clearSearch();
    final query = _searchCtrl.text;
    if (query.isEmpty) {
      setState(() {});
      return;
    }

    final term = _activeTerminal;
    final buffer = term.buffer;
    for (var row = 0; row < buffer.lines.length; row++) {
      final line = buffer.lines[row];
      final text = line.getText();
      var idx = 0;
      while (true) {
        idx = text.indexOf(query, idx);
        if (idx < 0) break;
        final p1 = line.createAnchor(idx);
        final p2 = line.createAnchor(idx + query.length);
        final hl = _termController.highlight(
          p1: p1,
          p2: p2,
          color: const Color(0xFFFFDF5D),
        );
        _searchHighlights.add(hl);
        idx += query.length;
      }
    }
    setState(() {});
  }

  void _clearSearch() {
    for (final hl in _searchHighlights) {
      hl.dispose();
    }
    _searchHighlights.clear();
    _searchCtrl.clear();
  }

  Widget _buildExtraKeys() {
    return Container(
      color: bgCard,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _extraKey('Esc', '\x1b'),
            _extraKey('Tab', '\x09'),
            _extraKey('Ctrl', null, isModifier: true),
            _extraKey('|', '|'),
            _extraKey('/', '/'),
            _extraKey('-', '-'),
            _extraKey('_', '_'),
            _extraKey('~', '~'),
            _extraKey('.', '.'),
            _extraKey(':', ':'),
            _extraKey('@', '@'),
            _extraKey('#', '#'),
            _extraKey('\$', '\$'),
            _extraKey('\u2190', '\x1b[D'),
            _extraKey('\u2191', '\x1b[A'),
            _extraKey('\u2193', '\x1b[B'),
            _extraKey('\u2192', '\x1b[C'),
          ],
        ),
      ),
    );
  }

  Widget _extraKey(String label, String? sequence,
      {bool isModifier = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          if (isModifier) {
            setState(() => _ctrlActive = !_ctrlActive);
            return;
          }
          if (sequence != null) {
            final term = _activeTerminal;
            if (_ctrlActive && sequence.length == 1) {
              final code = sequence.codeUnitAt(0) & 0x1f;
              term.textInput(String.fromCharCode(code));
              setState(() => _ctrlActive = false);
            } else {
              term.textInput(sequence);
            }
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: (isModifier && _ctrlActive)
                ? Colors.blue.withValues(alpha: 0.3)
                : bgButton,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clearSearch();
    _searchCtrl.dispose();
    _termController.dispose();
    _bridge.dispose();
    super.dispose();
  }
}
