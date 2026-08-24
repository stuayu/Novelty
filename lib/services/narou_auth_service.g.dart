// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'narou_auth_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// なろう認証サービスのプロバイダー。

@ProviderFor(narouAuthService)
final narouAuthServiceProvider = NarouAuthServiceProvider._();

/// なろう認証サービスのプロバイダー。

final class NarouAuthServiceProvider
    extends
        $FunctionalProvider<
          NarouAuthService,
          NarouAuthService,
          NarouAuthService
        >
    with $Provider<NarouAuthService> {
  /// なろう認証サービスのプロバイダー。
  NarouAuthServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'narouAuthServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$narouAuthServiceHash();

  @$internal
  @override
  $ProviderElement<NarouAuthService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  NarouAuthService create(Ref ref) {
    return narouAuthService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(NarouAuthService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<NarouAuthService>(value),
    );
  }
}

String _$narouAuthServiceHash() => r'49d578ce39919afb22036cb31545f7aa83cc616d';
