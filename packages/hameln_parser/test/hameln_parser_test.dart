import 'dart:convert';
import 'dart:io';

import 'package:hameln_parser/hameln_parser.dart';
import 'package:test/test.dart';

void main() {
  group('parseHamelnEpisodeBody', () {
    test('実HTMLの段落と空行を変換する', () {
      final html = _fixture('episode.html').readAsStringSync();

      final result = parseHamelnEpisodeBody(html);

      expect(result, <NovelContentElement>[
        NovelContentElement.plainText(
          '「はい。それでは皆さん今日も勉強頑張っていきましょう！」',
        ),
        NovelContentElement.newLine(),
        NovelContentElement.newLine(),
        NovelContentElement.plainText('『はーい』'),
        NovelContentElement.newLine(),
        NovelContentElement.plainText('石造りの建物の中で子供たちの元気な声が響く。'),
        NovelContentElement.newLine(),
      ]);
    });

    test('実HTMLの rb と rt をルビへ変換し rp を除外する', () {
      final html = _fixture('episode_ruby.html').readAsStringSync();

      final result = parseHamelnEpisodeBody(html);

      expect(result.whereType<RubyText>(), <RubyText>[
        NovelContentElement.rubyText('廃棄された天庭', 'バビロン') as RubyText,
        NovelContentElement.rubyText('翼の宰相', 'ノーマン・クリード') as RubyText,
        NovelContentElement.rubyText('簒奪', 'コピー') as RubyText,
        NovelContentElement.rubyText('観', '・') as RubyText,
        NovelContentElement.rubyText('斃', 'たお') as RubyText,
      ]);
      final plainText = result.whereType<PlainText>().map((e) => e.text).join();
      expect(plainText, isNot(contains('(')));
      expect(plainText, isNot(contains(')')));
    });

    test('傍点をルビとして保持し区切り線を改行へ変換する', () {
      final html = _fixture('episode_ruby.html').readAsStringSync();

      final result = parseHamelnEpisodeBody(html);

      expect(
        result,
        contains(NovelContentElement.rubyText('観', '・')),
      );
      final separatorStart = result.indexOf(
        NovelContentElement.plainText('区切り線の後。'),
      );
      expect(
        result.sublist(separatorStart, separatorStart + 4),
        <NovelContentElement>[
          NovelContentElement.plainText('区切り線の後。'),
          NovelContentElement.newLine(),
          NovelContentElement.newLine(),
          NovelContentElement.plainText('次の段落。'),
        ],
      );
    });

    test('#honbun がない場合と本文が空の場合は FormatException を投げる', () {
      for (final html in <String>[
        '<p>本文です。</p>',
        '<div id="honbun"></div>',
        '<div id="honbun"><p>　</p></div>',
      ]) {
        expect(
          () => parseHamelnEpisodeBody(html),
          throwsA(isA<FormatException>()),
          reason: '入力: $html',
        );
      }
    });

    test('実HTMLを Hybrid JSON に変換してルビ位置の整合性を保つ', () {
      final html = _fixture('episode_ruby.html').readAsStringSync();

      final result = parseHamelnEpisodeBody(html);
      final hybrid = HybridConverter.toHybridJson(result);
      final decoded = jsonDecode(hybrid) as Map<String, dynamic>;

      expect(decoded, <String, dynamic>{
        'txt':
            '「腐り落ちろ―――《廃棄された天庭」励起。《翼の宰相》簒奪。\n'
            '　そう観れば分かる。斃れるに決まっている。\n\n'
            '区切り線の後。\n\n次の段落。\n',
        'rb': <Map<String, dynamic>>[
          <String, dynamic>{'off': 10, 'base': '廃棄された天庭', 'ruby': 'バビロン'},
          <String, dynamic>{'off': 22, 'base': '翼の宰相', 'ruby': 'ノーマン・クリード'},
          <String, dynamic>{'off': 27, 'base': '簒奪', 'ruby': 'コピー'},
          <String, dynamic>{'off': 34, 'base': '観', 'ruby': '・'},
          <String, dynamic>{'off': 41, 'base': '斃', 'ruby': 'たお'},
        ],
      });
      expect(HybridConverter.fromHybridJson(hybrid), result);
    });

    test('br は改行へ変換し、未確認の画像は本文要素へ変換しない', () {
      const html = '<div id="honbun"><p>前<br>後<img alt="挿絵"></p></div>';

      final result = parseHamelnEpisodeBody(html);

      // br を落とすと前後の行が繋がって本文が欠けるため newLine にする
      expect(result, <NovelContentElement>[
        NovelContentElement.plainText('前'),
        NovelContentElement.newLine(),
        NovelContentElement.plainText('後'),
        NovelContentElement.newLine(),
      ]);
    });
  });
}

File _fixture(String name) {
  final fromRepositoryRoot = File('test/fixtures/hameln/$name');
  if (fromRepositoryRoot.existsSync()) {
    return fromRepositoryRoot;
  }
  return File('../../test/fixtures/hameln/$name');
}
