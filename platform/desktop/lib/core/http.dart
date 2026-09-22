import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'debug_log.dart';
import 'storage.dart';

/// 统一网络层。默认 UA 与原版 1.2.5+2 一致（okhttp/5.0.0）。
class Http {
  static const defaultUa = 'okhttp/5.0.0';

  static final Dio dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 25),
    headers: {
      'User-Agent': defaultUa,
      'Accept': '*/*',
      'Connection': 'Keep-Alive',
    },
    responseType: ResponseType.bytes,
    followRedirects: true,
    validateStatus: (s) => s != null && s < 500,
  ));

  static Future<String> getText(
    String url, {
    Map<String, String>? header,
    Map<String, dynamic>? query,
    String? method,
    Object? data,
  }) async {
    final res = await dio.request<List<int>>(
      url,
      queryParameters: query,
      data: data,
      options: Options(method: method ?? 'GET', headers: header),
    );
    final bytes = Uint8List.fromList(res.data ?? const <int>[]);
    final text = await decode(bytes, res.headers.value('content-type'));
    if (Store.logEnabled) {
      DebugLog.add(
        'HTTP',
        '${method ?? 'GET'} ${res.statusCode} ${bytes.length}B  $url',
      );
    }
    return text;
  }

  /// 带状态码的文本请求 —— **任何状态码都不抛异常**，把 body 原样返回。
  ///
  /// 为什么需要它：Node 源（`index.js`）把**业务错误**编码成
  /// `HTTP 500 + {"statusCode":500,"error":"Internal Server Error","message":"…"}`。
  /// 而 [dio] 的 `validateStatus` 是 `s < 500`，500 会直接抛 `DioException`，
  /// 于是那句 `message` 被丢掉，上层只能给出「未获取到播放地址」这类笼统文案。
  ///
  /// 实测（`/spider/renren/3/play`，人人|4K 的网盘线路）：
  /// ```json
  /// {"statusCode":500,"error":"Internal Server Error",
  ///  "message":"还没有配置夸克 Cookie，请先去配置中心登录夸克"}
  /// ```
  /// 原版会把这句话原样弹给用户，所以必须读得到 body。
  static Future<({int status, String text})> getTextWithStatus(
    String url, {
    Map<String, String>? header,
    Map<String, dynamic>? query,
    String? method,
    Object? data,
  }) async {
    final res = await dio.request<List<int>>(
      url,
      queryParameters: query,
      data: data,
      options: Options(
        method: method ?? 'GET',
        headers: header,
        validateStatus: (_) => true,
      ),
    );
    final bytes = Uint8List.fromList(res.data ?? const <int>[]);
    final text = await decode(bytes, res.headers.value('content-type'));
    if (Store.logEnabled) {
      DebugLog.add(
        'HTTP',
        '${method ?? 'GET'} ${res.statusCode} ${bytes.length}B  $url',
      );
    }
    return (status: res.statusCode ?? 0, text: text);
  }

  /// 取原始字节。用于二进制资源（如 spider 载荷这种伪装成图片的 ZIP），
  /// 不能用 [getText]——那会按字符集解码，把二进制内容改坏。
  static Future<Uint8List> getBytes(
    String url, {
    Map<String, String>? header,
    Map<String, dynamic>? query,
  }) async {
    final res = await dio.request<List<int>>(
      url,
      queryParameters: query,
      options: Options(method: 'GET', headers: header),
    );
    final bytes = Uint8List.fromList(res.data ?? const <int>[]);
    if (Store.logEnabled) {
      DebugLog.add('HTTP', 'GET ${res.statusCode} ${bytes.length}B  $url');
    }
    return bytes;
  }

  static Future<dynamic> getJson(
    String url, {
    Map<String, String>? header,
    Map<String, dynamic>? query,
    String? method,
    Object? data,
  }) async {
    final text = await getText(url, header: header, query: query, method: method, data: data);
    final t = text.trim();
    if (t.isEmpty) return null;
    return jsonDecode(t);
  }

  /// 站点常见编码：UTF-8 / GBK / GB2312 / GB18030 / BIG5。
  ///
  /// ## 为什么这里不做真正的 GBK/BIG5 解码
  ///
  /// PeekPili 用 `charset_converter`（Android 走 `CharsetDecoder`、iOS 走
  /// `CFStringConvertEncodingToNSStringEncoding`），桌面端没有对应实现。
  /// 而本工程**所有 HTTP 流量都指向本机 Node 源服务**（`127.0.0.1:9988`），
  /// 它固定返回 UTF-8 JSON，不会出现 GBK 网页。所以：
  ///   * UTF-8（含无 charset）→ `utf8.decode(allowMalformed: true)`
  ///   * 其他声明 → 同样走 UTF-8 + `allowMalformed`，乱码但不抛异常
  ///
  /// 这样比引入一个只在 Android/iOS 可用的原生插件更稳，也不影响任何
  /// 实际调用路径。若将来要直连源站的 GBK 页面，再加纯 Dart 解码器即可。
  static Future<String> decode(Uint8List bytes, String? contentType) async {
    return utf8.decode(bytes, allowMalformed: true);
  }
}
