import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/router/router.dart';

void main() {
  test('カクヨムログイン画面を型安全routeで解決できる', () {
    const route = KakuyomuLoginRoute();

    expect(route.location, '/more/kakuyomu-login');

    final matches = router.configuration.findMatch(Uri.parse(route.location));
    expect(matches.isError, isFalse);
  });
}
