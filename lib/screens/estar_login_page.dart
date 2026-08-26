import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:novelty/providers/auth_provider.dart';
import 'package:novelty/services/estar_auth_service.dart';
import 'package:novelty/services/estar_web_cookie_service.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/utils/estar_webview_support.dart';

const _estarLoginUrl = 'https://estar.jp/login';

/// エブリスタ公式ログイン画面を表示し、完了後のCookieを保存する画面。
class EstarLoginPage extends ConsumerStatefulWidget {
  /// コンストラクタ。
  const EstarLoginPage({super.key});

  @override
  ConsumerState<EstarLoginPage> createState() => _EstarLoginPageState();
}

class _EstarLoginPageState extends ConsumerState<EstarLoginPage> {
  bool _isPreparing = true;
  bool _isCompleting = false;
  bool _isCompleted = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (isEstarWebViewSupported) {
      unawaited(_prepareSession());
    } else {
      _isPreparing = false;
    }
  }

  Future<void> _prepareSession() async {
    try {
      await ref.read(estarWebCookieServiceProvider).restoreToWebView();
    } on Exception {
      // Cookieを復元できなくても、新規ログインは続行できる。
    }

    if (!mounted) return;
    setState(() => _isPreparing = false);
  }

  Future<void> _tryCompleteLogin(WebUri? currentUrl) async {
    if (_isCompleting || _isCompleted) {
      return;
    }

    final webCookieService = ref.read(estarWebCookieServiceProvider);
    if (!isEstarLoginCompleteUrl(currentUrl)) return;

    try {
      setState(() {
        _isCompleting = true;
        _errorMessage = null;
      });

      final captured = await captureEstarLoginIfCompleted(
        currentUrl,
        webCookieService,
      );
      if (!captured ||
          !await ref.read(estarAuthServiceProvider).isSessionValid()) {
        throw StateError('ログイン完了後のCookieを取得できませんでした');
      }

      _isCompleted = true;
      ref.invalidate(accountAuthStateProvider(NovelSource.estar));
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on Exception {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'ログイン情報を保存できませんでした。もう一度お試しください。';
      });
    } finally {
      if (mounted && !_isCompleted) {
        setState(() => _isCompleting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!isEstarWebViewSupported) {
      return Scaffold(
        appBar: AppBar(title: const Text('エブリスタアカウント')),
        body: const Center(
          child: Text('エブリスタアカウント連携は現在このOSでは利用できません。'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('エブリスタにログイン')),
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
          if (_isCompleting) const LinearProgressIndicator(),
          Expanded(
            child: _isPreparing
                ? const Center(child: CircularProgressIndicator())
                : InAppWebView(
                    initialUrlRequest: URLRequest(
                      url: WebUri(_estarLoginUrl),
                    ),
                    initialSettings: InAppWebViewSettings(),
                    onLoadStop: (controller, url) async {
                      await _tryCompleteLogin(url);
                    },
                    onUpdateVisitedHistory:
                        (controller, url, androidIsReload) async {
                          await _tryCompleteLogin(url);
                        },
                  ),
          ),
        ],
      ),
    );
  }
}
