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
  ),
);

void main() {
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
    final repository = _MemorySessionRepository();
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
      expect(repository.savedCookies, isEmpty);
    } finally {
      debugPrint = originalDebugPrint;
    }
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

      expect(await service.isSessionValid(), isFalse, reason: location);
      expect(adapter.requests, hasLength(1));
    }
  });
}
