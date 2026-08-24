import 'dart:convert';
import 'dart:io';

import 'package:estar_parser/estar_parser.dart';
import 'package:test/test.dart';

void main() {
  group('parseEstarEpisodeBody', () {
    test('ルビ記法を基底文字と読みに変換する', () {
      final result = parseEstarEpisodeBody('|黛彩葉《まゆずみいろは》');

      expect(result, <NovelContentElement>[
        NovelContentElement.rubyText('黛彩葉', 'まゆずみいろは'),
      ]);
    });

    test('ルビ記法の前後のテキストを順序どおり分割する', () {
      final result = parseEstarEpisodeBody(
        '前|黛彩葉《まゆずみいろは》中|九十九海李《つくもかいり》後',
      );

      expect(result, <NovelContentElement>[
        NovelContentElement.plainText('前'),
        NovelContentElement.rubyText('黛彩葉', 'まゆずみいろは'),
        NovelContentElement.plainText('中'),
        NovelContentElement.rubyText('九十九海李', 'つくもかいり'),
        NovelContentElement.plainText('後'),
      ]);
    });

    test('二重山括弧の強調はルビにせず中身のテキストを残す', () {
      final result = parseEstarEpisodeBody('前《《強調》》後');

      expect(result, <NovelContentElement>[
        NovelContentElement.plainText('前強調後'),
      ]);
      expect(result.whereType<RubyText>(), isEmpty);
    });

    test('連続する改行を空行として保持する', () {
      final result = parseEstarEpisodeBody('一行目\n\n\n二行目');

      expect(result, <NovelContentElement>[
        NovelContentElement.plainText('一行目'),
        NovelContentElement.newLine(),
        NovelContentElement.newLine(),
        NovelContentElement.newLine(),
        NovelContentElement.plainText('二行目'),
      ]);
    });

    test('Markdown画像行はURLを本文へ出さず行区切りを保持する', () {
      final result = parseEstarEpisodeBody(
        '画像の前\n![挿絵](https://example.com/image.jpg)\n画像の後',
      );

      expect(result, <NovelContentElement>[
        NovelContentElement.plainText('画像の前'),
        NovelContentElement.newLine(),
        NovelContentElement.newLine(),
        NovelContentElement.plainText('画像の後'),
      ]);
    });

    test('本文が空なら FormatException を投げる', () {
      for (final body in <String>['', '   ', '\n\n']) {
        expect(
          () => parseEstarEpisodeBody(body),
          throwsA(isA<FormatException>()),
          reason: '入力: $body',
        );
      }
    });

    test('実GraphQLレスポンスの本文をHybrid JSONへ整合する形で変換する', () {
      final result = parseEstarEpisodeBody(_fixtureBody());

      expect(result, <NovelContentElement>[
        NovelContentElement.plainText('時は遡り数ヶ月前の五月。'),
        NovelContentElement.newLine(),
        NovelContentElement.rubyText('黛彩葉', 'まゆずみいろは'),
        NovelContentElement.plainText('は政略結婚することになった。'),
        NovelContentElement.newLine(),
        NovelContentElement.newLine(),
        NovelContentElement.newLine(),
        NovelContentElement.plainText('私たちの世界では未だに政略結婚なんてよくあることで。'),
      ]);

      final hybrid = HybridConverter.toHybridJson(result);
      expect(jsonDecode(hybrid), <String, dynamic>{
        'txt':
            '時は遡り数ヶ月前の五月。\n'
            '黛彩葉は政略結婚することになった。\n\n\n'
            '私たちの世界では未だに政略結婚なんてよくあることで。',
        'rb': <Map<String, dynamic>>[
          <String, dynamic>{'off': 13, 'base': '黛彩葉', 'ruby': 'まゆずみいろは'},
        ],
      });
      expect(HybridConverter.fromHybridJson(hybrid), result);
    });
  });
}

String _fixtureBody() {
  final fixture = _fixture('episode.html').readAsStringSync();
  final encodedBodies = RegExp(
    r'"body":"((?:\\.|[^"\\])*)"',
  ).allMatches(fixture).map((match) => match.group(1)!);
  final encodedBody = encodedBodies.firstWhere((body) => body.isNotEmpty);
  final body = jsonDecode('"$encodedBody"') as String;
  return body.replaceAll(r'\n', '\n');
}

File _fixture(String name) {
  final fromRepositoryRoot = File('test/fixtures/estar/$name');
  if (fromRepositoryRoot.existsSync()) {
    return fromRepositoryRoot;
  }
  return File('../../test/fixtures/estar/$name');
}
