import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/sites/hameln/hameln_html_fetcher.dart';

void main() {
  String fixture(String name) =>
      File('test/fixtures/hameln/$name').readAsStringSync();

  group('isHamelnChallengeHtml', () {
    test('Cloudflareチャレンジページをチャレンジと判定する', () {
      // どちらも素のHTTP取得でCloudflareに差し戻された実測HTML。
      for (final name in <String>[
        'ranking_cloudflare.html',
        'search.html',
      ]) {
        expect(
          isHamelnChallengeHtml(fixture(name)),
          isTrue,
          reason: '$name をチャレンジと判定できていない',
        );
      }
    });

    test('通常のランキングページをチャレンジと誤判定しない', () {
      // 通常ページにも `/cdn-cgi/challenge-platform/` のスクリプトが入る。
      // これを指標にするとWebViewが取得した正常HTMLを捨て続けてしまう。
      final html = fixture('ranking.html');
      expect(html, contains('challenge-platform'));
      expect(isHamelnChallengeHtml(html), isFalse);
    });

    test('通常の作品ページ・目次・本文をチャレンジと誤判定しない', () {
      for (final name in <String>[
        'serial.html',
        'short.html',
        'toc.html',
        'episode.html',
        'episode_ruby.html',
      ]) {
        expect(
          isHamelnChallengeHtml(fixture(name)),
          isFalse,
          reason: '$name をチャレンジと誤判定した',
        );
      }
    });

    test('チャレンジ中の断片的なHTMLでも検出する', () {
      expect(
        isHamelnChallengeHtml('<html><head><title>Just a moment...</title>'),
        isTrue,
      );
      expect(
        isHamelnChallengeHtml('<div class="challenge-error-text">x</div>'),
        isTrue,
      );
    });
  });
}
