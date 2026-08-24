import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/services/http_client.dart';
import 'package:novelty/utils/user_agents.dart';

void main() {
  group('User-Agent プリセット', () {
    test('4プラットフォーム分のプリセットが揃っている', () {
      for (final profile in UserAgentProfile.values) {
        expect(
          userAgentPresets[profile],
          isNotNull,
          reason: '$profile のプリセットが未定義',
        );
        expect(userAgentPresets[profile], startsWith('Mozilla/5.0'));
      }
    });

    test('各プリセットがプラットフォームを識別できる文字列を含む', () {
      expect(userAgentFor(UserAgentProfile.android), contains('Android'));
      expect(userAgentFor(UserAgentProfile.ios), contains('iPhone'));
      expect(userAgentFor(UserAgentProfile.windows), contains('Windows NT'));
      expect(userAgentFor(UserAgentProfile.macos), contains('Macintosh'));
    });

    test('既定のUser-Agentは実行環境のプリセットと一致する', () {
      expect(defaultUserAgent, userAgentFor(currentUserAgentProfile));
    });
  });

  group('createNoveltyDio のUser-Agent指定', () {
    test('既定では実行環境のプリセットを使う', () {
      final dio = createNoveltyDio();
      expect(dio.options.headers['User-Agent'], defaultUserAgent);
    });

    test('プロファイル指定でそのプリセットを使う', () {
      final dio = createNoveltyDio(userAgentProfile: UserAgentProfile.android);
      expect(
        dio.options.headers['User-Agent'],
        userAgentFor(UserAgentProfile.android),
      );
    });

    test('文字列指定はプロファイル指定より優先される', () {
      final dio = createNoveltyDio(
        userAgent: 'CustomAgent/1.0',
        userAgentProfile: UserAgentProfile.ios,
      );
      expect(dio.options.headers['User-Agent'], 'CustomAgent/1.0');
    });
  });
}
