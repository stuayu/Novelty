import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/sites/account_sync_registry.dart';
import 'package:novelty/sites/estar/estar_account_sync_adapter.dart';
import 'package:novelty/sites/novel_source.dart';

void main() {
  test('エブリスタ認証アダプターを既定レジストリへ登録する', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(accountSyncRegistryProvider)[NovelSource.estar],
      isA<EstarAccountSyncAdapter>(),
    );
  });
}
