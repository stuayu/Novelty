import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:novel_parser_core/novel_parser_core.dart';

/// アルファポリスのエピソード本文HTMLをパースする。
List<NovelContentElement> parseAlphapolisEpisodeBody(String html) {
  final fragment = html_parser.parseFragment(html);
  final selectedBody = fragment.querySelector('#novelBody');
  final isEpisodePage =
      fragment.querySelector(
        '.p-novel-episode__title, '
        '.p-novel-episode__episode-title, '
        '.p-novel-episode__text',
      ) !=
      null;
  if (selectedBody == null && isEpisodePage) {
    throw const FormatException(
      'アルファポリスのエピソードページに #novelBody がありません',
    );
  }

  final body = selectedBody ?? fragment;
  final elements = <NovelContentElement>[];
  _parseNodes(body, elements);
  if (!elements.any((element) => element is PlainText || element is RubyText)) {
    throw const FormatException('アルファポリスの本文が空です');
  }
  return elements;
}

void _parseNodes(dom.Node node, List<NovelContentElement> elements) {
  for (final child in node.nodes) {
    if (child is dom.Text) {
      final text = child.text
          .replaceFirst(RegExp(r'^[\r\n\t ]+'), '')
          .replaceFirst(RegExp(r'[\r\n\t ]+$'), '');
      if (text.isNotEmpty) {
        elements.add(NovelContentElement.plainText(text));
      }
      continue;
    }

    if (child is dom.Element && child.localName == 'br') {
      elements.add(NovelContentElement.newLine());
      continue;
    }

    if (child is dom.Element && child.localName == 'ruby') {
      final ruby = child.querySelector('rt')?.text.trim();
      final base = child.nodes
          .where(
            (node) => node is! dom.Element || node.localName != 'rt',
          )
          .map((node) => node.text)
          .join()
          .trim();
      if (base.isNotEmpty && ruby != null && ruby.isNotEmpty) {
        elements.add(NovelContentElement.rubyText(base, ruby));
      } else {
        _parseNodes(child, elements);
      }
      continue;
    }

    _parseNodes(child, elements);
  }
}
