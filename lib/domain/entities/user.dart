class AppUser {
  final int id;
  final String name;
  final String email;
  final String? avatarPath;
  final String securityQuestion;
  final DateTime createdAt;

  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    this.avatarPath,
    required this.securityQuestion,
    required this.createdAt,
  });

  AppUser copyWith({String? name, String? email, String? avatarPath}) =>
      AppUser(
        id: id,
        name: name ?? this.name,
        email: email ?? this.email,
        avatarPath: avatarPath ?? this.avatarPath,
        securityQuestion: securityQuestion,
        createdAt: createdAt,
      );
}
