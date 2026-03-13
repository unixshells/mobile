class SSHKeyPair {
  final String id;
  String label;
  final String publicKeyOpenSSH;
  final String algorithm;
  final int createdAt;

  SSHKeyPair({
    required this.id,
    required this.label,
    required this.publicKeyOpenSSH,
    this.algorithm = 'ed25519',
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'publicKeyOpenSSH': publicKeyOpenSSH,
        'algorithm': algorithm,
        'createdAt': createdAt,
      };

  factory SSHKeyPair.fromMap(Map<String, dynamic> m) => SSHKeyPair(
        id: m['id'] as String,
        label: m['label'] as String,
        publicKeyOpenSSH: m['publicKeyOpenSSH'] as String,
        algorithm: m['algorithm'] as String? ?? 'ed25519',
        createdAt: m['createdAt'] as int,
      );

  String get fingerprint {
    final parts = publicKeyOpenSSH.split(' ');
    if (parts.length >= 2) {
      final b64 = parts[1];
      final truncated = b64.length > 12 ? b64.substring(0, 12) : b64;
      return 'SHA256:$truncated...';
    }
    if (publicKeyOpenSSH.length > 20) {
      return publicKeyOpenSSH.substring(0, 20);
    }
    return publicKeyOpenSSH;
  }
}
