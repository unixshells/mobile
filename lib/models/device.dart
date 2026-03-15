class Device {
  final String name;
  final String addedAt;
  final String status;
  bool online;

  Device({
    required this.name,
    this.addedAt = '',
    this.status = '',
    this.online = false,
  });

  factory Device.fromJson(Map<String, dynamic> m) => Device(
        name: m['device'] as String,
        addedAt: m['added_at'] as String? ?? '',
        status: m['status'] as String? ?? '',
        online: m['online'] as bool? ?? (m['status'] == 'online'),
      );
}
