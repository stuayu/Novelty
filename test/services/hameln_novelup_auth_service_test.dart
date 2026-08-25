import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/repositories/form_auth_session_repository.dart';
import 'package:novelty/services/hameln_auth_service.dart';
import 'package:novelty/services/novelup_auth_service.dart';
import 'package:novelty/sites/novel_source.dart';

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

class _MemoryRepository extends FormAuthSessionRepository {
  _MemoryRepository(NovelSource source) : super(source: source);

  Map<String, String> savedCookies = {};
  String? savedAccountId;

  @override
  Future<void> saveSession({
    required String accountId,
    required Map<String, String> cookies,
  }) async {
    savedAccountId = accountId;
    savedCookies = Map.of(cookies);
  }

  @override
  Future<String?> buildCookieHeader() async => savedCookies.isEmpty
      ? null
      : savedCookies.entries
            .map((entry) => '${entry.key}=${entry.value}')
            .join('; ');

  @override
  Future<void> clearAll() async {
    savedAccountId = null;
    savedCookies.clear();
  }
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

void main() {
  group('HamelnAuthService', () {
    test('redirect_modeを抽出し実測済み4フィールドをPOSTする', () async {
      final repository = _MemoryRepository(NovelSource.hameln);
      final adapter = _RecordingAdapter((options) {
        if (options.method == 'GET') {
          return _html(
            '''
<form action="./">
<input name="id"><input name="pass">
<input type="hidden" name="mode" value="login_entry_end">
<input type="hidden" name="redirect_mode" value="favo"></form>''',
            200,
            headers: {
              'set-cookie': ['uaid=guest; Path=/'],
            },
          );
        }
        return _html(
          '',
          302,
          headers: {
            'location': ['/?mode=mypage'],
            'set-cookie': ['new_session=authenticated; Path=/'],
          },
        );
      });
      final service = HamelnAuthService(
        sessionRepository: repository,
        dio: Dio()..httpClientAdapter = adapter,
      );

      final result = await service.login(id: 'reader-id', password: 'secret');

      expect(result.isSuccess, isTrue);
      expect(
        adapter.requests.first.uri.toString(),
        'https://syosetu.org/?mode=login',
      );
      expect(adapter.requests.last.uri.toString(), 'https://syosetu.org/');
      expect(adapter.requests.last.data, {
        'redirect_mode': 'favo',
        'mode': 'login_entry_end',
        'id': 'reader-id',
        'pass': 'secret',
      });
      expect(repository.savedCookies, {
        'uaid': 'guest',
        'new_session': 'authenticated',
      });
    });

    test('redirect_modeが無ければPOSTせず失敗する', () async {
      final repository = _MemoryRepository(NovelSource.hameln);
      final adapter = _RecordingAdapter(
        (_) => _html('<form><input name="id"><input name="pass"></form>', 200),
      );
      final service = HamelnAuthService(
        sessionRepository: repository,
        dio: Dio()..httpClientAdapter = adapter,
      );

      final result = await service.login(id: 'reader-id', password: 'secret');

      expect(result.isSuccess, isFalse);
      expect(adapter.requests, hasLength(1));
    });

    test('認証失敗フォームが返ればCookieを保存しない', () async {
      final repository = _MemoryRepository(NovelSource.hameln);
      final adapter = _RecordingAdapter((options) {
        if (options.method == 'GET') {
          return _html(
            '<input name="redirect_mode" value="top">',
            200,
          );
        }
        return _html(
          '''
<div role="alert">ログインに失敗</div>
<form><input name="id"><input name="pass"></form>''',
          200,
          headers: {
            'set-cookie': ['candidate=value; Path=/'],
          },
        );
      });
      final service = HamelnAuthService(
        sessionRepository: repository,
        dio: Dio()..httpClientAdapter = adapter,
      );

      expect(
        (await service.login(id: 'reader-id', password: 'wrong')).isSuccess,
        isFalse,
      );
      expect(repository.savedCookies, isEmpty);
    });
  });

  group('NovelupAuthService', () {
    test('_tokenとrememberをHTMLから抽出して全フィールドをPOSTする', () async {
      final repository = _MemoryRepository(NovelSource.novelup);
      final adapter = _RecordingAdapter((options) {
        if (options.method == 'GET') {
          return _html(
            '''
<form action="/login">
<input type="hidden" name="_token" value="csrf-value">
<input name="mail"><input name="password">
<input type="checkbox" name="remember" value="remember-me"></form>''',
            200,
            headers: {
              'set-cookie': ['XSRF-TOKEN=xsrf; Path=/'],
            },
          );
        }
        return _html(
          '',
          302,
          headers: {
            'location': ['/'],
            'set-cookie': ['opaque_session=session-value; Path=/'],
          },
        );
      });
      final service = NovelupAuthService(
        sessionRepository: repository,
        dio: Dio()..httpClientAdapter = adapter,
      );

      final result = await service.login(
        mail: 'reader@example.com',
        password: 'secret',
      );

      expect(result.isSuccess, isTrue);
      expect(adapter.requests.last.data, {
        '_token': 'csrf-value',
        'remember': 'remember-me',
        'mail': 'reader@example.com',
        'password': 'secret',
      });
      expect(repository.savedCookies, {
        'XSRF-TOKEN': 'xsrf',
        'opaque_session': 'session-value',
      });
    });

    test('rememberの実値がHTMLに無ければ推測せず失敗する', () async {
      final repository = _MemoryRepository(NovelSource.novelup);
      final adapter = _RecordingAdapter(
        (_) => _html('<input name="_token" value="csrf">', 200),
      );
      final service = NovelupAuthService(
        sessionRepository: repository,
        dio: Dio()..httpClientAdapter = adapter,
      );

      final result = await service.login(
        mail: 'reader@example.com',
        password: 'secret',
      );

      expect(result.isSuccess, isFalse);
      expect(adapter.requests, hasLength(1));
    });

    test('ログイン画面へのredirectはCookieが発行されても失敗する', () async {
      final repository = _MemoryRepository(NovelSource.novelup);
      final adapter = _RecordingAdapter((options) {
        if (options.method == 'GET') {
          return _html(
            '''
<input name="_token" value="csrf">
<input name="remember" value="1">''',
            200,
          );
        }
        return _html(
          '',
          302,
          headers: {
            'location': ['/login'],
            'set-cookie': ['candidate=value; Path=/'],
          },
        );
      });
      final service = NovelupAuthService(
        sessionRepository: repository,
        dio: Dio()..httpClientAdapter = adapter,
      );

      expect(
        (await service.login(
          mail: 'bad@example.com',
          password: 'wrong',
        )).isSuccess,
        isFalse,
      );
      expect(repository.savedCookies, isEmpty);
    });
  });
}
