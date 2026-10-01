import 'package:flutter_test/flutter_test.dart';
import 'package:prm/domain/models/app_user.dart';

void main() {
  test('parses the API profile and round-trips through JSON', () {
    final user = AppUser.fromJson({
      'id': '6710a1b2c3d4e5f601234567',
      'email': 'athlete@example.com',
      'name': 'Athlete',
      'photoUrl': null,
    });
    expect(user.displayName, 'Athlete');
    expect(user.photoUrl, isNull);
    expect(AppUser.fromJson(user.toJson()), user);
  });
}
