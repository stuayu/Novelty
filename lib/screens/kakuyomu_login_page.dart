import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:novelty/services/kakuyomu_auth_service.dart';
import 'package:novelty/services/kakuyomu_web_cookie_service.dart';

const _kakuyomuLoginUrl = 'https://kakuyomu.jp/auth/login';

/// カクヨム公式ログイン画面を表示し、ログイン済み Cookie を保存する画面。
class KakuyomuLoginPage extends ConsumerStatefulWidget {
  /// コンストラクタ。
  const KakuyomuLoginPage({super.key});

  @override
  ConsumerState<KakuyomuLoginPage> createState() => _KakuyomuLoginPageState();
}

class _KakuyomuLoginPageState extends ConsumerState<KakuyomuLoginPage> {
  bool _isPreparing = true;
  bool _isCheckingLogin = false;
  bool _isCompleted = false;
  String? _errorMessage;

  bool get _isSupportedPlatform {
    if (kIsWeb) return false;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => true,
      TargetPlatform.linux || TargetPlatform.fuchsia => false,
    };
  }

  @override
  void initState() {
    super.initState();
    if (_isSupportedPlatform) {
      _prepareSession();
    } else {
      _isPreparing = false;
    }
  }

  Future<void> _prepareSession() async {
    try {
      await ref.read(kakuyomuWebCookieServiceProvider).restoreToWebView();
    } on Exception {
      // Cookie 復元に失敗しても新規ログインは可能なので画面表示を続行する。
    }

    if (!mounted) return;
    setState(() => _isPreparing = false);
  }

  Future<void> _tryCompleteLogin(WebUri? currentUrl) async {
    if (_isCheckingLogin || _isCompleted || currentUrl == null) return;

    final uri = Uri.tryParse(currentUrl.toString());
    if (uri == null || !uri.host.endsWith('kakuyomu.jp')) return;

    // 認証画面の途中ではセッション検証を行わない。
    if (uri.path.startsWith('/auth/login') || uri.path == '/login') return;

    setState(() {
      _isCheckingLogin = true;
      _errorMessage = null;
    });

    try {
      final webCookieService = ref.read(kakuyomuWebCookieServiceProvider);
      final cookies = await webCookieService.captureFromWebView();
      if (cookies.isEmpty) {
        return;
      }

      final authService = ref.read(kakuyomuAuthServiceProvider);
      final isValid = await authService.isSessionValid();
      if (!isValid) {
        return;
      }

      _isCompleted = true;
      ref.invalidate(kakuyomuSessionValidProvider);

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on Exception {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'ログイン状態を確認できませんでした。もう一度お試しください。';
      });
    } finally {
      if (mounted && !_isCompleted) {
        setState(() => _isCheckingLogin = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isSupportedPlatform) {
      return Scaffold(
        appBar: AppBar(title: const Text('カクヨムアカウント')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'カクヨムアカウント連携は現在このOSでは利用できません。',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('カクヨムにログイン')),
      body: Column(
        children: [
          if (_errorMessage != null)
            MaterialBanner(
              content: Text(_errorMessage!),
              actions: [
                TextButton(
                  onPressed: () => setState(() => _errorMessage = null),
                  child: const Text('閉じる'),
                ),
              ],
            ),
          if (_isCheckingLogin) const LinearProgressIndicator(),
          Expanded(
            child: _isPreparing
                ? const Center(child: CircularProgressIndicator())
                : InAppWebView(
                    initialUrlRequest: URLRequest(
                      url: WebUri(_kakuyomuLoginUrl),
                    ),
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      thirdPartyCookiesEnabled: true,
                    ),
                    onLoadStop: (controller, url) async {
                      await _tryCompleteLogin(url);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
