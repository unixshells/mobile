import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

/// Lightweight wrapper around dartssh2's SftpClient.
class SftpService {
  final SSHClient _client;
  SftpClient? _sftp;

  SftpService(this._client);

  Future<SftpClient> _open() async {
    _sftp ??= await _client.sftp();
    return _sftp!;
  }

  Future<List<SftpName>> listDirectory(String path) async {
    final sftp = await _open();
    return await sftp.listdir(path);
  }

  Future<SftpFileAttrs> stat(String path) async {
    final sftp = await _open();
    return await sftp.stat(path);
  }

  Future<String> absolute(String path) async {
    final sftp = await _open();
    return await sftp.absolute(path);
  }

  Future<Uint8List> readFile(String path) async {
    final sftp = await _open();
    final file = await sftp.open(path);
    try {
      return await file.readBytes();
    } finally {
      await file.close();
    }
  }

  Future<void> writeFile(String path, Uint8List data) async {
    final sftp = await _open();
    final file = await sftp.open(path,
        mode: SftpFileOpenMode.create |
            SftpFileOpenMode.truncate |
            SftpFileOpenMode.write);
    try {
      await file.writeBytes(data);
    } finally {
      await file.close();
    }
  }

  Future<void> mkdir(String path) async {
    final sftp = await _open();
    await sftp.mkdir(path);
  }

  Future<void> remove(String path) async {
    final sftp = await _open();
    await sftp.remove(path);
  }

  Future<void> rmdir(String path) async {
    final sftp = await _open();
    await sftp.rmdir(path);
  }

  Future<void> rename(String oldPath, String newPath) async {
    final sftp = await _open();
    await sftp.rename(oldPath, newPath);
  }

  Future<String> readlink(String path) async {
    final sftp = await _open();
    return await sftp.readlink(path);
  }

  void close() {
    _sftp?.close();
    _sftp = null;
  }
}
