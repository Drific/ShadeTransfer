import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

enum LogLevel { debug, info, warning, error }

class LogEntry {
  final DateTime time;
  final LogLevel level;
  final String tag;
  final String message;
  final String? stackTrace;

  LogEntry({
    required this.time,
    required this.level,
    required this.tag,
    required this.message,
    this.stackTrace});

  String get levelStr {
    switch (level) {
      case LogLevel.debug: return 'DEBUG';
      case LogLevel.info: return 'INFO';
      case LogLevel.warning: return 'WARN';
      case LogLevel.error: return 'ERROR';
    }
  }

  String format() {
    final ts = '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}.'
        '${time.millisecond.toString().padLeft(3, '0')}';
    final base = '[$ts] [$levelStr] [$tag] $message';
    return stackTrace != null ? '$base\n$stackTrace' : base;
  }
}

class AppLogger {
  static final AppLogger _instance = AppLogger._internal();
  factory AppLogger() => _instance;
  AppLogger._internal();

  final List<LogEntry> _entries = [];
  File? _logFile;
  bool _initialized = false;
  final LogLevel _minLevel = LogLevel.debug;

  final _listeners = <void Function(LogEntry)>[];

  List<LogEntry> get entries => List.unmodifiable(_entries);

  void addListener(void Function(LogEntry) listener) => _listeners.add(listener);
  void removeListener(void Function(LogEntry) listener) => _listeners.remove(listener);

  Future<void> init() async {
    if (_initialized) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final logDir = Directory('${dir.path}/logs');
      if (!await logDir.exists()) await logDir.create(recursive: true);
      final now = DateTime.now();
      final fileName = 'shade_${now.year}${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}'
          '${now.minute.toString().padLeft(2, '0')}.log';
      _logFile = File('${logDir.path}/$fileName');
      _initialized = true;
      info('Logger', 'Logger initialized, file: ${_logFile!.path}');
    } catch (e) {
      debugPrint('Failed to init logger: $e');
    }
  }

  void debug(String tag, String message) => _log(LogLevel.debug, tag, message);
  void info(String tag, String message) => _log(LogLevel.info, tag, message);
  void warning(String tag, String message) => _log(LogLevel.warning, tag, message);
  void error(String tag, String message, [StackTrace? st]) =>
      _log(LogLevel.error, tag, message, st);

  void _log(LogLevel level, String tag, String message, [StackTrace? st]) {
    if (level.index < _minLevel.index) return;
    final entry = LogEntry(
      time: DateTime.now(),
      level: level,
      tag: tag,
      message: message,
      stackTrace: st?.toString(),
    );
    _entries.add(entry);
    if (_entries.length > 5000) _entries.removeRange(0, 1000);
    debugPrint(entry.format());
    for (final l in _listeners) {
      try { l(entry); } catch (_) {}
    }
    _writeToFile(entry);
  }

  Future<void> _writeToFile(LogEntry entry) async {
    try {
      if (_logFile != null) {
        await _logFile!.writeAsString('${entry.format()}\n', mode: FileMode.append, flush: false);
      }
    } catch (_) {}
  }

  Future<String?> getLogFilePath() async => _logFile?.path;

  Future<String> getLogsAsString({int maxLines = 500}) async {
    final start = _entries.length > maxLines ? _entries.length - maxLines : 0;
    return _entries.sublist(start).map((e) => e.format()).join('\n');
  }

  void clear() => _entries.clear();
}
