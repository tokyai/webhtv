import 'dart:collection';

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
class DebugLog {
  static const maxEntries = 500;
  static final List<LogEntry> _entries = <LogEntry>[];
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static List<LogEntry> get entries =>
      List<LogEntry>.unmodifiable(_entries.reversed.toList());

  static void add(String tag, String message) {
    _entries.add(LogEntry(tag, message));
    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }
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
