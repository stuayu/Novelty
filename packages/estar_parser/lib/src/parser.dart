import 'package:novel_parser_core/novel_parser_core.dart';

final _rubyPattern = RegExp(r'\|([^\n《》]+)《([^\n《》]+)》');
final _emphasisPattern = RegExp(r'《《([^\n]*?)》》');
final _imageLinePattern = RegExp(
  r'^[ \t]*!\[.*\]\(.*\)[ \t]*$',
  multiLine: true,
);

/// エブリスタのGraphQLレスポンスに含まれる本文プレーンテキストをパースする。
List<NovelContentElement> parseEstarEpisodeBody(String body) {
  final bodyWithoutImages = body.replaceAll(_imageLinePattern, '');
  final normalizedBody = bodyWithoutImages.replaceAllMapped(
    _emphasisPattern,
    (match) => match.group(1)!,
  );
  if (normalizedBody.trim().isEmpty) {
    throw const FormatException('エブリスタの本文が空です');
  }
  final elements = <NovelContentElement>[];
  var offset = 0;
  for (final match in _rubyPattern.allMatches(normalizedBody)) {
    if (match.start > offset) {
      _addPlainText(
        normalizedBody.substring(offset, match.start),
        elements,
      );
    }
    elements.add(
      NovelContentElement.rubyText(match.group(1)!, match.group(2)!),
    );
    offset = match.end;
  }
  if (offset < normalizedBody.length) {
    _addPlainText(normalizedBody.substring(offset), elements);
  }
  return elements;
}

void _addPlainText(String text, List<NovelContentElement> elements) {
  final lines = text.split('\n');
  for (var index = 0; index < lines.length; index++) {
    if (lines[index].isNotEmpty) {
      elements.add(NovelContentElement.plainText(lines[index]));
    }
    if (index < lines.length - 1) {
      elements.add(NovelContentElement.newLine());
    }
  }
}
