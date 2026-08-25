// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auth_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// なろうのログイン処理を管理するコントローラー。

@ProviderFor(NarouLogin)
final narouLoginProvider = NarouLoginProvider._();

/// なろうのログイン処理を管理するコントローラー。
final class NarouLoginProvider
    extends $AsyncNotifierProvider<NarouLogin, void> {
  /// なろうのログイン処理を管理するコントローラー。
  NarouLoginProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'narouLoginProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$narouLoginHash();

  @$internal
  @override
  NarouLogin create() => NarouLogin();
}

String _$narouLoginHash() => r'611cac2acb3cdb42bab26f4eaa4accff3bf2f1d5';

/// なろうのログイン処理を管理するコントローラー。

abstract class _$NarouLogin extends $AsyncNotifier<void> {
  FutureOr<void> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<void>, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<void>, void>,
              AsyncValue<void>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
