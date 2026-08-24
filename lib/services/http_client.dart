import 'package:dio/dio.dart';

/// 通信開始までの待機上限。
const noveltyConnectTimeout = Duration(seconds: 15);

/// 通信データの送受信上限。
const noveltyTransferTimeout = Duration(seconds: 30);

/// 現行サイトがブラウザ以外のUser-Agentを拒否する可能性があるため、値は現状維持。
/// 将来、サイト規約と連絡先を確認したうえで `Novelty/<version> (+<contact>)` へ変更する。
const noveltyUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/143.0.0.0 Safari/537.36';

/// Novelty全体で共有するDioを生成する。
///
/// Interceptor追加時もこの生成境界へ集約する。
Dio createNoveltyDio({
  Duration connectTimeout = noveltyConnectTimeout,
  Duration receiveTimeout = noveltyTransferTimeout,
  Duration sendTimeout = noveltyTransferTimeout,
}) {
  return Dio(
    BaseOptions(
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      sendTimeout: sendTimeout,
      headers: <String, Object>{'User-Agent': noveltyUserAgent},
    ),
  );
}
