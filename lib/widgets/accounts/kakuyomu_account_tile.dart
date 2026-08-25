import 'package:flutter/material.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/widgets/accounts/account_tile.dart';

/// 「もっと」画面に表示するカクヨムアカウント欄。
class KakuyomuAccountTile extends StatelessWidget {
  /// コンストラクタ。
  const KakuyomuAccountTile({super.key});

  @override
  Widget build(BuildContext context) => AccountTile(
    configuration: accountTileConfigurationFor(NovelSource.kakuyomu)!,
  );
}
