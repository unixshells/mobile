import '../models/account.dart';
import '../models/device.dart';

/// Provides mock data when demo mode is active.
/// Activated by signing in with username "iapdemo".
class DemoService {
  static final DemoService _instance = DemoService._();
  factory DemoService() => _instance;
  DemoService._();

  bool _active = false;

  bool get isActive => _active;

  void activate() => _active = true;
  void deactivate() => _active = false;

  UnixShellsAccount get account => UnixShellsAccount(
        username: 'iapdemo',
        email: 'iapdemo@unixshells.com',
        subscriptionStatus: 'active',
      );

  List<Device> get devices => [
        Device(
          name: 'workstation',
          addedAt: '2025-11-14',
          status: 'online',
          online: true,
          sessions: [
            DeviceSession(name: 'default', status: 'alive', title: 'htop'),
            DeviceSession(name: 'dev', status: 'alive', title: 'vim ~/project/main.go'),
          ],
        ),
        Device(
          name: 'prod-server',
          addedAt: '2025-12-02',
          status: 'online',
          online: true,
          sessions: [
            DeviceSession(name: 'default', status: 'alive', title: 'tail -f /var/log/nginx/access.log'),
          ],
        ),
        Device(
          name: 'raspberry-pi',
          addedAt: '2026-01-18',
          status: 'online',
          online: true,
          sessions: [
            DeviceSession(name: 'default', status: 'alive', title: 'monitoring'),
          ],
        ),
      ];

}
