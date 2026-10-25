import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:novelty/providers/auth_provider.dart';
import 'package:novelty/services/narou_auth_service.dart';
import 'package:url_launcher/url_launcher.dart';

/// なろうアカウントのログイン画面。
class LoginPage extends ConsumerStatefulWidget {
  /// コンストラクタ。
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _narouidController = TextEditingController();
  final _passwordController = TextEditingController();
  final _mfaCodeController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _awaitingMfa = false;
  bool _rememberSession = true;
  late final void Function() _cancelMfaChallenge;

  @override
  void initState() {
    super.initState();
    _cancelMfaChallenge = ref
        .read(narouLoginProvider.notifier)
        .cancelMfaChallenge;
  }

  @override
  void dispose() {
    _cancelMfaChallenge();
    _narouidController.dispose();
    _passwordController.dispose();
    _mfaCodeController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    // 例外が出てもインジケータを必ず解除する。
    // finally が無いとログイン失敗時に進捗表示が回り続ける。
    NarouLoginResult result;
    try {
      final login = ref.read(narouLoginProvider.notifier);
      result = _awaitingMfa
          ? await login.verifyMfaCode(_mfaCodeController.text)
          : await login.login(
              narouid: _narouidController.text.trim(),
              password: _passwordController.text,
              rememberSession: _rememberSession,
            );
    } on Object {
      result = const NarouLoginResult.failure('ログイン処理に失敗しました');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }

    if (!mounted) return;
    if (_awaitingMfa) _mfaCodeController.clear();

    if (result.requiresMfa) {
      setState(() => _awaitingMfa = true);
      _narouidController.clear();
      _passwordController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('登録メールまたは認証アプリの確認コードを入力してください')),
      );
      return;
    }

    if (result.isSuccess) {
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.shouldSuggestAuthenticatorApp
                ? '${result.username} でログインしました。次回に備えて認証アプリの設定をおすすめします。'
                : '${result.username} でログインしました',
          ),
          duration: result.shouldSuggestAuthenticatorApp
              ? const Duration(seconds: 12)
              : const Duration(seconds: 4),
          action: result.shouldSuggestAuthenticatorApp
              ? SnackBarAction(
                  label: 'TOTPを設定',
                  onPressed: () => unawaited(_openAuthenticatorSettings()),
                )
              : null,
        ),
      );
    } else {
      if (_awaitingMfa && !result.canRetryMfa) {
        _cancelMfaChallenge();
        setState(() => _awaitingMfa = false);
      }
      final colorScheme = Theme.of(context).colorScheme;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.error ?? 'ログインに失敗しました',
            style: TextStyle(color: colorScheme.onErrorContainer),
          ),
          backgroundColor: colorScheme.errorContainer,
        ),
      );
    }
  }

  void _restartLogin() {
    _cancelMfaChallenge();
    setState(() {
      _awaitingMfa = false;
      _mfaCodeController.clear();
    });
  }

  Future<void> _openAuthenticatorSettings() async {
    try {
      final opened = await launchUrl(
        Uri.parse('https://syosetu.com/personaluser2stepauth/top/'),
        mode: LaunchMode.externalApplication,
      );
      if (opened || !mounted) return;
    } on Exception {
      if (!mounted) return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('認証アプリの設定ページを開けませんでした')),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(narouLoginProvider);
    final sessionStorageNotice = _rememberSession
        ? 'ログインIDとセッション情報はSecure Storageに保存されます。'
        : 'ログインIDとセッション情報はアプリを閉じるまで保持し、終了時に破棄します。';
    return Scaffold(
      appBar: AppBar(title: const Text('なろうアカウント ログイン')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                Text(
                  'ログイン',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _awaitingMfa
                      ? '登録メールに届いた確認コード、または認証アプリのコードを入力してください。'
                      : 'なろうアカウントでログインすると、ブックマークの同期やしおりの連携ができます。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),
                if (_awaitingMfa) ...[
                  Text(
                    '二段階認証',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('narou-mfa-code'),
                    controller: _mfaCodeController,
                    decoration: const InputDecoration(
                      labelText: '認証コード',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.password),
                    ),
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    obscureText: true,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(32),
                    ],
                    validator: (value) => value == null || value.isEmpty
                        ? '認証コードを入力してください'
                        : null,
                  ),
                ] else ...[
                  TextFormField(
                    controller: _narouidController,
                    decoration: const InputDecoration(
                      labelText: 'ユーザーIDまたはメールアドレス',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.username],
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'ユーザーIDまたはメールアドレスを入力してください';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText: 'パスワード',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(
                            () => _obscurePassword = !_obscurePassword,
                          );
                        },
                      ),
                    ),
                    obscureText: _obscurePassword,
                    autofillHints: const [AutofillHints.password],
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'パスワードを入力してください';
                      }
                      return null;
                    },
                  ),
                  CheckboxListTile(
                    key: const Key('narou-remember-session'),
                    contentPadding: EdgeInsets.zero,
                    value: _rememberSession,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('この端末でログイン状態を維持'),
                    subtitle: const Text('共有端末では選択を外してください'),
                    onChanged: _isLoading
                        ? null
                        : (value) => setState(
                            () => _rememberSession = value ?? false,
                          ),
                  ),
                ],
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: _isLoading ? null : _handleLogin,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_awaitingMfa ? '認証コードを確認' : 'ログイン'),
                ),
                if (_awaitingMfa) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _isLoading ? null : _restartLogin,
                    child: const Text('最初からやり直す'),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  '$sessionStorageNotice\nパスワードと確認コードは保存しません。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
