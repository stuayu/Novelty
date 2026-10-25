import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/repositories/form_auth_session_repository.dart';
import 'package:novelty/services/form_post_auth_service.dart';
import 'package:novelty/sites/novel_source.dart';

class _MemorySessionRepository extends FormAuthSessionRepository {
  _MemorySessionRepository() : super(source: NovelSource.novelup);

  Map<String, String> savedCookies = {};

  @override
  Future<void> saveSession({
    required String accountId,
    required Map<String, String> cookies,
  }) async {
    savedCookies = Map.of(cookies);
  }

  @override
  Future<Map<String, String>> getCookies() async => Map.of(savedCookies);

  @override
  Future<String?> buildCookieHeader() async => savedCookies.entries
      .map((entry) => '${entry.key}=${entry.value}')
      .join('; ');

  @override
  Future<void> clearAll() async => savedCookies.clear();
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _html(
  String body,
  int status, {
  Map<String, List<String>> headers = const {},
}) => ResponseBody.fromString(
  body,
  status,
  headers: {
    Headers.contentTypeHeader: ['text/html; charset=utf-8'],
    ...headers,
  },
);

FormPostAuthService _service({
  required Dio dio,
  required FormAuthSessionRepository repository,
  Uri? loginUri,
  Uri? postUri,
  Uri? sessionCheckUri,
  List<Uri> sessionSuccessRedirectUris = const [],
}) => FormPostAuthService(
  sessionRepository: repository,
  dio: dio,
  configuration: FormPostAuthConfiguration(
    loginUri: loginUri ?? Uri.parse('https://auth.example/login'),
    postUri: postUri ?? Uri.parse('https://auth.example/login'),
    sessionCheckUri: sessionCheckUri,
    accountField: 'account',
    passwordField: 'password',
    hiddenFields: const ['csrf'],
    sessionSuccessRedirectUris: sessionSuccessRedirectUris,
  ),
);

void main() {
  test('保存Cookieがなければorigin設定が不正でも未ログインと判定する', () async {
    final repository = _MemorySessionRepository();
    final adapter = _RecordingAdapter((_) => _html('', 200));
    final service = _service(
      dio: Dio()..httpClientAdapter = adapter,
      repository: repository,
      loginUri: Uri.parse('http://auth.example/login'),
      postUri: Uri.parse('http://auth.example/login'),
    );

    expect(await service.validateSession(), FormAuthSessionValidity.invalid);
    expect(adapter.requests, isEmpty);
  });

  test('一時的なHTTPエラーと認証拒否を別の状態として返す', () async {
    for (final (status, expected) in [
      (401, FormAuthSessionValidity.invalid),
      (403, FormAuthSessionValidity.unavailable),
      (429, FormAuthSessionValidity.unavailable),
      (503, FormAuthSessionValidity.unavailable),
    ]) {
      final repository = _MemorySessionRepository()
        ..savedCookies = {'session': 'saved'};
      final adapter = _RecordingAdapter((_) => _html('', status));
      final service = _service(
        dio: Dio()..httpClientAdapter = adapter,
        repository: repository,
      );

      expect(await service.validateSession(), expected, reason: 'HTTP $status');
      expect(repository.savedCookies, {'session': 'saved'});
    }
  });

  test('ログインフォームへのリダイレクトを明示的な失効として返す', () async {
    for (final location in ['/login?mode=login', '/login?expired=1']) {
      final repository = _MemorySessionRepository()
        ..savedCookies = {'session': 'saved'};
      final adapter = _RecordingAdapter(
        (_) => _html(
          '',
          302,
          headers: {
            'location': [location],
          },
        ),
      );
      final service = _service(
        dio: Dio()..httpClientAdapter = adapter,
        repository: repository,
        sessionCheckUri: Uri.parse('https://auth.example/account'),
      );

      expect(
        await service.validateSession(),
        FormAuthSessionValidity.invalid,
        reason: location,
      );
      expect(repository.savedCookies, {'session': 'saved'});
    }
  });

  test('要認証ページからの未知のredirectを有効セッションと誤認しない', () async {
    for (final (location, expected) in [
      ('/login', FormAuthSessionValidity.invalid),
      ('/login/', FormAuthSessionValidity.invalid),
      ('/maintenance', FormAuthSessionValidity.unavailable),
      ('/mypage/top', FormAuthSessionValidity.valid),
      ('/mypagex', FormAuthSessionValidity.unavailable),
    ]) {
      final repository = _MemorySessionRepository()
        ..savedCookies = {'session': 'saved'};
      final adapter = _RecordingAdapter(
        (_) => _html(
          '',
          302,
          headers: {
            'location': [location],
          },
        ),
      );
      final service = _service(
        dio: Dio()..httpClientAdapter = adapter,
        repository: repository,
        sessionCheckUri: Uri.parse('https://auth.example/mypage'),
      );

      expect(
        await service.validateSession(),
        expected,
        reason: location,
      );
    }
  });

  test('ログインページからのmode=mypage redirectは有効セッションとして扱う', () async {
    final repository = _MemorySessionRepository()
      ..savedCookies = {'session': 'saved'};
    final adapter = _RecordingAdapter(
      (_) => _html(
        '',
        302,
        headers: {
          'location': ['/?mode=mypage'],
        },
      ),
    );
    final service = _service(
      dio: Dio()..httpClientAdapter = adapter,
      repository: repository,
      loginUri: Uri.parse('https://auth.example/?mode=login'),
      postUri: Uri.parse('https://auth.example/?mode=login'),
      sessionSuccessRedirectUris: [
        Uri.parse('https://auth.example/?mode=mypage'),
      ],
    );

    expect(await service.validateSession(), FormAuthSessionValidity.valid);
  });

  test('ログインページからの未登録redirectは有効扱いにしない', () async {
    final repository = _MemorySessionRepository()
      ..savedCookies = {'session': 'saved'};
    final adapter = _RecordingAdapter(
      (_) => _html(
        '',
        302,
        headers: {
          'location': ['/maintenance'],
        },
      ),
    );
    final service = _service(
      dio: Dio()..httpClientAdapter = adapter,
      repository: repository,
    );

    expect(
      await service.validateSession(),
      FormAuthSessionValidity.unavailable,
    );
  });

  test('loginとpostのoriginが一致しない設定では通信しない', () async {
    final repository = _MemorySessionRepository();
    final adapter = _RecordingAdapter((_) => _html('', 200));
    final service = _service(
      dio: Dio()..httpClientAdapter = adapter,
      repository: repository,
      postUri: Uri.parse('https://attacker.example/login'),
    );

    final result = await service.login(
      accountId: 'reader',
      password: 'secret',
    );

    expect(result.isSuccess, isFalse);
    expect(adapter.requests, isEmpty);
    expect(repository.savedCookies, isEmpty);
  });

  test('ログインフォームの外部actionへCookieや資格情報を送らない', () async {
    final repository = _MemorySessionRepository();
    final adapter = _RecordingAdapter(
      (_) => _html(
        '<form action="https://attacker.example/collect"> '
        '<input type="hidden" name="csrf" value="csrf-value"> '
        '<input name="account"><input name="password"></form>',
        200,
        headers: {
          'set-cookie': ['session=secret-cookie; Path=/'],
        },
      ),
    );
    final service = _service(
      dio: Dio()..httpClientAdapter = adapter,
      repository: repository,
    );

    final result = await service.login(
      accountId: 'reader',
      password: 'secret-password',
    );

    expect(result.isSuccess, isFalse);
    expect(adapter.requests, hasLength(1));
    expect(repository.savedCookies, isEmpty);
  });

  test('別フォームのCSRF値をログインPOSTへ流用しない', () async {
    final repository = _MemorySessionRepository();
    final adapter = _RecordingAdapter((options) {
      if (options.method == 'GET') {
        return _html(
          '<form><input type="hidden" name="csrf" value="other-form-token"></form> '
          '<form action="/login"> '
          '<input name="account"><input name="password"></form>',
          200,
        );
      }
      return _html(
        '',
        302,
        headers: {
          'location': ['/account'],
          'set-cookie': ['session=authenticated; Path=/'],
        },
      );
    });
    final service = _service(
      dio: Dio()..httpClientAdapter = adapter,
      repository: repository,
    );

    final result = await service.login(
      accountId: 'reader',
      password: 'secret-password',
    );

    expect(result.isSuccess, isFalse);
    expect(adapter.requests, hasLength(1));
    expect(repository.savedCookies, isEmpty);
  });

  test('通信例外内の資格情報とCookie値を画面・ログへ出さない', () async {
    final repository = _MemorySessionRepository()
      ..savedCookies = {'session': 'existing-session'};
    final adapter = _RecordingAdapter((options) {
      if (options.method == 'GET') {
        return _html(
          '<form action="/login"> '
          '<input type="hidden" name="csrf" value="csrf-value"> '
          '<input name="account"><input name="password"></form>',
          200,
          headers: {
            'set-cookie': ['preauth=secret-cookie; Path=/'],
          },
        );
      }
      throw DioException(
        requestOptions: options,
        message: 'password=secret-password Cookie=secret-cookie',
      );
    });
    final service = _service(
      dio: Dio()..httpClientAdapter = adapter,
      repository: repository,
    );
    final logs = <String>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');

    try {
      final result = await service.login(
        accountId: 'reader',
        password: 'secret-password',
      );

      expect(result.error, isNot(contains('secret-password')));
      expect(result.error, isNot(contains('secret-cookie')));
      expect(logs.join('\n'), isNot(contains('secret-password')));
      expect(logs.join('\n'), isNot(contains('secret-cookie')));
      expect(repository.savedCookies, {'session': 'existing-session'});
    } finally {
      debugPrint = originalDebugPrint;
    }
  });

  test('別アカウントの資格情報エラーでは既存フォーム認証セッションを保持する', () async {
    final repository = _MemorySessionRepository()
      ..savedCookies = {'session': 'previous-session'};
    final adapter = _RecordingAdapter((options) {
      if (options.method == 'GET') {
        return _html(
          '<form action="/login"> '
          '<input type="hidden" name="csrf" value="csrf-value"> '
          '<input name="account"><input name="password"></form>',
          200,
        );
      }
      return _html(
        '<form action="/login"> '
        '<input name="account"><input name="password"></form> '
        '<p class="alert-danger">メールアドレスまたはパスワードが正しくありません</p>',
        200,
      );
    });
    final service = _service(
      dio: Dio()..httpClientAdapter = adapter,
      repository: repository,
    );

    final result = await service.login(
      accountId: 'new-reader',
      password: 'wrong-password',
    );

    expect(result.isSuccess, isFalse);
    expect(repository.savedCookies, {'session': 'previous-session'});
  });

  test('改行を含むID・パスワード拒否表示でも既存セッションを保持する', () async {
    final repository = _MemorySessionRepository()
      ..savedCookies = {'session': 'previous-session'};
    final adapter = _RecordingAdapter((options) {
      if (options.method == 'GET') {
        return _html(
          '<form action="/login"> '
          '<input type="hidden" name="csrf" value="csrf-value"> '
          '<input name="account"><input name="password"></form>',
          200,
        );
      }
      return _html(
        '<form action="/login"> '
        '<input name="account"><input name="password"></form> '
        '<div class="error">IDまたは<br>パスワードが違います</div>',
        200,
      );
    });
    final service = _service(
      dio: Dio()..httpClientAdapter = adapter,
      repository: repository,
    );

    final result = await service.login(
      accountId: 'new-reader',
      password: 'wrong-password',
    );

    expect(result.isSuccess, isFalse);
    expect(repository.savedCookies, {'session': 'previous-session'});
  });

  test('CSRFトークンのエラーでは既存フォーム認証セッションを保持する', () async {
    final repository = _MemorySessionRepository()
      ..savedCookies = {'session': 'previous-session'};
    final adapter = _RecordingAdapter((options) {
      if (options.method == 'GET') {
        return _html(
          '<form action="/login"> '
          '<input type="hidden" name="csrf" value="csrf-value"> '
          '<label>メールアドレス<input name="account"></label> '
          '<label>パスワード<input name="password"></label></form>',
          200,
        );
      }
      return _html(
        '<form action="/login"> '
        '<label>メールアドレス<input name="account"></label> '
        '<label>パスワード<input name="password"></label></form> '
        '<p class="alert-danger">認証トークンが無効です。もう一度お試しください。</p>',
        200,
      );
    });
    final service = _service(
      dio: Dio()..httpClientAdapter = adapter,
      repository: repository,
    );

    final result = await service.login(
      accountId: 'reader',
      password: 'password',
    );

    expect(result.isSuccess, isFalse);
    expect(repository.savedCookies, {'session': 'previous-session'});
  });

  test('同一originの認証redirectだけを受け入れ、URLのコードをログに出さない', () async {
    final repository = _MemorySessionRepository()
      ..savedCookies = {'session': 'secret-cookie'};
    final adapter = _RecordingAdapter(
      (_) => _html(
        '',
        302,
        headers: {
          'location': ['https://auth.example/account?code=secret-otp'],
        },
      ),
    );
    final service = _service(
      dio: Dio()..httpClientAdapter = adapter,
      repository: repository,
      sessionCheckUri: Uri.parse('https://auth.example/account'),
    );
    final logs = <String>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');

    try {
      expect(await service.isSessionValid(), isTrue);
      expect(adapter.requests, hasLength(1));
      expect(
        adapter.requests.single.headers['Cookie'],
        'session=secret-cookie',
      );
      expect(logs.join('\n'), isNot(contains('secret-otp')));
      expect(logs.join('\n'), isNot(contains('secret-cookie')));
    } finally {
      debugPrint = originalDebugPrint;
    }
  });

  test('HTTPまたは別portの認証redirectは有効セッションとして扱わない', () async {
    for (final location in [
      'http://auth.example/account',
      'https://auth.example:444/account',
      'https://accounts.example/login',
    ]) {
      final repository = _MemorySessionRepository()
        ..savedCookies = {'session': 'value'};
      final adapter = _RecordingAdapter(
        (_) => _html(
          '',
          302,
          headers: {
            'location': [location],
          },
        ),
      );
      final service = _service(
        dio: Dio()..httpClientAdapter = adapter,
        repository: repository,
        sessionCheckUri: Uri.parse('https://auth.example/account'),
      );

      expect(
        await service.validateSession(),
        FormAuthSessionValidity.unavailable,
        reason: location,
      );
      expect(adapter.requests, hasLength(1));
    }
  });
}
