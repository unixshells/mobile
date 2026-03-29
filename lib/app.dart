import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'util/constants.dart';
import 'services/demo_service.dart';
import 'services/discovery_service.dart';
import 'services/key_service.dart';
import 'services/relay_api_service.dart';
import 'services/session_manager.dart';
import 'services/ssh_service.dart';
import 'services/storage_service.dart';
import 'views/home/home_view.dart';

class UnixShellsApp extends StatefulWidget {
  const UnixShellsApp({super.key});

  @override
  State<UnixShellsApp> createState() => _UnixShellsAppState();
}

class _UnixShellsAppState extends State<UnixShellsApp> {
  late final StorageService _storage;
  late final KeyService _keyService;
  late final SSHService _sshService;
  late final RelayApiService _api;
  late final DiscoveryService _discovery;

  @override
  void initState() {
    super.initState();
    _storage = StorageService();
    _keyService = KeyService(_storage);
    _sshService = SSHService(_keyService, _storage);
    _api = RelayApiService();
    _discovery = DiscoveryService(_api, _storage, _keyService);
    _initRelayApi();
    _discovery.start();
  }

  Future<void> _initRelayApi() async {
    // Clear demo account on restart — demo mode should not persist.
    final account = await _storage.getAccount();
    if (account != null && account.username == 'iapdemo') {
      await _storage.deleteAccount();
      DemoService().deactivate();
    }

    final host = await _storage.getSetting('relay_host');
    if (host != null && host.isNotEmpty) {
      _api = RelayApiService.fromHost(host: host);
    }
  }

  @override
  void dispose() {
    _discovery.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider.value(value: _storage),
        Provider.value(value: _keyService),
        Provider.value(value: _sshService),
        Provider.value(value: _api),
        ChangeNotifierProvider.value(value: _discovery),
        ChangeNotifierProvider(create: (_) => SessionManager(_sshService)),
      ],
      child: MaterialApp(
        title: 'Unix Shells',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: bgDark,
          colorScheme: const ColorScheme.dark(
            primary: accent,
            surface: bgCard,
            onPrimary: Color(0xFF0b0c10),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: bgSidebar,
            foregroundColor: textBright,
            elevation: 0,
            titleTextStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textBright),
          ),
          tabBarTheme: const TabBarThemeData(
            indicatorColor: accent,
            labelColor: textBright,
            unselectedLabelColor: textMuted,
            labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            unselectedLabelStyle: TextStyle(fontSize: 12),
          ),
          floatingActionButtonTheme: const FloatingActionButtonThemeData(
            backgroundColor: accent,
            foregroundColor: Color(0xFF0b0c10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
          ),
          dialogTheme: DialogThemeData(
            backgroundColor: bgCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            titleTextStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textBright),
            contentTextStyle: const TextStyle(fontSize: 13, color: textDim, height: 1.6),
          ),
          popupMenuTheme: PopupMenuThemeData(
            color: bgSurface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            textStyle: const TextStyle(fontSize: 13, color: textDim),
          ),
          snackBarTheme: SnackBarThemeData(
            backgroundColor: bgSurface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            contentTextStyle: const TextStyle(fontSize: 12, color: textBright),
          ),
          cardTheme: CardThemeData(
            color: bgCard,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          dividerColor: borderColor,
          useMaterial3: true,
        ),
        home: const HomeView(),
      ),
    );
  }
}
