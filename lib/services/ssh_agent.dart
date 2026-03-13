import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

// SSH agent protocol constants.
const _agentcRequestIdentities = 11;
const _agentIdentitiesAnswer = 12;
const _agentcSignRequest = 13;
const _agentSignResponse = 14;
const _agentFailure = 5;

/// Handles SSH agent protocol messages on an agent-forwarded channel.
/// Responds to identity requests and sign requests using the provided keys.
class SSHAgentHandler {
  final List<SSHKeyPair> identities;
  int _signCount = 0;
  DateTime _windowStart = DateTime.now();
  static const _maxSignsPerMinute = 60;

  SSHAgentHandler(this.identities);

  /// Attach to an SSH channel opened by the server for agent forwarding.
  void handle(SSHChannel channel) {
    final buffer = BytesBuilder(copy: false);
    channel.stream.listen((data) {
      buffer.add(data.bytes);
      _processBuffer(buffer, channel);
    });
  }

  void _processBuffer(BytesBuilder buffer, SSHChannel channel) {
    while (true) {
      final bytes = buffer.takeBytes();
      if (bytes.length < 5) {
        buffer.add(bytes);
        return;
      }

      // Agent message format: [length:4][type:1][payload]
      final view = ByteData.sublistView(bytes);
      final msgLen = view.getUint32(0);
      if (bytes.length < 4 + msgLen) {
        buffer.add(bytes);
        return;
      }

      final type = bytes[4];
      final payload =
          msgLen > 1 ? Uint8List.sublistView(bytes, 5, 4 + msgLen) : null;

      _handleMessage(type, payload, channel);

      // Put remaining bytes back.
      if (bytes.length > 4 + msgLen) {
        buffer.add(Uint8List.sublistView(bytes, 4 + msgLen));
      }
    }
  }

  void _handleMessage(int type, Uint8List? payload, SSHChannel channel) {
    switch (type) {
      case _agentcRequestIdentities:
        _handleRequestIdentities(channel);
      case _agentcSignRequest:
        if (payload != null) {
          _handleSignRequest(payload, channel);
        } else {
          _sendFailure(channel);
        }
      default:
        _sendFailure(channel);
    }
  }

  void _handleRequestIdentities(SSHChannel channel) {
    // Build response: [count:4] + for each: [key_blob_len:4][key_blob][comment_len:4][comment]
    final out = BytesBuilder();

    // Message type.
    out.addByte(_agentIdentitiesAnswer);

    // Number of identities.
    _writeUint32(out, identities.length);

    for (final id in identities) {
      final pubKey = id.toPublicKey();
      final keyBlob = pubKey.encode();
      _writeBytes(out, keyBlob);
      _writeString(out, id.type);
    }

    _sendMessage(channel, out.takeBytes());
  }

  void _handleSignRequest(Uint8List payload, SSHChannel channel) {
    // Rate limit sign requests.
    final now = DateTime.now();
    if (now.difference(_windowStart).inMinutes >= 1) {
      _signCount = 0;
      _windowStart = now;
    }
    _signCount++;
    if (_signCount > _maxSignsPerMinute) {
      _sendFailure(channel);
      return;
    }

    // Parse: [key_blob_len:4][key_blob][data_len:4][data][flags:4]
    var offset = 0;

    final keyBlobLen = _readUint32(payload, offset);
    offset += 4;
    final keyBlob = Uint8List.sublistView(payload, offset, offset + keyBlobLen);
    offset += keyBlobLen;

    final dataLen = _readUint32(payload, offset);
    offset += 4;
    final data = Uint8List.sublistView(payload, offset, offset + dataLen);
    offset += dataLen;

    // Find matching identity.
    SSHKeyPair? matchingKey;
    for (final id in identities) {
      final pubKey = id.toPublicKey();
      final encoded = pubKey.encode();
      if (_bytesEqual(encoded, keyBlob)) {
        matchingKey = id;
        break;
      }
    }

    if (matchingKey == null) {
      _sendFailure(channel);
      return;
    }

    // Sign the data.
    final signature = matchingKey.sign(data);
    final sigBytes = signature.encode();

    // Build response.
    final out = BytesBuilder();
    out.addByte(_agentSignResponse);
    _writeBytes(out, sigBytes);

    _sendMessage(channel, out.takeBytes());
  }

  void _sendFailure(SSHChannel channel) {
    _sendMessage(channel, Uint8List.fromList([_agentFailure]));
  }

  void _sendMessage(SSHChannel channel, Uint8List data) {
    final msg = Uint8List(4 + data.length);
    final view = ByteData.sublistView(msg);
    view.setUint32(0, data.length);
    msg.setRange(4, 4 + data.length, data);
    channel.addData(msg);
  }

  void _writeUint32(BytesBuilder out, int value) {
    final bytes = Uint8List(4);
    ByteData.sublistView(bytes).setUint32(0, value);
    out.add(bytes);
  }

  void _writeBytes(BytesBuilder out, Uint8List data) {
    _writeUint32(out, data.length);
    out.add(data);
  }

  void _writeString(BytesBuilder out, String s) {
    final bytes = Uint8List.fromList(s.codeUnits);
    _writeBytes(out, bytes);
  }

  int _readUint32(Uint8List data, int offset) {
    return ByteData.sublistView(data).getUint32(offset);
  }

  bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
