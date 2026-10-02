/// The signed-in FitFlow account, as returned by the API (`/api/me`).
class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    this.displayName,
    this.photoUrl,
  });

  /// Stable account id; scopes synced data on this device.
  final String id;
  final String email;
  final String? displayName;
  final String? photoUrl;

  /// Parses the API's `{id, email, name, photoUrl}` profile.
  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['id'] as String,
    email: json['email'] as String,
    displayName: json['name'] as String?,
    photoUrl: json['photoUrl'] as String?,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'email': email,
    'name': displayName,
    'photoUrl': photoUrl,
  };

  @override
  bool operator ==(Object other) =>
      other is AppUser &&
      other.id == id &&
      other.email == email &&
      other.displayName == displayName &&
      other.photoUrl == photoUrl;

  @override
  int get hashCode => Object.hash(id, email, displayName, photoUrl);
}
