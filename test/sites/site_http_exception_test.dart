import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/sites/alphapolis/alphapolis_site.dart';
import 'package:novelty/sites/estar/estar_site.dart';
import 'package:novelty/sites/hameln/hameln_site.dart';
import 'package:novelty/sites/kakuyomu/kakuyomu_site.dart';
import 'package:novelty/sites/novel_site.dart';
import 'package:novelty/sites/novelup/novelup_site.dart';

void main() {
  test('サイトHTTP例外はステータスと機密を含まないルートを公開する', () {
    final errors = <SiteDiagnosticException>[
      const AlphapolisHttpException(
        503,
        'https://www.alphapolis.co.jp/api/list?token=secret',
      ),
      const KakuyomuHttpException(
        403,
        'https://kakuyomu.jp/api/list?token=secret',
      ),
      const HamelnHttpException(
        429,
        'https://syosetu.org/api/list?token=secret',
      ),
      const EstarHttpException(
        502,
        'https://estar.jp/api/graphql?token=secret',
        method: 'POST',
      ),
      const NovelupHttpException(
        404,
        'https://novelup.plus/api/list?token=secret',
      ),
    ];

    for (final error in errors) {
      expect(error.safeDiagnosticFields['httpStatusCode'], isA<int>());
      expect(
        error.safeDiagnosticFields['requestRoute'],
        isNot(contains('secret')),
      );
      expect(error.safeDiagnosticFields['requestRoute'], isNot(contains('?')));
    }
    expect(errors[3].safeDiagnosticFields['requestMethod'], 'POST');
  });
}
