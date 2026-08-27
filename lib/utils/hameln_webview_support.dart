import 'package:flutter/foundation.dart';

/// ハーメルンアカウント連携用WebViewを利用できるプラットフォームか。
bool get isHamelnWebViewSupported {
  if (kIsWeb) return false;

  return switch (defaultTargetPlatform) {
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => true,
    TargetPlatform.linux || TargetPlatform.fuchsia => false,
  };
}
