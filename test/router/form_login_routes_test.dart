import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/router/router.dart';

void main() {
  final routes = [
    (const AlphapolisLoginRoute(), '/more/alphapolis-login'),
    (const HamelnLoginRoute(), '/more/hameln-login'),
    (const NovelupLoginRoute(), '/more/novelup-login'),
  ];

  for (final (route, location) in routes) {
    test('$location を型安全routeで解決できる', () {
      expect(route.location, location);
      expect(
        router.configuration.findMatch(Uri.parse(location)).isError,
        isFalse,
      );
    });
  }
}
