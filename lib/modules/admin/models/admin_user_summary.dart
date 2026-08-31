class AdminUserSummary {
  const AdminUserSummary({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    required this.status,
    this.createdAt,
  });

  factory AdminUserSummary.fromMap(Map<String, dynamic> map) {
    return AdminUserSummary(
      id: map['id'] as String,
      fullName: (map['full_name'] as String?)?.trim().isNotEmpty == true
          ? map['full_name'] as String
          : 'Unnamed user',
      email: (map['email'] as String?) ?? '-',
      role: (map['role'] as String?) ?? 'driver',
      status: (map['status'] as String?) ?? 'active',
      createdAt: map['created_at'] == null
          ? null
          : DateTime.tryParse(map['created_at'] as String),
    );
  }

  final String id;
  final String fullName;
  final String email;
  final String role;
  final String status;
  final DateTime? createdAt;

  bool get isActive => status == 'active';
  bool get isAdmin => role == 'admin';
}
