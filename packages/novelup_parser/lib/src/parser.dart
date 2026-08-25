import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:novel_parser_core/novel_parser_core.dart';

/// ノベルアップ＋のエピソード本文HTMLをパースする。
List<NovelContentElement> parseNovelupEpisodeBody(String html) {
  final document = html_parser.parse(html);
  final body = document.querySelector('#episode_content');
  if (body == null) {
    throw const FormatException(
      'ノベルアップ＋のエピソードページに #episode_content がありません',
    );
  }
  if (body.text.trim().isEmpty) {
    throw const FormatException('ノベルアップ＋の本文が空です');
  }
  final elements = <NovelContentElement>[];
  _parseNodes(body, elements);
  final hasText = elements.any(
    (element) =>
        (element is PlainText && element.text.trim().isNotEmpty) ||
        (element is RubyText && element.base.trim().isNotEmpty),
  );
  if (!hasText) {
    throw const FormatException('ノベルアップ＋の本文が空です');
  }
  return elements;
}

void _parseNodes(dom.Node node, List<NovelContentElement> elements) {
  for (final child in node.nodes) {
    if (child is dom.Text) {
      _parseText(child.text, elements);
      continue;
    }

    if (child is! dom.Element) {
      continue;
    }
    if (child.localName == 'rp') {
      continue;
    }
    // br は HTML 上の意味が改行で確定しているため newLine として扱う。
    if (child.localName == 'br') {
      elements.add(NovelContentElement.newLine());
      continue;
    }
    // 画像は対応する本文要素と実HTMLの表現が未確認のため推測で変換しない。
    if (child.localName == 'img') {
      continue;
    }
    if (child.localName == 'ruby') {
      final rb = _directChild(child, 'rb');
      final rt = _directChild(child, 'rt');
      final base = rb?.text.trim();
      final ruby = rt?.text.trim();
      if (base != null && base.isNotEmpty && ruby != null && ruby.isNotEmpty) {
        elements.add(NovelContentElement.rubyText(base, ruby));
      } else {
        _parseNodes(child, elements);
      }
      continue;
    }
    _parseNodes(child, elements);
  }
}

dom.Element? _directChild(dom.Element parent, String localName) {
  for (final child in parent.children) {
    if (child.localName == localName) {
      return child;
    }
  }
  return null;
}

void _parseText(String text, List<NovelContentElement> elements) {
  final parts = text.split(RegExp(r'\r\n|\r|\n'));
  for (var index = 0; index < parts.length; index++) {
    if (parts[index].isNotEmpty) {
      elements.add(NovelContentElement.plainText(parts[index]));
    }
    if (index < parts.length - 1) {
      elements.add(NovelContentElement.newLine());
    }
  }
}
