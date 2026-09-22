/// 源订阅的拉取与校验。
///
/// 对应实测行为（见 `.workbuddy-ai/tmp/x1probe/API-CONTRACT.md`）：
///   1. `GET <源地址>`（形如 `http://user:pass@host/index.js.md5`）→ 32 字节 MD5 十六进制
///   2. 把地址尾部 `.md5` 去掉 → `GET <index.js>` → **302** 到 CDN 对象
///      （`content-type` 伪装为 `image/jpeg`）
///   3. 跟随后得到正文（实测 6,487,338 B JavaScript）
///   4. `md5(正文) == 第 1 步的指针` → 通过
///
/// 若第 1 步拿到的不是 32 位十六进制，说明该地址本身就是正文（不是 `.md5` 指针），
/// 此时直接使用其内容并跳过校验。
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// 一次拉取的结果。
class FetchedSource {
  /// 是否发生了更新（指针变化或首次拉取）。
  final bool updated;
  /// 源正文（JavaScript）。
  final String body;
  /// 内容 MD5。
  final String md5;
  /// 是否经过 MD5 校验通过。
  final bool verified;
  /// 原始请求到的最终 URL（跟随重定向后）。
  final String finalUrl;

  const FetchedSource({
    required this.updated,
    required this.body,
    required this.md5,
    required this.verified,
    required this.finalUrl,
  });
}

class SourceFetchException implements Exception {
  final String message;
  final int? statusCode;

  const SourceFetchException(this.message, {this.statusCode});

  @override
  String toString() => statusCode == null
      ? 'SourceFetchException: $message'
      : 'SourceFetchException($statusCode): $message';
}

/// 源订阅的拉取器。
class SourceFetcher {
  /// 超时。源正文约 6.5 MB，国内 CDN 拉取给足时间。
  static const _timeout = Duration(seconds: 60);

  /// 浏览器 UA —— 部分 CDN 会对空 UA / curl 返回 403（E2 实测）。
  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

  final http.Client _client;

  SourceFetcher({http.Client? client}) : _client = client ?? http.Client();

  void dispose() => _client.close();

  /// 拉取源。
  ///
  /// [knownMd5] 为本地已缓存内容的 MD5；若与服务端指针一致则跳过正文下载，
  /// 返回 `updated == false` 和空的 [FetchedSource.body]。
  Future<FetchedSource> fetch(String sourceUrl, {String? knownMd5}) async {
    final uri = _parse(sourceUrl);

    // 1) 拉取指针（或正文）
    final first = await _get(uri);
    if (first.statusCode != 200) {
      throw SourceFetchException(
        '拉取源地址失败：HTTP ${first.statusCode}',
        statusCode: first.statusCode,
      );
    }
    final firstText = _decodeBody(first);
    final pointer = _normalizeMd5(firstText);

    // 地址本身就是正文（返回的不是 32 位 MD5）
    if (pointer == null) {
      final md5 = _md5Of(first.bodyBytes);
      final updated = md5 != knownMd5;
      return FetchedSource(
        updated: updated,
        body: updated ? firstText : '',
        md5: md5,
        verified: true,
        finalUrl: first.request?.url.toString() ?? uri.toString(),
      );
    }

    // 指针未变 → 无需下载正文
    if (knownMd5 != null && knownMd5 == pointer) {
      return FetchedSource(
        updated: false,
        body: '',
        md5: pointer,
        verified: true,
        finalUrl: uri.toString(),
      );
    }

    // 2) 拉正文（去掉 .md5 后缀）
    final bodyUri = _stripMd5Suffix(uri);
    final second = await _followRedirects(bodyUri);

    final realMd5 = _md5Of(second.bodyBytes);
    final verified = realMd5 == pointer;
    if (!verified) {
      throw SourceFetchException(
        '正文 MD5 与指针不一致：指针=$pointer 实际=$realMd5',
      );
    }

    return FetchedSource(
      updated: true,
      body: _decodeBody(second),
      md5: realMd5,
      verified: true,
      finalUrl: second.request?.url.toString() ?? bodyUri.toString(),
    );
  }

  // -------------------------------------------------------------------------
  // 内部
  // -------------------------------------------------------------------------

  /// 手工跟随 302 / 301 / 307 / 308，最多 5 跳。
  ///
  /// 为什么不用 `http` 包的自动重定向：`index.js` 会 302 到 CDN 上的 `.jpg`
  /// 对象，需要保留对 `Location` 的可见性以便诊断；且跨域重定向时部分实现会
  /// 丢弃连接。这里显式跟随，行为可预测。
  Future<http.Response> _followRedirects(Uri uri, {int depth = 0}) async {
    if (depth > 5) {
      throw const SourceFetchException('重定向次数过多（>5）');
    }
    var resp = await _get(uri, followRedirects: false);
    final code = resp.statusCode;
    if (code == 301 || code == 302 || code == 303 || code == 307 || code == 308) {
      final loc = resp.headers['location'];
      if (loc == null || loc.isEmpty) {
        throw SourceFetchException('收到 $code 但缺少 Location 头');
      }
      final next = uri.resolve(loc);
      return _followRedirects(next, depth: depth + 1);
    }
    return resp;
  }

  Future<http.Response> _get(Uri uri, {bool followRedirects = true}) async {
    try {
      final req = http.Request('GET', uri)
        ..followRedirects = followRedirects
        ..headers['User-Agent'] = _ua
        ..headers['Accept'] = '*/*';
      final streamed = await _client.send(req).timeout(_timeout);
      return await http.Response.fromStream(streamed).timeout(_timeout);
    } on SocketException catch (e) {
      throw SourceFetchException('网络不可达：${e.message}');
    } on HttpException catch (e) {
      throw SourceFetchException('HTTP 错误：${e.message}');
    }
  }

  Uri _parse(String s) {
    final trimmed = s.trim();
    if (trimmed.isEmpty) {
      throw const SourceFetchException('源地址为空');
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const SourceFetchException('源地址格式无效（需含 http:// 或 https://）');
    }
    return uri;
  }

  /// `…/index.js.md5` → `…/index.js`
  Uri _stripMd5Suffix(Uri uri) {
    final p = uri.path;
    if (!p.endsWith('.md5')) return uri;
    return uri.replace(path: p.substring(0, p.length - 4));
  }

  /// 若文本是 32 位十六进制（可带空白）则返回小写形式，否则返回 null。
  static String? _normalizeMd5(String text) {
    final t = text.trim().toLowerCase();
    if (t.length != 32) return null;
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(t)) return null;
    return t;
  }

  static String _md5Of(List<int> bytes) => md5.convert(bytes).toString();

  /// 正文按 UTF-8 解码；解码失败时退回 latin1 以免丢数据。
  static String _decodeBody(http.Response r) {
    try {
      return utf8.decode(r.bodyBytes);
    } catch (_) {
      return latin1.decode(r.bodyBytes);
    }
  }
}
