import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:novelty/providers/auth_provider.dart';
import 'package:novelty/services/hameln_auth_service.dart';
import 'package:novelty/services/hameln_web_cookie_service.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/utils/hameln_webview_support.dart';

const _hamelnLoginUrl = 'https://syosetu.org/?mode=login';

/// ハーメルン公式ログイン画面を表示し、ログイン済みCookieを保存する画面。
class HamelnLoginPage extends ConsumerStatefulWidget {
  /// コンストラクタ。
  const HamelnLoginPage({super.key});

  @override
  ConsumerState<HamelnLoginPage> createState() => _HamelnLoginPageState();
}

class _HamelnLoginPageState extends ConsumerState<HamelnLoginPage> {
  bool _isPreparing = true;
  bool _isCheckingLogin = false;
  bool _isCompleted = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (isHamelnWebViewSupported) {
      unawaited(_prepareSession());
    } else {
      _isPreparing = false;
    }
  }

  Future<void> _prepareSession() async {
    try {
      await ref.read(hamelnWebCookieServiceProvider).restoreToWebView();
    } on Exception {
      // WebView側Cookieを復元できなくても、新規ログインは続行できる。
    }

    if (!mounted) return;
    setState(() => _isPreparing = false);
  }

  Future<void> _tryCompleteLogin() async {
    if (_isCheckingLogin || _isCompleted) return;

    try {
      setState(() {
        _isCheckingLogin = true;
        _errorMessage = null;
      });

      final cookies = await ref
          .read(hamelnWebCookieServiceProvider)
          .captureFromWebView();
      if (cookies.isEmpty ||
          !await ref.read(hamelnAuthServiceProvider).isSessionValid()) {
        return;
      }

      _isCompleted = true;
      ref.invalidate(accountAuthStateProvider(NovelSource.hameln));
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
    if (!isHamelnWebViewSupported) {
      return Scaffold(
        appBar: AppBar(title: const Text('ハーメルンアカウント')),
        body: const Center(
          child: Text('ハーメルンアカウント連携は現在このOSでは利用できません。'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('ハーメルンにログイン')),
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
                      url: WebUri(_hamelnLoginUrl),
                    ),
                    initialSettings: InAppWebViewSettings(),
                    onLoadStop: (controller, url) async {
                      await _tryCompleteLogin();
                    },
                    onUpdateVisitedHistory:
                        (controller, url, androidIsReload) async {
                          await _tryCompleteLogin();
                        },
                  ),
          ),
        ],
      ),
    );
  }
}
