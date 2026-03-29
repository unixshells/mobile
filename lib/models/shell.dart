class Shell {
  final String id;
  final String username;
  final String plan;
  final int memMb;
  final int vcpus;
  final int diskGb;
  final String state;
  final String createdAt;
  final String stripeSubId;
  final String previewUrl;

  Shell({
    required this.id,
    this.username = '',
    this.plan = '',
    this.memMb = 0,
    this.vcpus = 0,
    this.diskGb = 0,
    this.state = '',
    this.createdAt = '',
    this.stripeSubId = '',
    this.previewUrl = '',
  });

  factory Shell.fromJson(Map<String, dynamic> m) => Shell(
        id: m['id'] as String? ?? '',
        username: m['username'] as String? ?? '',
        plan: m['plan'] as String? ?? '',
        memMb: m['mem_mb'] as int? ?? 0,
        vcpus: m['vcpus'] as int? ?? 0,
        diskGb: m['disk_gb'] as int? ?? 0,
        state: m['state'] as String? ?? '',
        createdAt: m['created_at'] as String? ?? '',
        stripeSubId: m['stripe_sub_id'] as String? ?? '',
        previewUrl: m['preview_url'] as String? ?? '',
      );

  String get specs => '${memMb}MB / ${vcpus}vCPU / ${diskGb}GB';

  bool get isRunning => state == 'running';

  bool get isStripe => stripeSubId.isNotEmpty;
}
