import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'util/constants.dart';
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
        ChangeNotifierProvider(create: (_) => SessionManager(_sshService, _api)),
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
        home: const HomeView(),
      ),
    );
  }
}
