class UnixShellsAccount {
  final String username;
  final String email;
  final String subscriptionStatus;

  UnixShellsAccount({
    required this.username,
    required this.email,
    this.subscriptionStatus = '',
  });

  Map<String, dynamic> toJson() => {
        'username': username,
        'email': email,
        'subscriptionStatus': subscriptionStatus,
      };

  factory UnixShellsAccount.fromJson(Map<String, dynamic> m) =>
      UnixShellsAccount(
        username: m['username'] as String,
        email: m['email'] as String,
        subscriptionStatus: m['subscriptionStatus'] as String? ?? '',
      );

  bool get isActive => subscriptionStatus == 'active';
}
