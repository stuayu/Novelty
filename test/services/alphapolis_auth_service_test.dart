import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/repositories/form_auth_session_repository.dart';
import 'package:novelty/services/alphapolis_auth_service.dart';
import 'package:novelty/sites/novel_source.dart';

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.respond);

  final ResponseBody Function(RequestOptions options) respond;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

class _MemorySessionRepository extends FormAuthSessionRepository {
  _MemorySessionRepository() : super(source: NovelSource.alphapolis);

  Map<String, String> cookies = {};
  String? accountId;
  int clearCount = 0;

  @override
  Future<void> saveSession({
    required String accountId,
    required Map<String, String> cookies,
  }) async {
    this.accountId = accountId;
    this.cookies = Map.of(cookies);
  }

  @override
  Future<Map<String, String>> getCookies() async => Map.of(cookies);

  @override
  Future<String?> getAccountId() async => accountId;

  @override
  Future<String?> buildCookieHeader() async => cookies.isEmpty
      ? null
      : cookies.entries
            .map((entry) => '${entry.key}=${entry.value}')
            .join('; ');

  @override
  Future<void> clearAll() async {
    clearCount++;
    cookies.clear();
    accountId = null;
  }
}

ResponseBody _html(
  String body,
  int status, {
  Map<String, List<String>>? headers,
}) {
  return ResponseBody.fromString(
    body,
    status,
    headers: {
      Headers.contentTypeHeader: ['text/html; charset=utf-8'],
      ...?headers,
    },
  );
}

void main() {
  group('AlphapolisAuthService', () {
    test('hidden tokenを抽出し全フィールドをPOSTして全Cookieを保存する', () async {
      final repository = _MemorySessionRepository();
      final adapter = _RecordingAdapter((options) {
        if (options.method == 'GET') {
          return _html(
            '''
<form action="/login">
<input type="hidden" name="_token" value="csrf-value">
<input name="email"><input name="password"></form>''',
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
            'location': ['/mypage'],
            'set-cookie': [
              'alpl_v2_front_session=session-value; Path=/; HttpOnly',
              'unexpected_cookie=keep-me; Path=/',
            ],
          },
        );
      });
      final dio = Dio()..httpClientAdapter = adapter;
      final service = AlphapolisAuthService(
        sessionRepository: repository,
        dio: dio,
      );

      final result = await service.login(
        email: 'reader@example.com',
        password: 'secret',
      );

      expect(result.isSuccess, isTrue);
      expect(adapter.requests, hasLength(2));
      expect(
        adapter.requests.last.uri.toString(),
        'https://www.alphapolis.co.jp/login',
      );
      expect(adapter.requests.last.data, {
        '_token': 'csrf-value',
        'email': 'reader@example.com',
        'password': 'secret',
      });
      expect(adapter.requests.last.headers['Cookie'], 'XSRF-TOKEN=xsrf');
      expect(repository.accountId, 'reader@example.com');
      expect(repository.cookies, {
        'XSRF-TOKEN': 'xsrf',
        'alpl_v2_front_session': 'session-value',
        'unexpected_cookie': 'keep-me',
      });
    });

    test('hidden tokenが無い場合はPOSTせず失敗する', () async {
      final repository = _MemorySessionRepository();
      final adapter = _RecordingAdapter((_) => _html('<form></form>', 200));
      final service = AlphapolisAuthService(
        sessionRepository: repository,
        dio: Dio()..httpClientAdapter = adapter,
      );

      final result = await service.login(
        email: 'reader@example.com',
        password: 'secret',
      );

      expect(result.isSuccess, isFalse);
      expect(adapter.requests, hasLength(1));
      expect(repository.cookies, isEmpty);
    });

    test('ログインフォーム再表示時はCookieが発行されても失敗する', () async {
      final repository = _MemorySessionRepository();
      final adapter = _RecordingAdapter((options) {
        if (options.method == 'GET') {
          return _html(
            '<input type="hidden" name="_token" value="csrf">',
            200,
          );
        }
        return _html(
          '''
<div class="alert-danger">認証失敗</div>
<form action="/login"><input name="email"><input name="password"></form>''',
          200,
          headers: {
            'set-cookie': ['candidate=value; Path=/'],
          },
        );
      });
      final service = AlphapolisAuthService(
        sessionRepository: repository,
        dio: Dio()..httpClientAdapter = adapter,
      );

      final result = await service.login(
        email: 'bad@example.com',
        password: 'wrong',
      );

      expect(result.isSuccess, isFalse);
      expect(repository.cookies, isEmpty);
    });

    test('成功先へのredirectでもPOST後Cookieが無ければ失敗する', () async {
      final repository = _MemorySessionRepository();
      final adapter = _RecordingAdapter((options) {
        if (options.method == 'GET') {
          return _html(
            '<input type="hidden" name="_token" value="csrf">',
            200,
          );
        }
        return _html(
          '',
          302,
          headers: {
            'location': ['/mypage'],
          },
        );
      });
      final service = AlphapolisAuthService(
        sessionRepository: repository,
        dio: Dio()..httpClientAdapter = adapter,
      );

      final result = await service.login(
        email: 'reader@example.com',
        password: 'secret',
      );

      expect(result.isSuccess, isFalse);
      expect(repository.cookies, isEmpty);
    });

    test('保存Cookie付きGETがログイン外へredirectすればログイン済み', () async {
      final repository = _MemorySessionRepository()
        ..cookies = {'dynamic': 'session'};
      final adapter = _RecordingAdapter(
        (_) => _html(
          '',
          302,
          headers: {
            'location': ['/mypage'],
          },
        ),
      );
      final service = AlphapolisAuthService(
        sessionRepository: repository,
        dio: Dio()..httpClientAdapter = adapter,
      );

      expect(await service.isSessionValid(), isTrue);
      expect(adapter.requests.single.headers['Cookie'], 'dynamic=session');
    });

    test('ログインページが再表示されれば未ログイン', () async {
      final repository = _MemorySessionRepository()
        ..cookies = {'dynamic': 'expired'};
      final adapter = _RecordingAdapter(
        (_) => _html(
          '<form action="/login"><input name="email"><input name="password"></form>',
          200,
        ),
      );
      final service = AlphapolisAuthService(
        sessionRepository: repository,
        dio: Dio()..httpClientAdapter = adapter,
      );

      expect(await service.isSessionValid(), isFalse);
    });

    test('logoutで保存済みセッションを消す', () async {
      final repository = _MemorySessionRepository()
        ..cookies = {'dynamic': 'session'};
      final service = AlphapolisAuthService(
        sessionRepository: repository,
        dio: Dio(),
      );

      await service.logout();

      expect(repository.clearCount, 1);
      expect(repository.cookies, isEmpty);
    });
  });
}
