// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auth_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// なろうの認証状態を管理するプロバイダー。
///
/// `null` = 未ログイン、`NarouUser` = ログイン済み。

@ProviderFor(Auth)
final authProvider = AuthProvider._();

/// なろうの認証状態を管理するプロバイダー。
///
/// `null` = 未ログイン、`NarouUser` = ログイン済み。
final class AuthProvider extends $AsyncNotifierProvider<Auth, NarouUser?> {
  /// なろうの認証状態を管理するプロバイダー。
  ///
  /// `null` = 未ログイン、`NarouUser` = ログイン済み。
  AuthProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'authProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$authHash();

  @$internal
  @override
  Auth create() => Auth();
}

String _$authHash() => r'53492c06411995471f5a431840e5e3fb810f7221';

/// なろうの認証状態を管理するプロバイダー。
///
/// `null` = 未ログイン、`NarouUser` = ログイン済み。

abstract class _$Auth extends $AsyncNotifier<NarouUser?> {
  FutureOr<NarouUser?> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<NarouUser?>, NarouUser?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<NarouUser?>, NarouUser?>,
              AsyncValue<NarouUser?>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
