import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../../services/sftp_service.dart';
import '../../util/constants.dart';

class SftpView extends StatefulWidget {
  final SftpService sftp;
  final String title;

  const SftpView({super.key, required this.sftp, required this.title});

  @override
  State<SftpView> createState() => _SftpViewState();
}

class _SftpViewState extends State<SftpView> {
  String _currentPath = '/';
  List<SftpName> _entries = [];
  bool _loading = true;
  String? _error;
  final _selectedPaths = <String>{};
  bool _selectMode = false;
  bool _isDragOver = false;
  StreamSubscription<List<SharedMediaFile>>? _shareSub;

  @override
  void initState() {
    super.initState();
    _resolveHomeAndList();
    _listenForSharedFiles();
  }

  void _listenForSharedFiles() {
    _shareSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      (files) {
        if (files.isNotEmpty) _uploadSharedFiles(files);
      },
    );
    // Handle files shared while app was closed.
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      if (files.isNotEmpty) _uploadSharedFiles(files);
    });
  }

  Future<void> _uploadSharedFiles(List<SharedMediaFile> sharedFiles) async {
    final messenger = ScaffoldMessenger.of(context);
    var count = 0;
    for (final shared in sharedFiles) {
      final file = File(shared.path);
      if (!await file.exists()) continue;
      final filename = p.basename(shared.path);
      final bytes = await file.readAsBytes();
      final remotePath = p.join(_currentPath, filename);
      try {
        messenger.showSnackBar(
          SnackBar(content: Text('Uploading $filename...')),
        );
        await widget.sftp.writeFile(remotePath, Uint8List.fromList(bytes));
        count++;
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text('Upload failed: $filename — $e')),
        );
      }
    }
    if (count > 0) {
      messenger.showSnackBar(
        SnackBar(content: Text('Uploaded $count file(s)')),
      );
      await _listDir(_currentPath);
    }
  }

  Future<void> _resolveHomeAndList() async {
    try {
      final home = await widget.sftp.absolute('.');
      _currentPath = home;
    } catch (_) {
      _currentPath = '/';
    }
    await _listDir(_currentPath);
  }

  Future<void> _listDir(String path) async {
    setState(() {
      _loading = true;
      _error = null;
      _selectedPaths.clear();
      _selectMode = false;
    });
    try {
      final resolved = await widget.sftp.absolute(path);
      final entries = await widget.sftp.listDirectory(resolved);
      entries.removeWhere((e) => e.filename == '.' || e.filename == '..');
      entries.sort((a, b) {
        final aDir = _isDir(a);
        final bDir = _isDir(b);
        if (aDir != bDir) return aDir ? -1 : 1;
        return a.filename.toLowerCase().compareTo(b.filename.toLowerCase());
      });
      setState(() {
        _currentPath = resolved;
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  bool _isDir(SftpName entry) {
    final mode = entry.attr.mode;
    if (mode == null) return false;
    return (mode.value & 0x4000) != 0;
  }

  bool _isLink(SftpName entry) {
    final mode = entry.attr.mode;
    if (mode == null) return false;
    return (mode.value & 0xA000) == 0xA000;
  }

  String _formatSize(int? size) {
    if (size == null) return '';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatPermissions(SftpFileMode? mode) {
    if (mode == null) return '';
    final perms = mode.value & 0x1FF;
    final buf = StringBuffer();
    const letters = 'rwxrwxrwx';
    for (var i = 8; i >= 0; i--) {
      buf.write((perms & (1 << i)) != 0 ? letters[8 - i] : '-');
    }
    return buf.toString();
  }

  Future<void> _navigate(SftpName entry) async {
    if (_selectMode) {
      _toggleSelect(entry);
      return;
    }
    final entryPath = p.join(_currentPath, entry.filename);
    if (_isLink(entry)) {
      // Resolve symlink target and navigate if it's a directory.
      try {
        final target = await widget.sftp.readlink(entryPath);
        final resolvedPath = p.isAbsolute(target) ? target : p.join(_currentPath, target);
        final stat = await widget.sftp.stat(resolvedPath);
        if ((stat.mode?.value ?? 0) & 0x4000 != 0) {
          await _listDir(resolvedPath);
        }
      } catch (_) {
        // Broken symlink or permission error — ignore.
      }
      return;
    }
    if (_isDir(entry)) {
      await _listDir(entryPath);
    }
  }

  Future<void> _navigateUp() async {
    if (_currentPath == '/') return;
    await _listDir(p.dirname(_currentPath));
  }

  void _toggleSelect(SftpName entry) {
    final path = p.join(_currentPath, entry.filename);
    setState(() {
      if (_selectedPaths.contains(path)) {
        _selectedPaths.remove(path);
        if (_selectedPaths.isEmpty) _selectMode = false;
      } else {
        _selectedPaths.add(path);
      }
    });
  }

  Future<void> _downloadFile(String remotePath, String filename) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      messenger.showSnackBar(
        SnackBar(content: Text('Downloading $filename...')),
      );
      final data = await widget.sftp.readFile(remotePath);
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Save $filename',
        fileName: filename,
        bytes: data,
      );
      if (result != null) {
        messenger.showSnackBar(
          SnackBar(content: Text('Saved $filename')),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Download failed: $e')),
      );
    }
  }

  Future<void> _uploadFiles() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      for (final file in result.files) {
        if (file.bytes == null || file.name.isEmpty) continue;
        final remotePath = p.join(_currentPath, file.name);
        messenger.showSnackBar(
          SnackBar(content: Text('Uploading ${file.name}...')),
        );
        await widget.sftp.writeFile(remotePath, file.bytes!);
      }
      messenger.showSnackBar(
        SnackBar(
            content: Text('Uploaded ${result.files.length} file(s)')),
      );
      await _listDir(_currentPath);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Upload failed: $e')),
      );
    }
  }

  Future<void> _createDirectory() async {
    final messenger = ScaffoldMessenger.of(context);
    final name = await _showInputDialog('New Folder', 'Folder name');
    if (name == null || name.isEmpty) return;
    try {
      await widget.sftp.mkdir(p.join(_currentPath, name));
      await _listDir(_currentPath);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to create folder: $e')),
      );
    }
  }

  Future<void> _renameEntry(SftpName entry) async {
    final messenger = ScaffoldMessenger.of(context);
    final name =
        await _showInputDialog('Rename', 'New name', initial: entry.filename);
    if (name == null || name.isEmpty || name == entry.filename) return;
    try {
      await widget.sftp.rename(
        p.join(_currentPath, entry.filename),
        p.join(_currentPath, name),
      );
      await _listDir(_currentPath);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Rename failed: $e')),
      );
    }
  }

  Future<void> _deleteEntry(SftpName entry) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgCard,
        title: const Text('Delete', style: TextStyle(color: Colors.white)),
        content: Text('Delete "${entry.filename}"?',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final fullPath = p.join(_currentPath, entry.filename);
      if (_isDir(entry)) {
        await widget.sftp.rmdir(fullPath);
      } else {
        await widget.sftp.remove(fullPath);
      }
      await _listDir(_currentPath);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }

  Future<void> _deleteSelected() async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgCard,
        title: const Text('Delete', style: TextStyle(color: Colors.white)),
        content: Text('Delete ${_selectedPaths.length} item(s)?',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      for (final path in _selectedPaths) {
        try {
          final stat = await widget.sftp.stat(path);
          if (stat.mode != null && (stat.mode!.value & 0x4000) != 0) {
            await widget.sftp.rmdir(path);
          } else {
            await widget.sftp.remove(path);
          }
        } catch (_) {}
      }
      await _listDir(_currentPath);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }

  Future<String?> _showInputDialog(String title, String hint,
      {String? initial}) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgCard,
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showEntryActions(SftpName entry) {
    final isDir = _isDir(entry);
    showModalBottomSheet(
      context: context,
      backgroundColor: bgCard,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline, color: Colors.white70),
              title: Text(entry.filename,
                  style: const TextStyle(color: Colors.white)),
              subtitle: Text(
                '${_formatPermissions(entry.attr.mode)}  ${_formatSize(entry.attr.size)}',
                style: const TextStyle(color: Colors.white38),
              ),
            ),
            const Divider(color: Colors.white12),
            if (!isDir)
              ListTile(
                leading:
                    const Icon(Icons.download_outlined, color: Colors.white70),
                title: const Text('Download',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  _downloadFile(
                      p.join(_currentPath, entry.filename), entry.filename);
                },
              ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline,
                  color: Colors.white70),
              title:
                  const Text('Rename', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _renameEntry(entry);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title:
                  const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _deleteEntry(entry);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgDark,
      appBar: AppBar(
        backgroundColor: bgCard,
        foregroundColor: Colors.white,
        title: _selectMode
            ? Text('${_selectedPaths.length} selected')
            : Text(widget.title),
        leading: _selectMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  _selectMode = false;
                  _selectedPaths.clear();
                }),
              )
            : null,
        actions: _selectMode
            ? [
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: _deleteSelected,
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.create_new_folder_outlined),
                  onPressed: _createDirectory,
                ),
                IconButton(
                  icon: const Icon(Icons.upload_file_outlined),
                  onPressed: _uploadFiles,
                ),
              ],
      ),
      body: _buildDropTarget(
        child: Column(
          children: [
            _buildPathBar(),
            Expanded(child: _buildBody()),
            if (_isDragOver)
              Container(
                color: Colors.blue.withValues(alpha: 0.15),
                padding: const EdgeInsets.all(24),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.file_upload, color: Colors.blue, size: 32),
                    SizedBox(width: 12),
                    Text('Drop files to upload',
                        style: TextStyle(color: Colors.blue, fontSize: 16)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropTarget({required Widget child}) {
    return DragTarget<Object>(
      onWillAcceptWithDetails: (_) {
        setState(() => _isDragOver = true);
        return true;
      },
      onLeave: (_) => setState(() => _isDragOver = false),
      onAcceptWithDetails: (details) async {
        setState(() => _isDragOver = false);
        final data = details.data;
        if (data is String) {
          // Handle dropped file path (iPadOS/Android tablet).
          final file = File(data);
          if (await file.exists()) {
            await _uploadLocalFile(file);
          }
        }
      },
      builder: (context, candidateData, rejectedData) => child,
    );
  }

  Future<void> _uploadLocalFile(File file) async {
    final messenger = ScaffoldMessenger.of(context);
    final filename = p.basename(file.path);
    try {
      messenger.showSnackBar(
        SnackBar(content: Text('Uploading $filename...')),
      );
      final bytes = await file.readAsBytes();
      await widget.sftp
          .writeFile(p.join(_currentPath, filename), Uint8List.fromList(bytes));
      messenger.showSnackBar(
        SnackBar(content: Text('Uploaded $filename')),
      );
      await _listDir(_currentPath);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Upload failed: $e')),
      );
    }
  }

  Widget _buildPathBar() {
    return Container(
      color: bgCard,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          if (_currentPath != '/')
            GestureDetector(
              onTap: _navigateUp,
              child: const Icon(Icons.arrow_upward,
                  size: 20, color: Colors.white54),
            ),
          if (_currentPath != '/') const SizedBox(width: 8),
          Expanded(
            child: Text(
              _currentPath,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 13, fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: () => _listDir(_currentPath),
            child:
                const Icon(Icons.refresh, size: 20, color: Colors.white54),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(_error!,
                  style: const TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _listDir(_currentPath),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_entries.isEmpty) {
      return const Center(
        child: Text('Empty directory',
            style: TextStyle(color: Colors.white38, fontSize: 16)),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _listDir(_currentPath),
      child: ListView.builder(
        itemCount: _entries.length,
        itemBuilder: (context, i) => _buildEntry(_entries[i]),
      ),
    );
  }

  Widget _buildEntry(SftpName entry) {
    final isDir = _isDir(entry);
    final isLink = _isLink(entry);
    final fullPath = p.join(_currentPath, entry.filename);
    final selected = _selectedPaths.contains(fullPath);

    IconData icon;
    Color iconColor;
    if (isDir) {
      icon = Icons.folder;
      iconColor = Colors.blue;
    } else if (isLink) {
      icon = Icons.link;
      iconColor = Colors.cyan;
    } else {
      icon = _fileIcon(entry.filename);
      iconColor = Colors.white54;
    }

    return ListTile(
      leading: _selectMode
          ? Checkbox(
              value: selected,
              onChanged: (_) => _toggleSelect(entry),
              activeColor: Colors.blue,
              checkColor: Colors.white,
              side: const BorderSide(color: Colors.white38),
            )
          : Icon(icon, color: iconColor),
      title: Text(
        entry.filename,
        style: TextStyle(
          color: isLink ? Colors.cyan : Colors.white,
          fontSize: 14,
        ),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        isDir
            ? _formatPermissions(entry.attr.mode)
            : '${_formatSize(entry.attr.size)}  ${_formatPermissions(entry.attr.mode)}',
        style: const TextStyle(color: Colors.white38, fontSize: 12),
      ),
      trailing: !_selectMode
          ? GestureDetector(
              onTap: () => _showEntryActions(entry),
              child:
                  const Icon(Icons.more_vert, size: 20, color: Colors.white38),
            )
          : null,
      onTap: () => _navigate(entry),
      onLongPress: () {
        if (!_selectMode) {
          setState(() => _selectMode = true);
        }
        _toggleSelect(entry);
      },
    );
  }

  IconData _fileIcon(String filename) {
    final ext = p.extension(filename).toLowerCase();
    switch (ext) {
      case '.txt':
      case '.md':
      case '.log':
        return Icons.description;
      case '.jpg':
      case '.jpeg':
      case '.png':
      case '.gif':
      case '.bmp':
      case '.svg':
        return Icons.image;
      case '.mp4':
      case '.avi':
      case '.mkv':
      case '.mov':
        return Icons.video_file;
      case '.mp3':
      case '.wav':
      case '.flac':
      case '.aac':
        return Icons.audio_file;
      case '.zip':
      case '.tar':
      case '.gz':
      case '.bz2':
      case '.xz':
      case '.7z':
        return Icons.archive;
      case '.pdf':
        return Icons.picture_as_pdf;
      case '.dart':
      case '.py':
      case '.js':
      case '.ts':
      case '.go':
      case '.rs':
      case '.c':
      case '.cpp':
      case '.h':
      case '.java':
      case '.sh':
      case '.yaml':
      case '.yml':
      case '.json':
      case '.xml':
      case '.toml':
      case '.conf':
        return Icons.code;
      default:
        return Icons.insert_drive_file;
    }
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    super.dispose();
  }
}
