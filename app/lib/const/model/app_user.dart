/// profiles 테이블 (supabase/01_schema.sql)
class Profile {
  final String id;
  final String role; // 'user' | 'admin'
  final String displayName;
  final DateTime createdAt;

  const Profile({
    required this.id,
    this.role = 'user',
    required this.displayName,
    required this.createdAt,
  });

  bool get isAdmin => role == 'admin';

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
        id: m['id'] as String,
        role: m['role'] as String? ?? 'user',
        displayName: m['display_name'] as String? ?? '',
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
      );
}
