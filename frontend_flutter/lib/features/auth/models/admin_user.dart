class AdminUser {
  final String username;

  const AdminUser({required this.username});

  factory AdminUser.fromJson(Map<String, dynamic> json) {
    return AdminUser(
      username: json['username'] as String? ?? 'Admin',
    );
  }
}
