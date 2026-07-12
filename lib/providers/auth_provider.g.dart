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
const authProvider = AuthProvider._();

/// なろうの認証状態を管理するプロバイダー。
///
/// `null` = 未ログイン、`NarouUser` = ログイン済み。
final class AuthProvider extends $AsyncNotifierProvider<Auth, NarouUser?> {
  /// なろうの認証状態を管理するプロバイダー。
  ///
  /// `null` = 未ログイン、`NarouUser` = ログイン済み。
  const AuthProvider._()
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

String _$authHash() => r'8c16c280c7dda269e419d37d365e00a015b50ea6';

/// なろうの認証状態を管理するプロバイダー。
///
/// `null` = 未ログイン、`NarouUser` = ログイン済み。

abstract class _$Auth extends $AsyncNotifier<NarouUser?> {
  FutureOr<NarouUser?> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<AsyncValue<NarouUser?>, NarouUser?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<NarouUser?>, NarouUser?>,
              AsyncValue<NarouUser?>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
