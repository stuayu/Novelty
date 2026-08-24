import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/sites/alphapolis/alphapolis_site.dart';
import 'package:novelty/sites/estar/estar_site.dart';
import 'package:novelty/sites/hameln/hameln_site.dart';
import 'package:novelty/sites/kakuyomu/kakuyomu_site.dart';
import 'package:novelty/sites/narou/narou_site.dart';
import 'package:novelty/sites/novel_site_registry.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:riverpod/riverpod.dart';

void main() {
  group('novelSiteRegistry', () {
    test('narou が登録されており実装は NarouSite', () {
      expect(defaultNovelSiteRegistry.keys, contains(NovelSource.narou));
      expect(defaultNovelSiteRegistry[NovelSource.narou], isA<NarouSite>());
    });

    test('kakuyomu が登録されており実装は KakuyomuSite', () {
      expect(defaultNovelSiteRegistry.keys, contains(NovelSource.kakuyomu));
      expect(
        defaultNovelSiteRegistry[NovelSource.kakuyomu],
        isA<KakuyomuSite>(),
      );
    });

    test('alphapolis が登録されており実装は AlphapolisSite', () {
      expect(defaultNovelSiteRegistry.keys, contains(NovelSource.alphapolis));
      expect(
        defaultNovelSiteRegistry[NovelSource.alphapolis],
        isA<AlphapolisSite>(),
      );
    });

    test('hameln が登録されており実装は HamelnSite', () {
      expect(defaultNovelSiteRegistry.keys, contains(NovelSource.hameln));
      expect(defaultNovelSiteRegistry[NovelSource.hameln], isA<HamelnSite>());
    });

    test('estar が既定レジストリとプロバイダに登録されている', () {
      expect(defaultNovelSiteRegistry[NovelSource.estar], isA<EstarSite>());

      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(novelSiteRegistryProvider)[NovelSource.estar],
        isA<EstarSite>(),
      );
    });

    test('登録エントリは5件', () {
      expect(defaultNovelSiteRegistry, hasLength(5));
    });

    test('登録済みエントリのキーと実装の source が一致する', () {
      for (final entry in defaultNovelSiteRegistry.entries) {
        expect(entry.value.source, entry.key);
      }
    });
  });
}
