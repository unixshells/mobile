import 'dart:convert';

enum ForwardType { local, remote }

class PortForward {
  final ForwardType type;
  final int localPort;
  final String remoteHost;
  final int remotePort;

  const PortForward({
    required this.type,
    required this.localPort,
    required this.remoteHost,
    required this.remotePort,
  });

  Map<String, dynamic> toMap() => {
        'type': type.name,
        'localPort': localPort,
        'remoteHost': remoteHost,
        'remotePort': remotePort,
      };

  factory PortForward.fromMap(Map<String, dynamic> m) => PortForward(
        type: ForwardType.values.byName(m['type'] as String),
        localPort: m['localPort'] as int,
        remoteHost: m['remoteHost'] as String,
        remotePort: m['remotePort'] as int,
      );

  static String encodeList(List<PortForward> list) =>
      jsonEncode(list.map((e) => e.toMap()).toList());

  static List<PortForward> decodeList(String? json) {
    if (json == null || json.isEmpty) return [];
    final list = jsonDecode(json) as List;
    return list
        .map((e) => PortForward.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  @override
  String toString() {
    if (type == ForwardType.local) {
      return 'L$localPort:$remoteHost:$remotePort';
    }
    return 'R$remotePort:$remoteHost:$localPort';
  }
}
