import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/logger_service.dart';
import '../utils/app_theme.dart';

class LogViewerPage extends StatefulWidget {
  const LogViewerPage({super.key});

  @override
  State<LogViewerPage> createState() => _LogViewerPageState();
}

class _LogViewerPageState extends State<LogViewerPage> {
  final _logger = AppLogger();
  final _scrollController = ScrollController();
  LogLevel _filter = LogLevel.debug;
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    _logger.addListener(_onNewLog);
  }

  @override
  void dispose() {
    _logger.removeListener(_onNewLog);
    _scrollController.dispose();
    super.dispose();
  }

  void _onNewLog(LogEntry entry) {
    if (mounted) setState(() {});
    if (_autoScroll) _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  List<LogEntry> get _filteredEntries {
    return _logger.entries.where((e) => e.level.index >= _filter.index).toList();
  }

  Color _levelColor(LogLevel level) {
    switch (level) {
      case LogLevel.debug: return Colors.grey;
      case LogLevel.info: return AppTheme.accentColor;
      case LogLevel.warning: return AppTheme.warningColor;
      case LogLevel.error: return AppTheme.errorColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = _filteredEntries;
    return Scaffold(
      appBar: AppBar(
        title: const Text('应用日志'),
        actions: [
          PopupMenuButton<LogLevel>(
            icon: const Icon(Icons.filter_list),
            onSelected: (level) => setState(() => _filter = level),
            itemBuilder: (_) => LogLevel.values.map((l) => PopupMenuItem(
              value: l,
              child: Text(l.name.toUpperCase()),
            )).toList(),
          ),
          IconButton(
            icon: Icon(_autoScroll ? Icons.vertical_align_bottom : Icons.vertical_align_center),
            onPressed: () => setState(() => _autoScroll = !_autoScroll),
            tooltip: _autoScroll ? '自动滚动:开' : '自动滚动:关',
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () async {
              final currentContext = context;
              final text = await _logger.getLogsAsString(maxLines: 1000);
              await Clipboard.setData(ClipboardData(text: text));
              if (!currentContext.mounted) return;
              ScaffoldMessenger.of(currentContext).showSnackBar(
                const SnackBar(content: Text('日志已复制到剪贴板')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              _logger.clear();
              setState(() {});
            },
          ),
        ],
      ),
      body: entries.isEmpty
          ? const Center(
              child: Text('暂无日志', style: TextStyle(color: AppTheme.textSecondary)),
            )
          : ListView.builder(
              controller: _scrollController,
              itemCount: entries.length,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemBuilder: (_, i) {
                final entry = entries[i];
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: _levelColor(entry.level), width: 3),
                    ),
                  ),
                  child: SelectableText(
                    entry.format(),
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: _levelColor(entry.level),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
