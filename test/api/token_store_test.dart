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

  test('a corrupt stored session counts as none', () async {
    FlutterSecureStorage.setMockInitialValues({
      'api_session': '{"accessToken":1',
    });
    expect(await SecureTokenStore().read(), isNull);
    FlutterSecureStorage.setMockInitialValues({
      'api_session': '{"accessToken":"a"}',
    });
    expect(await SecureTokenStore().read(), isNull);
  });

  test('stores both tokens together under one key', () async {
    final storage = const FlutterSecureStorage();
    await SecureTokenStore(storage)
        .write(const ApiTokens(accessToken: 'a', refreshToken: 'r'));
    expect((await storage.readAll()).keys, ['api_session']);
    // A fresh store (next launch) reads the same session back.
    expect((await SecureTokenStore(storage).read())?.refreshToken, 'r');
  });

  test('serves reads from memory after the first one', () async {
    final storage = const FlutterSecureStorage();
    final store = SecureTokenStore(storage);
    await store.write(const ApiTokens(accessToken: 'a', refreshToken: 'r'));
    await storage.deleteAll();
    expect((await store.read())?.accessToken, 'a');
  });
}
