import 'dart:async';

import 'package:flutter/material.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';

import '../models/file_metadata.dart';
import '../models/transfer_session.dart';
import '../utils/app_theme.dart';

class TransferProgressWidget extends StatefulWidget {
  final TransferSession session;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onCancel;

  const TransferProgressWidget({
    super.key,
    required this.session,
    this.onPause,
    this.onResume,
    this.onCancel,
  });

  @override
  State<TransferProgressWidget> createState() => _TransferProgressWidgetState();
}

class _TransferProgressWidgetState extends State<TransferProgressWidget> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final metadata = session.fileMetadata;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(session),
          const SizedBox(height: 16),
          _buildProgressBar(session),
          const SizedBox(height: 12),
          _buildStats(session, metadata),
          const SizedBox(height: 16),
          _buildActionButtons(session),
        ],
      ),
    );
  }

  Widget _buildHeader(TransferSession session) {
    final isSender = session.direction == TransferDirection.send;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(isSender ? Icons.upload : Icons.download, color: AppTheme.accentColor, size: 22),
        const SizedBox(width: 8),
        Text(
          isSender ? '正在发送' : '正在接收',
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const Spacer(),
        Text(
          '${(session.progress * 100).toStringAsFixed(1)}%',
          style: const TextStyle(color: AppTheme.primaryColor, fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildProgressBar(TransferSession session) {
    return Column(
      children: [
        LinearPercentIndicator(
          padding: EdgeInsets.zero,
          lineHeight: 10,
          percent: session.progress.clamp(0.0, 1.0),
          progressColor: AppTheme.primaryColor,
          backgroundColor: AppTheme.surfaceColor,
          barRadius: const Radius.circular(5),
          animation: false,
        ),
        const SizedBox(height: 6),
        LinearPercentIndicator(
          padding: EdgeInsets.zero,
          lineHeight: 6,
          percent: session.chunkProgress.clamp(0.0, 1.0),
          progressColor: AppTheme.accentColor,
          backgroundColor: AppTheme.surfaceColor,
          barRadius: const Radius.circular(3),
          animation: false,
        ),
      ],
    );
  }

  Widget _buildStats(TransferSession session, FileMetadata? metadata) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          if (metadata != null) ...[
            _statRow(Icons.insert_drive_file, metadata.name, metadata.formattedSize),
            const Divider(color: AppTheme.textSecondary, height: 16),
          ],
          _statRow(Icons.speed, '速度', session.formattedSpeed),
          const Divider(color: AppTheme.textSecondary, height: 16),
          _statRow(Icons.data_usage, '已传输', '${_formatBytes(session.transferredBytes)} / ${metadata != null ? metadata.formattedSize : '--'}'),
          const Divider(color: AppTheme.textSecondary, height: 16),
          _statRow(Icons.timer, '预计剩余', session.formattedETA),
        ],
      ),
    );
  }

  Widget _statRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.accentColor, size: 16),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.w500),
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(TransferSession session) {
    final isPaused = session.status == TransferStatus.paused;
    final isTransferring = session.status == TransferStatus.transferring;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isTransferring)
          OutlinedButton.icon(
            onPressed: widget.onPause,
            icon: const Icon(Icons.pause, size: 18),
            label: const Text('暂停'),
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
          )
        else if (isPaused)
          ElevatedButton.icon(
            onPressed: widget.onResume,
            icon: const Icon(Icons.play_arrow, size: 18),
            label: const Text('继续'),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
          ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: widget.onCancel,
          icon: const Icon(Icons.cancel_outlined, size: 18),
          label: const Text('取消'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.errorColor,
            side: const BorderSide(color: AppTheme.errorColor),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
        ),
      ],
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
