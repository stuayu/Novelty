import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// User-Agent のプリセット種別。
///
/// サイト側がブラウザ以外の User-Agent を拒否することがあるため、
/// 通信時はいずれかのプリセットを名乗る。
enum UserAgentProfile {
  /// Android の Chrome。
  android,

  /// iOS の Safari。
  ios,

  /// Windows の Chrome。
  windows,

  /// macOS の Safari。
  macos,
}

/// User-Agent のプリセット一覧。
///
/// 値を差し替えたい場合はこのマップだけを編集すればアプリ全体の通信に反映される。
/// 参照箇所は `createNoveltyDio`（`lib/services/http_client.dart`）に集約されている。
const Map<UserAgentProfile, String> userAgentPresets =
    <UserAgentProfile, String>{
      UserAgentProfile.android:
          'Mozilla/5.0 (Linux; Android 15; Pixel 9) '
          'AppleWebKit/537.36 (KHTML, like Gecko) '
          'Chrome/143.0.0.0 Mobile Safari/537.36',
      UserAgentProfile.ios:
          'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) '
          'AppleWebKit/605.1.15 (KHTML, like Gecko) '
          'Version/18.5 Mobile/15E148 Safari/604.1',
      UserAgentProfile.windows:
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
          'AppleWebKit/537.36 (KHTML, like Gecko) '
          'Chrome/143.0.0.0 Safari/537.36',
      UserAgentProfile.macos:
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
          'AppleWebKit/605.1.15 (KHTML, like Gecko) '
          'Version/18.5 Safari/605.1.15',
    };

/// 実行中のプラットフォームに対応するプリセット種別。
///
/// Android から Windows の User-Agent を名乗るような不自然さを避けるため、
/// 既定では実行環境に合わせる。判定できない場合は [UserAgentProfile.windows]。
UserAgentProfile get currentUserAgentProfile {
  if (kIsWeb) return UserAgentProfile.windows;
  if (Platform.isAndroid) return UserAgentProfile.android;
  if (Platform.isIOS) return UserAgentProfile.ios;
  if (Platform.isMacOS) return UserAgentProfile.macos;
  if (Platform.isWindows) return UserAgentProfile.windows;
  // Linux などは Windows の Chrome を名乗る
  return UserAgentProfile.windows;
}

/// 既定の User-Agent。実行中のプラットフォームに対応する値を返す。
String get defaultUserAgent => userAgentPresets[currentUserAgentProfile]!;

/// 指定したプリセットの User-Agent を返す。
String userAgentFor(UserAgentProfile profile) => userAgentPresets[profile]!;
