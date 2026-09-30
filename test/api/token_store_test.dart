import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prm/data/api/token_store.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('SecureTokenStore round-trips and clears the session', () async {
    final store = SecureTokenStore();
    expect(await store.read(), isNull);

    await store.write(
      const ApiTokens(accessToken: 'access', refreshToken: 'refresh'),
    );
    final tokens = await store.read();
    expect(tokens?.accessToken, 'access');
    expect(tokens?.refreshToken, 'refresh');

    await store.clear();
    expect(await store.read(), isNull);
  });

  test('a half-written session counts as none', () async {
    FlutterSecureStorage.setMockInitialValues({'api_access_token': 'a'});
    expect(await SecureTokenStore().read(), isNull);
  });
}
