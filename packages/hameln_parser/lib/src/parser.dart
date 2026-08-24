import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:novel_parser_core/novel_parser_core.dart';

/// ハーメルンのエピソード本文HTMLをパースする。
List<NovelContentElement> parseHamelnEpisodeBody(String html) {
  final document = html_parser.parse(html);
  final body = document.querySelector('#honbun');
  if (body == null) {
    throw const FormatException(
      'ハーメルンのエピソードページに #honbun がありません',
    );
  }

  final elements = <NovelContentElement>[];
  for (final child in body.children) {
    if (child.localName == 'p') {
      if (child.text.trim().isNotEmpty) {
        _parseNodes(child, elements);
      }
      elements.add(NovelContentElement.newLine());
      continue;
    }
    if (child.localName == 'hr' && child.classes.contains('separator')) {
      elements.add(NovelContentElement.newLine());
    }
  }
  if (!elements.any((element) => element is PlainText || element is RubyText)) {
    throw const FormatException('ハーメルンの本文が空です');
  }
  return elements;
}

void _parseNodes(dom.Node node, List<NovelContentElement> elements) {
  for (final child in node.nodes) {
    if (child is dom.Text) {
      if (child.text.isNotEmpty) {
        elements.add(NovelContentElement.plainText(child.text));
      }
      continue;
    }

    if (child is! dom.Element) {
      continue;
    }
    if (child.localName == 'rp') {
      continue;
    }
    // br は HTML 上の意味が改行で確定しているため、無視すると行が繋がって
    // 本文が欠ける。実HTMLでの出現は未確認だが newLine として扱う。
    if (child.localName == 'br') {
      elements.add(NovelContentElement.newLine());
      continue;
    }
    // 画像は NovelContentElement に対応する型がなく、実HTMLでの表現も未確認のため
    // 推測して本文へ潰さない。
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
