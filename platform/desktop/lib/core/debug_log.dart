import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';

class LogEntry {
  final DateTime time;
  final String tag;
  final String message;
  LogEntry(this.tag, this.message) : time = DateTime.now();

  String get stamp {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }
}

/// 调试日志环形缓冲（原版设置第 11 项「调试日志」）。
///
/// 除了内存环形缓冲，还支持**落盘**（[enableFileSink]）。落盘的意义：
/// 用户报「搜不到」这类问题时，光看界面无法区分「源没数据」和
/// 「客户端把数据丢了」。把每一步写进文件后，让用户复现一次即可定位 ——
/// 这在非交互环境（无法模拟点击）里是唯一可靠的取证手段。
class DebugLog {
  static const maxEntries = 500;
  static final List<LogEntry> _entries = <LogEntry>[];
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// 落盘目标（null = 不落盘）。
  static File? _sink;
  static IOSink? _sinkStream;

  /// 把日志同时写到 [file]。传 null 关闭。
  static Future<void> enableFileSink(File? file) async {
    await _sinkStream?.flush();
    await _sinkStream?.close();
    _sinkStream = null;
    _sink = file;
    if (file == null) return;
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString('', mode: FileMode.write); // 每次启动截断
      _sinkStream = file.openWrite(mode: FileMode.append);
    } catch (_) {
      _sink = null;
      _sinkStream = null;
    }
  }

  static String? get sinkPath => _sink?.path;

  static List<LogEntry> get entries =>
      List<LogEntry>.unmodifiable(_entries.reversed.toList());

  static void add(String tag, String message) {
    final e = LogEntry(tag, message);
    _entries.add(e);
    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }
    try {
      _sinkStream?.writeln('[${e.stamp}] [$tag] $message');
    } catch (_) {}
    revision.value++;
  }

  static void clear() {
    _entries.clear();
    revision.value++;
  }

  static String dump() {
    final buf = StringBuffer();
    for (final e in _entries) {
      buf.writeln('[${e.stamp}] [${e.tag}] ${e.message}');
    }
    return buf.toString();
  }
}

/// 供外部只读访问（避免直接暴露可变列表）
UnmodifiableListView<LogEntry> unmodifiableLogs(List<LogEntry> src) =>
    UnmodifiableListView<LogEntry>(src);
