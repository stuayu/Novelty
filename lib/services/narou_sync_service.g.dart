// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'narou_sync_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// なろう同期サービスのプロバイダー。

@ProviderFor(narouSyncService)
const narouSyncServiceProvider = NarouSyncServiceProvider._();

/// なろう同期サービスのプロバイダー。

final class NarouSyncServiceProvider
    extends
        $FunctionalProvider<
          NarouSyncService,
          NarouSyncService,
          NarouSyncService
        >
    with $Provider<NarouSyncService> {
  /// なろう同期サービスのプロバイダー。
  const NarouSyncServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'narouSyncServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$narouSyncServiceHash();

  @$internal
  @override
  $ProviderElement<NarouSyncService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  NarouSyncService create(Ref ref) {
    return narouSyncService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(NarouSyncService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<NarouSyncService>(value),
    );
  }
}

String _$narouSyncServiceHash() => r'434959badb0803145325aeed8d315ab8967ac342';
