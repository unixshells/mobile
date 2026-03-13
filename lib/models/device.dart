class Device {
  final String name;
  final String addedAt;
  bool online;

  Device({
    required this.name,
    required this.addedAt,
    this.online = false,
  });

  factory Device.fromJson(Map<String, dynamic> m) => Device(
        name: m['device'] as String,
        addedAt: m['added_at'] as String? ?? '',
        online: m['online'] as bool? ?? false,
      );
}
