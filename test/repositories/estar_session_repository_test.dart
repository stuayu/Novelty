import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/models/estar_session_cookie.dart';
import 'package:novelty/repositories/estar_session_repository.dart';

class _FakeSecureStorage extends FlutterSecureStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read({
    required String key,
    AndroidOptions? aOptions,
    IOSOptions? iOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AndroidOptions? aOptions,
    IOSOptions? iOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AndroidOptions? aOptions,
    IOSOptions? iOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    values.remove(key);
  }
}

void main() {
  test('Cookie名を限定せず属性付きで保存・復元する', () async {
    final repository = EstarSessionRepository(storage: _FakeSecureStorage());
    const cookies = [
      EstarSessionCookie(
        name: 'future_cookie_name',
        value: 'secret-value',
        domain: '.estar.jp',
        path: '/',
        expiresDate: 4102444800000,
        isSecure: true,
        isHttpOnly: true,
      ),
      EstarSessionCookie(
        name: 'another_cookie',
        value: 'another-value',
        domain: 'auth.estar.jp',
        path: '/auth',
      ),
    ];

    await repository.saveCookies(cookies);

    expect(await repository.getCookies(), hasLength(2));
    expect(await repository.getCookies(), [
      isA<EstarSessionCookie>()
          .having((cookie) => cookie.name, 'name', 'future_cookie_name')
          .having((cookie) => cookie.domain, 'domain', '.estar.jp')
          .having((cookie) => cookie.isHttpOnly, 'isHttpOnly', isTrue),
      isA<EstarSessionCookie>()
          .having((cookie) => cookie.name, 'name', 'another_cookie')
          .having((cookie) => cookie.domain, 'domain', 'auth.estar.jp'),
    ]);
  });

  test('エブリスタ外Cookieは保存しない', () async {
    final repository = EstarSessionRepository(storage: _FakeSecureStorage());

    await repository.saveCookies(const [
      EstarSessionCookie(
        name: 'unrelated',
        value: 'secret-value',
        domain: 'example.com',
        path: '/',
      ),
    ]);

    expect(await repository.getCookies(), isEmpty);
    expect(await repository.hasCookies(), isFalse);
  });
}
