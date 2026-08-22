import 'package:flutter/foundation.dart';

/// カクヨムアカウント連携用 WebView を利用できるプラットフォームか。
bool get isKakuyomuWebViewSupported {
  if (kIsWeb) return false;

  return switch (defaultTargetPlatform) {
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => true,
    TargetPlatform.linux || TargetPlatform.fuchsia => false,
  };
}
