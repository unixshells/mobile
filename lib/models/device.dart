class DeviceSession {
  final String name;
  final String status;
  final String title;

  DeviceSession({required this.name, this.status = '', this.title = ''});

  factory DeviceSession.fromJson(Map<String, dynamic> m) => DeviceSession(
        name: m['name'] as String,
        status: m['status'] as String? ?? '',
        title: m['title'] as String? ?? '',
      );
}

class Device {
  final String name;
  final String addedAt;
  final String status;
  bool online;
  final List<DeviceSession> sessions;

  Device({
    required this.name,
    this.addedAt = '',
    this.status = '',
    this.online = false,
    this.sessions = const [],
  });

  factory Device.fromJson(Map<String, dynamic> m) => Device(
        name: m['device'] as String,
        addedAt: m['added_at'] as String? ?? '',
        status: m['status'] as String? ?? '',
        online: m['online'] as bool? ?? (m['status'] == 'online'),
        sessions: (m['sessions'] as List?)
                ?.map((s) =>
                    DeviceSession.fromJson(s as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}
