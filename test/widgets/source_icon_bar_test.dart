import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/widgets/source_icon_bar.dart';

void main() {
  group('SourceIconBar', () {
    Widget buildSubject({
      NovelSource? selected = NovelSource.narou,
      String? allLabel,
      ValueChanged<NovelSource?>? onChanged,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: SourceIconBar(
            sources: NovelSource.values,
            selected: selected,
            onChanged: onChanged ?? (_) {},
            allLabel: allLabel,
          ),
        ),
      );
    }

    testWidgets('全サイトが短縮名で横並びに表示される', (tester) async {
      await tester.pumpWidget(buildSubject());

      for (final source in NovelSource.values) {
        expect(
          find.text(source.shortLabel),
          findsOneWidget,
          reason: '${source.label} のボタンが見つからない',
        );
      }
    });

    testWidgets('サイトを押すとonChangedにそのサイトが渡る', (tester) async {
      NovelSource? changed;
      await tester.pumpWidget(buildSubject(onChanged: (s) => changed = s));

      await tester.tap(find.text(NovelSource.kakuyomu.shortLabel));
      await tester.pumpAndSettle();

      expect(changed, NovelSource.kakuyomu);
    });

    /// 選択状態のチップのラベルを集める。
    List<String> selectedLabels(WidgetTester tester) {
      final colors = ThemeData().colorScheme;
      return tester
          .widgetList<Text>(find.byType(Text))
          .where(
            (text) =>
                text.style?.fontWeight == FontWeight.bold &&
                text.style?.color == colors.onSecondaryContainer,
          )
          .map((text) => text.data!)
          .toList();
    }

    testWidgets('選択中のサイトだけが強調表示になる', (tester) async {
      await tester.pumpWidget(buildSubject(selected: NovelSource.estar));

      expect(selectedLabels(tester), [NovelSource.estar.shortLabel]);
    });

    testWidgets('allLabel指定時は先頭に「すべて」が並びnullを渡せる', (tester) async {
      NovelSource? changed = NovelSource.narou;
      var called = false;
      await tester.pumpWidget(
        buildSubject(
          allLabel: 'すべて',
          onChanged: (s) {
            called = true;
            changed = s;
          },
        ),
      );

      expect(find.text('すべて'), findsOneWidget);

      await tester.tap(find.text('すべて'));
      await tester.pumpAndSettle();

      expect(called, isTrue);
      expect(changed, isNull);
    });

    testWidgets('allLabel未指定なら「すべて」は並ばない', (tester) async {
      await tester.pumpWidget(buildSubject());

      expect(find.text('すべて'), findsNothing);
    });

    testWidgets('selectedがnullなら「すべて」が強調表示になる', (tester) async {
      await tester.pumpWidget(
        buildSubject(selected: null, allLabel: 'すべて'),
      );

      expect(selectedLabels(tester), ['すべて']);
    });

    testWidgets('iPhone SEの幅でも全サイトが横に収まり見切れない', (tester) async {
      // iPhone SE (第2・第3世代) の論理解像度。
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(buildSubject(allLabel: 'すべて'));

      // 「すべて」+ 全サイトが1つ残らず描画されていること。
      expect(find.text('すべて'), findsOneWidget);
      for (final source in NovelSource.values) {
        expect(find.text(source.shortLabel), findsOneWidget);
      }

      // どのボタンも画面幅からはみ出していないこと。
      final chips = find.byType(InkWell);
      expect(chips, findsNWidgets(NovelSource.values.length + 1));
      for (var i = 0; i < NovelSource.values.length + 1; i++) {
        final rect = tester.getRect(chips.at(i));
        expect(
          rect.left,
          greaterThanOrEqualTo(-0.01),
          reason: '$i番目のボタンが左にはみ出している',
        );
        expect(
          rect.right,
          lessThanOrEqualTo(375.01),
          reason: '$i番目のボタンが右にはみ出している',
        );
        expect(rect.width, greaterThan(0));
      }
    });

    testWidgets('横スクロールせず1行に並ぶ', (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(buildSubject(allLabel: 'すべて'));

      // スクロール可能にすると狭い端末で右端が隠れるため使わない。
      expect(find.byType(Scrollable), findsNothing);
    });
  });
}
