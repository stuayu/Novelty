import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/router/router.dart';

void main() {
  test('エブリスタログイン画面を型安全routeで解決できる', () {
    const route = EstarLoginRoute();

    expect(route.location, '/more/estar-login');
    expect(
      router.configuration.findMatch(Uri.parse(route.location)).isError,
      isFalse,
    );
  });
}
