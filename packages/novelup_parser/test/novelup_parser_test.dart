import 'dart:convert';
import 'dart:io';

import 'package:novelup_parser/novelup_parser.dart';
import 'package:test/test.dart';

void main() {
  group('parseNovelupEpisodeBody', () {
    test('#episode_content がない場合は FormatException を投げる', () {
      expect(
        () => parseNovelupEpisodeBody('<p>本文です。</p>'),
        throwsA(isA<FormatException>()),
      );
    });

    test('本文が空の場合は FormatException を投げる', () {
      for (final html in <String>[
        '<p id="episode_content"></p>',
        '<p id="episode_content"> \n\t</p>',
        '<p id="episode_content"><br><img><rp>(</rp></p>',
      ]) {
        expect(
          () => parseNovelupEpisodeBody(html),
          throwsA(isA<FormatException>()),
          reason: '入力: $html',
        );
      }
    });

    test('p 内の実改行と連続改行を newLine として保持する', () {
      const html = '<p id="episode_content">一行目\n\n三行目</p>';

      final result = parseNovelupEpisodeBody(html);

      expect(result, <NovelContentElement>[
        NovelContentElement.plainText('一行目'),
        NovelContentElement.newLine(),
        NovelContentElement.newLine(),
        NovelContentElement.plainText('三行目'),
      ]);
    });

    test('rb を親文字、rt を読みとして分離し rp を本文から除外する', () {
      const ruby = '<ruby><rb>南埜</rb><rp>(</rp><rt>みなみの</rt><rp>)</rp></ruby>';
      const html = '<p id="episode_content">「えっと、$rubyサン」</p>';

      final result = parseNovelupEpisodeBody(html);

      expect(result, <NovelContentElement>[
        NovelContentElement.plainText('「えっと、'),
        NovelContentElement.rubyText('南埜', 'みなみの'),
        NovelContentElement.plainText('サン」'),
      ]);
      final plainText = result.whereType<PlainText>().map((e) => e.text).join();
      expect(plainText, isNot(contains('(')));
      expect(plainText, isNot(contains(')')));
    });

    test('br は改行へ変換し、未知の要素はテキストのみ保持して画像は無視する', () {
      const unknownElements = '<span>強調</span><img alt="挿絵">';
      const html = '<p id="episode_content">前<br>後$unknownElements</p>';

      final result = parseNovelupEpisodeBody(html);

      expect(result, <NovelContentElement>[
        NovelContentElement.plainText('前'),
        NovelContentElement.newLine(),
        NovelContentElement.plainText('後'),
        NovelContentElement.plainText('強調'),
      ]);
    });

    test('実HTMLの本文、実改行、空行、ルビを変換する', () {
      final html = _fixture('episode.html').readAsStringSync();

      final result = parseNovelupEpisodeBody(html);

      expect(result, <NovelContentElement>[
        NovelContentElement.plainText('筆を染める：'),
        NovelContentElement.newLine(),
        NovelContentElement.plainText('初めて文章や絵を書き始めること、'),
        NovelContentElement.newLine(),
        NovelContentElement.newLine(),
        NovelContentElement.plainText('「えっと、'),
        NovelContentElement.rubyText('南埜', 'みなみの'),
        NovelContentElement.plainText('サン」'),
        NovelContentElement.newLine(),
        NovelContentElement.newLine(),
        NovelContentElement.plainText('　僕は、観念するしかなかった。'),
      ]);
    });

    test('実HTMLを Hybrid JSON に変換してルビ位置の整合性を保つ', () {
      final html = _fixture('episode.html').readAsStringSync();

      final result = parseNovelupEpisodeBody(html);
      final hybrid = HybridConverter.toHybridJson(result);
      final decoded = jsonDecode(hybrid) as Map<String, dynamic>;

      expect(decoded, <String, dynamic>{
        'txt':
            '筆を染める：\n'
            '初めて文章や絵を書き始めること、\n\n'
            '「えっと、南埜サン」\n\n'
            '　僕は、観念するしかなかった。',
        'rb': <Map<String, dynamic>>[
          <String, dynamic>{'off': 30, 'base': '南埜', 'ruby': 'みなみの'},
        ],
      });
      expect(HybridConverter.fromHybridJson(hybrid), result);
    });
  });
}

File _fixture(String name) {
  final fromRepositoryRoot = File('test/fixtures/novelup/$name');
  if (fromRepositoryRoot.existsSync()) {
    return fromRepositoryRoot;
  }
  return File('../../test/fixtures/novelup/$name');
}
