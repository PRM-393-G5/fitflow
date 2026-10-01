import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prm/data/api/api_config.dart';

void main() {
  Uri resolve({
    String dartDefine = '',
    String? dotenvValue,
    TargetPlatform platform = TargetPlatform.android,
    bool isWeb = false,
  }) => ApiConfig.resolve(
    dartDefine: dartDefine,
    dotenvValue: dotenvValue,
    platform: platform,
    isWeb: isWeb,
  );

  test('defaults to the host machine as seen from the platform', () {
    expect(resolve().toString(), 'http://10.0.2.2:3001/api/');
    expect(
      resolve(platform: TargetPlatform.iOS).toString(),
      'http://localhost:3001/api/',
    );
    expect(resolve(isWeb: true).toString(), 'http://localhost:3001/api/');
  });

  test('dart-define beats .env, which beats the default', () {
    expect(
      resolve(dotenvValue: 'http://192.168.1.20:3001/api').toString(),
      'http://192.168.1.20:3001/api/',
    );
    expect(
      resolve(
        dartDefine: 'https://api.fitflow.app/api/',
        dotenvValue: 'http://192.168.1.20:3001/api',
      ).toString(),
      'https://api.fitflow.app/api/',
    );
    expect(resolve(dotenvValue: '  ').toString(), 'http://10.0.2.2:3001/api/');
  });

  test('relative paths resolve under the API prefix', () {
    expect(
      resolve().resolve('me/docs/sessions').toString(),
      'http://10.0.2.2:3001/api/me/docs/sessions',
    );
  });
}
