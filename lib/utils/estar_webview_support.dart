import 'package:flutter/foundation.dart';

/// エブリスタアカウント連携用WebViewを利用できるプラットフォームか。
bool get isEstarWebViewSupported {
  if (kIsWeb) return false;

  return switch (defaultTargetPlatform) {
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => true,
    TargetPlatform.linux || TargetPlatform.fuchsia => false,
  };
}
