import 'dart:convert';
import 'dart:io';

import 'package:alphapolis_parser/alphapolis_parser.dart';
import 'package:test/test.dart';

void main() {
  group('parseAlphapolisEpisodeBody', () {
    test('本文断片のテキストと改行を変換する', () {
      const html = '　一行目。<br />二行目。<br />';

      final result = parseAlphapolisEpisodeBody(html);

      expect(result, <NovelContentElement>[
        NovelContentElement.plainText('　一行目。'),
        NovelContentElement.newLine(),
        NovelContentElement.plainText('二行目。'),
        NovelContentElement.newLine(),
      ]);
    });

    test('実HTMLのルビを基底文字と読みへ分離する', () {
      final html = File(
        'test/fixtures/ruby_episode_body.html',
      ).readAsStringSync();

      final result = parseAlphapolisEpisodeBody(html);

      expect(result.whereType<RubyText>(), <RubyText>[
        NovelContentElement.rubyText('王族', 'かぞく') as RubyText,
        NovelContentElement.rubyText('白蛇', 'エ・ラジャ') as RubyText,
      ]);
    });

    test('実HTMLの連続する br を空行として保持する', () {
      final html = File(
        'test/fixtures/ruby_episode_body.html',
      ).readAsStringSync();

      final result = parseAlphapolisEpisodeBody(html);
      final firstLineBreak = result.indexWhere((element) => element is NewLine);

      expect(result[firstLineBreak + 1], isA<NewLine>());
    });

    test('実HTMLを Hybrid JSON に変換してルビ位置の整合性を保つ', () {
      final html = File(
        'test/fixtures/ruby_episode_body.html',
      ).readAsStringSync();

      final result = parseAlphapolisEpisodeBody(html);
      final hybrid = HybridConverter.toHybridJson(result);
      final decoded = jsonDecode(hybrid) as Map<String, dynamic>;

      expect(
        decoded,
        <String, dynamic>{
          'txt':
              '　王族や、親しい者たちとの別れは、もう済ませてある。\n\n'
              '　これよりレインティエは、西にある広大な霊海の森を越えて、白蛇族の元へ向かい。\n',
          'rb': <Map<String, dynamic>>[
            <String, dynamic>{'off': 1, 'base': '王族', 'ruby': 'かぞく'},
            <String, dynamic>{'off': 57, 'base': '白蛇', 'ruby': 'エ・ラジャ'},
          ],
        },
      );
      expect(HybridConverter.fromHybridJson(hybrid), result);
    });

    test('完全ページでは novelBody だけを本文として変換する', () {
      final html = File(
        'test/fixtures/episode_page.html',
      ).readAsStringSync();

      final result = parseAlphapolisEpisodeBody(html);

      expect(result, <NovelContentElement>[
        NovelContentElement.plainText(
          '　クラン「ゼノギア」の応接室は、床が鏡みたいに光っていた。',
        ),
        NovelContentElement.newLine(),
        NovelContentElement.newLine(),
        NovelContentElement.plainText('　昨夜、俺がワックスを二度がけしたからだ。'),
        NovelContentElement.newLine(),
      ]);
    });

    test('本文が空なら FormatException を投げる', () {
      for (final html in <String>['', '   ', '<br /><br />']) {
        expect(
          () => parseAlphapolisEpisodeBody(html),
          throwsA(isA<FormatException>()),
          reason: '入力: $html',
        );
      }
    });

    test('完全ページで novelBody セレクタが一致しなければ FormatException を投げる', () {
      const html =
          '<h2 class="p-novel-episode__episode-title">第1話</h2> '
          '<div class="p-novel-episode__text">本文です。</div>';

      expect(
        () => parseAlphapolisEpisodeBody(html),
        throwsA(isA<FormatException>()),
      );
    });

    test('未知の要素は子テキストを失わずに変換する', () {
      const html = '<span class="unknown">本文<em>強調</em></span><br />';

      final result = parseAlphapolisEpisodeBody(html);

      expect(result, <NovelContentElement>[
        NovelContentElement.plainText('本文'),
        NovelContentElement.plainText('強調'),
        NovelContentElement.newLine(),
      ]);
    });
  });
}
