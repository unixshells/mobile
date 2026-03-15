import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/account.dart';
import '../models/connection.dart';
import '../models/ssh_key.dart';

class StorageService {
  static const _secureStorage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
    aOptions: AndroidOptions(),
  );
  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    _db = await openDatabase(
      p.join(dir.path, 'unixshells.db'),
      version: 4,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
              'ALTER TABLE connections ADD COLUMN portForwards TEXT');
          await db.execute(
              'ALTER TABLE connections ADD COLUMN agentForwarding INTEGER NOT NULL DEFAULT 0');
        }
        if (oldVersion < 3) {
          await db.execute(
              'ALTER TABLE connections ADD COLUMN useMosh INTEGER NOT NULL DEFAULT 0');
        }
        if (oldVersion < 4) {
          await db.execute(
              'ALTER TABLE connections ADD COLUMN sessionName TEXT');
        }
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE connections (
            id TEXT PRIMARY KEY,
            label TEXT NOT NULL,
            type TEXT NOT NULL,
            host TEXT NOT NULL,
            port INTEGER NOT NULL DEFAULT 22,
            username TEXT NOT NULL DEFAULT '',
            authMethod TEXT NOT NULL DEFAULT 'key',
            keyId TEXT,
            passwordId TEXT,
            relayUsername TEXT,
            relayDevice TEXT,
            portForwards TEXT,
            agentForwarding INTEGER NOT NULL DEFAULT 0,
            useMosh INTEGER NOT NULL DEFAULT 0,
            sessionName TEXT,
            lastConnected INTEGER,
            sortOrder INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE keys (
            id TEXT PRIMARY KEY,
            label TEXT NOT NULL,
            publicKeyOpenSSH TEXT NOT NULL,
            algorithm TEXT NOT NULL DEFAULT 'ed25519',
            createdAt INTEGER NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

  // Connections.

  Future<List<Connection>> listConnections() async {
    final d = await db;
    final rows = await d.query('connections', orderBy: 'sortOrder, label');
    return rows.map((r) => Connection.fromMap(r)).toList();
  }

  Future<void> saveConnection(Connection c) async {
    final d = await db;
    await d.insert('connections', c.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> reorderConnections(List<Connection> conns) async {
    final d = await db;
    await d.transaction((txn) async {
      for (var i = 0; i < conns.length; i++) {
        await txn.update('connections', {'sortOrder': i},
            where: 'id = ?', whereArgs: [conns[i].id]);
      }
    });
  }

  Future<void> deleteConnection(String id) async {
    final d = await db;
    await d.delete('connections', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateLastConnected(String id) async {
    final d = await db;
    await d.update('connections',
        {'lastConnected': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?', whereArgs: [id]);
  }

  // SSH keys.

  Future<List<SSHKeyPair>> listKeys() async {
    final d = await db;
    final rows = await d.query('keys', orderBy: 'createdAt DESC');
    return rows.map((r) => SSHKeyPair.fromMap(r)).toList();
  }

  Future<void> saveKeyPair(SSHKeyPair key, String privateKeyPem) async {
    final d = await db;
    await d.insert('keys', key.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    await _secureStorage.write(key: 'privkey_${key.id}', value: privateKeyPem);
  }

  Future<String?> getPrivateKey(String keyId) async {
    return await _secureStorage.read(key: 'privkey_$keyId');
  }

  Future<void> deleteKey(String id) async {
    final d = await db;
    await d.delete('keys', where: 'id = ?', whereArgs: [id]);
    await _secureStorage.delete(key: 'privkey_$id');
  }

  // Passwords (stored in secure storage only).

  Future<void> savePassword(String id, String password) async {
    await _secureStorage.write(key: 'password_$id', value: password);
  }

  Future<String?> getPassword(String id) async {
    return await _secureStorage.read(key: 'password_$id');
  }

  Future<void> deletePassword(String id) async {
    await _secureStorage.delete(key: 'password_$id');
  }

  // Host key verification (TOFU).

  Future<void> saveHostKey(String host, int port, String fingerprint) async {
    await _secureStorage.write(
        key: 'hostkey_$host:$port', value: fingerprint);
  }

  Future<String?> getHostKey(String host, int port) async {
    return await _secureStorage.read(key: 'hostkey_$host:$port');
  }

  Future<void> deleteHostKey(String host, int port) async {
    await _secureStorage.delete(key: 'hostkey_$host:$port');
  }

  // Settings.

  Future<void> saveSetting(String key, String value) async {
    await _secureStorage.write(key: 'setting_$key', value: value);
  }

  Future<String?> getSetting(String key) async {
    return await _secureStorage.read(key: 'setting_$key');
  }

  // Device preferences (for discovered devices).

  Future<void> saveDevicePrefs(String username, String device, Map<String, dynamic> prefs) async {
    await _secureStorage.write(
        key: 'devicepref_$username:$device', value: jsonEncode(prefs));
  }

  Future<Map<String, dynamic>> getDevicePrefs(String username, String device) async {
    final raw = await _secureStorage.read(key: 'devicepref_$username:$device');
    if (raw == null) return {};
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  // Unix Shells account.

  Future<void> saveAccount(UnixShellsAccount account) async {
    await _secureStorage.write(
        key: 'unixshells_account', value: jsonEncode(account.toJson()));
  }

  Future<UnixShellsAccount?> getAccount() async {
    final raw = await _secureStorage.read(key: 'unixshells_account');
    if (raw == null) return null;
    return UnixShellsAccount.fromJson(jsonDecode(raw));
  }

  Future<void> deleteAccount() async {
    await _secureStorage.delete(key: 'unixshells_account');
  }

  // Export/import for cloud sync.

  Future<String> exportData() async {
    final connections = await listConnections();
    final keys = await listKeys();
    final privateKeys = <String, String>{};
    for (final key in keys) {
      final priv = await getPrivateKey(key.id);
      if (priv != null) privateKeys[key.id] = priv;
    }
    final account = await getAccount();
    final settings = <String, String>{};
    for (final k in ['relay_host', 'theme', 'font_size', 'font_family']) {
      final v = await getSetting(k);
      if (v != null) settings[k] = v;
    }
    return jsonEncode({
      'version': 2,
      'connections': connections.map((c) => c.toMap()).toList(),
      'keys': keys.map((k) => k.toMap()).toList(),
      'privateKeys': privateKeys,
      'account': account?.toJson(),
      'settings': settings,
    });
  }

  Future<void> importData(String json, {bool merge = false}) async {
    final data = jsonDecode(json) as Map<String, dynamic>;
    final d = await db;

    // In replace mode, clear existing data first.
    if (!merge) {
      await d.delete('connections');
      final existingKeys = await listKeys();
      for (final k in existingKeys) {
        await _secureStorage.delete(key: 'privkey_${k.id}');
      }
      await d.delete('keys');
    }

    // Import connections.
    final conns = data['connections'] as List?;
    if (conns != null) {
      for (final raw in conns) {
        final conn = Connection.fromMap(raw as Map<String, dynamic>);
        await d.insert('connections', conn.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }

    // Import keys.
    final keyList = data['keys'] as List?;
    final privKeys = data['privateKeys'] as Map<String, dynamic>?;
    if (keyList != null) {
      for (final raw in keyList) {
        final key = SSHKeyPair.fromMap(raw as Map<String, dynamic>);
        await d.insert('keys', key.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace);
        final priv = privKeys?[key.id] as String?;
        if (priv != null) {
          await _secureStorage.write(key: 'privkey_${key.id}', value: priv);
        }
      }
    }

    // Import account.
    final acct = data['account'] as Map<String, dynamic>?;
    if (acct != null) {
      await saveAccount(UnixShellsAccount.fromJson(acct));
    }

    // Import settings.
    final settings = data['settings'] as Map<String, dynamic>?;
    if (settings != null) {
      for (final entry in settings.entries) {
        await saveSetting(entry.key, entry.value as String);
      }
    }
  }
}
