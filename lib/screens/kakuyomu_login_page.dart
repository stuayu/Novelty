import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:novelty/services/kakuyomu_auth_service.dart';
import 'package:novelty/services/kakuyomu_web_cookie_service.dart';
import 'package:novelty/utils/kakuyomu_uri.dart';
import 'package:novelty/utils/kakuyomu_webview_support.dart';

const _kakuyomuLoginUrl = 'https://kakuyomu.jp/auth/login';

/// カクヨム公式ログイン画面を表示し、ログイン済み Cookie を保存する画面。
class KakuyomuLoginPage extends ConsumerStatefulWidget {
  const KakuyomuLoginPage({super.key});

  @override
  ConsumerState<KakuyomuLoginPage> createState() => _KakuyomuLoginPageState();
}

class _KakuyomuLoginPageState extends ConsumerState<KakuyomuLoginPage> {
  bool _isPreparing = true;
  bool _isCheckingLogin = false;
  bool _isCompleted = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (isKakuyomuWebViewSupported) {
      unawaited(_prepareSession());
    } else {
      _isPreparing = false;
    }
  }

  Future<void> _prepareSession() async {
    try {
      await ref.read(kakuyomuWebCookieServiceProvider).restoreToWebView();
    } on Exception {}

    if (!mounted) return;
    setState(() => _isPreparing = false);
  }

  Future<void> _tryCompleteLogin(WebUri? currentUrl) async {
    if (_isCheckingLogin || _isCompleted) return;

    final webCookieService = ref.read(kakuyomuWebCookieServiceProvider);

    try {
      setState(() {
        _isCheckingLogin = true;
        _errorMessage = null;
      });

      final cookies = await webCookieService.captureFromWebView();
      if (cookies.isEmpty) return;

      final authService = ref.read(kakuyomuAuthServiceProvider);
      final isValid = await authService.isSessionValid();
      if (!isValid) return;

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
    if (!isKakuyomuWebViewSupported) {
      return Scaffold(
        appBar: AppBar(title: const Text('カクヨムアカウント')),
        body: const Center(
          child: Text('カクヨムアカウント連携は現在このOSでは利用できません。'),
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
              actions: [TextButton(onPressed: () {}, child: const Text('閉じる'))],
            ),
          if (_isCheckingLogin) const LinearProgressIndicator(),
          Expanded(
            child: _isPreparing
                ? const Center(child: CircularProgressIndicator())
                : InAppWebView(
                    initialUrlRequest: URLRequest(
                      url: WebUri(_kakuyomuLoginUrl),
                    ),
                    initialSettings: InAppWebViewSettings(),
                    onLoadStop: (controller, url) async {
                      await _tryCompleteLogin(url);
                    },
                    onUpdateVisitedHistory: (controller, url, androidIsReload) async {
                      await _tryCompleteLogin(url);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
