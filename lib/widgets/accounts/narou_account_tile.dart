import 'package:flutter/material.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/widgets/accounts/account_tile.dart';

/// 「もっと」画面に表示する小説家になろうアカウント欄。
class NarouAccountTile extends StatelessWidget {
  /// コンストラクタ。
  const NarouAccountTile({super.key});

  @override
  Widget build(BuildContext context) => AccountTile(
    configuration: accountTileConfigurationFor(NovelSource.narou)!,
  );
}
