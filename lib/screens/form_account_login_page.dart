import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:novelty/providers/auth_provider.dart';
import 'package:novelty/services/form_post_auth_service.dart';
import 'package:novelty/sites/novel_source.dart';

/// サイト別ログイン処理。
typedef FormAccountLogin =
    Future<FormAuthLoginResult> Function(
      String accountId,
      String password,
    );

/// フォームPOST認証サイト共通のログイン画面。
class FormAccountLoginPage extends ConsumerStatefulWidget {
  /// コンストラクタ。
  const FormAccountLoginPage({
    required this.source,
    required this.title,
    required this.accountLabel,
    required this.login,
    super.key,
  });

  /// 対象サイト。
  final NovelSource source;

  /// 画面タイトル。
  final String title;

  /// アカウント入力欄ラベル。
  final String accountLabel;

  /// サイト別ログイン処理。
  final FormAccountLogin login;

  @override
  ConsumerState<FormAccountLoginPage> createState() =>
      _FormAccountLoginPageState();
}

class _FormAccountLoginPageState extends ConsumerState<FormAccountLoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _accountController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _accountController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final result = await widget.login(
      _accountController.text.trim(),
      _passwordController.text,
    );
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.isSuccess) {
      ref.invalidate(accountAuthStateProvider(widget.source));
      Navigator.of(context).pop(true);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.error ?? 'ログインに失敗しました'),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                TextFormField(
                  controller: _accountController,
                  decoration: InputDecoration(
                    labelText: widget.accountLabel,
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.person),
                  ),
                  keyboardType: widget.accountLabel == 'メールアドレス'
                      ? TextInputType.emailAddress
                      : TextInputType.text,
                  autofillHints: const [AutofillHints.username],
                  validator: (value) => value == null || value.trim().isEmpty
                      ? '${widget.accountLabel}を入力してください'
                      : null,
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
                      onPressed: () => setState(
                        () => _obscurePassword = !_obscurePassword,
                      ),
                    ),
                  ),
                  obscureText: _obscurePassword,
                  autofillHints: const [AutofillHints.password],
                  validator: (value) =>
                      value == null || value.isEmpty ? 'パスワードを入力してください' : null,
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: _isLoading ? null : _handleLogin,
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('ログイン'),
                ),
                const SizedBox(height: 16),
                Text(
                  'ログイン成功後のセッションだけをデバイスのSecure Storageに保存します。',
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
