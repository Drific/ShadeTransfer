import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/signaling_data.dart';
import '../models/transfer_session.dart';
import '../services/app_state_provider.dart';
import '../services/webrtc_service.dart' as webrtc;
import '../utils/app_theme.dart';
import '../widgets/transfer_progress_widget.dart';

class SenderPage extends StatefulWidget {
  final bool useNfc;
  const SenderPage({super.key, this.useNfc = false});

  @override
  State<SenderPage> createState() => _SenderPageState();
}

class _SenderPageState extends State<SenderPage> {
  int _currentStep = 0;
  SignalingData? _offer;
  bool _showQr = false;

  // QR code max capacity is about 2953 bytes at error correction L
  // With base64 encoding and error correction M, practical limit is ~2000 chars
  static const int _qrMaxChars = 2000;

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('发送'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            context.read<AppStateProvider>().reset();
            Navigator.pop(context);
          },
        ),
      ),
      body: Container(
        decoration: AppTheme.gradientDecoration,
        child: Consumer<AppStateProvider>(
          builder: (context, provider, child) {
            return _buildContent(provider);
          },
        ),
      ),
    );
  }

  Widget _buildContent(AppStateProvider provider) {
    if (provider.connectionState == webrtc.ConnectionState.connected &&
        provider.currentSession != null &&
        provider.currentSession!.status == TransferStatus.transferring) {
      return TransferProgressWidget(
        session: provider.currentSession!,
        onPause: () => provider.pauseTransfer(),
        onResume: () => provider.resumeTransfer(),
        onCancel: () => _handleCancel(provider),
      );
    }

    if (provider.currentSession?.status == TransferStatus.completed) {
      return _buildCompletedView(provider);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStep1(provider),
          if (_currentStep >= 1) ...[
            const SizedBox(height: 16),
            _buildStep2(provider),
          ],
        ],
      ),
    );
  }

  Widget _buildStep1(AppStateProvider provider) {
    return Card(
      color: AppTheme.cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _currentStep >= 0 ? AppTheme.primaryColor : AppTheme.surfaceColor,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text('1', style: TextStyle(
                      color: _currentStep > 0 ? Colors.white : AppTheme.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    )),
                  ),
                ),
                const SizedBox(width: 10),
                const Text('选择文件', style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            if (provider.selectedFiles.isNotEmpty) ...[
              ...provider.selectedFiles.map((f) => _buildFileItem(f)),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickFiles(provider),
                    icon: const Icon(Icons.attach_file, size: 18),
                    label: const Text('添加文件', style: TextStyle(fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickFolder(provider),
                    icon: const Icon(Icons.folder_outlined, size: 18),
                    label: const Text('添加文件夹', style: TextStyle(fontSize: 13)),
                  ),
                ),
              ],
            ),
            if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.textSecondary.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DragTarget<String>(
                  builder: (context, candidateData, rejectedData) {
                    return SizedBox(
                      height: 60,
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.file_upload_outlined,
                              color: candidateData.isNotEmpty ? AppTheme.primaryColor : AppTheme.textSecondary,
                              size: 24,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '拖拽文件或文件夹到此处',
                              style: TextStyle(
                                color: candidateData.isNotEmpty ? AppTheme.primaryColor : AppTheme.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  onAcceptWithDetails: (details) {
                    final path = details.data;
                    final file = File(path);
                    if (file.existsSync()) {
                      provider.addFile(path);
                    } else if (Directory(path).existsSync()) {
                      provider.addFolder(path);
                    }
                  },
                ),
              ),
            ],
            if (provider.selectedFiles.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() => _currentStep = 1);
                    _generateOffer(provider);
                  },
                  child: const Text('生成信令'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFileItem(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final isDir = Directory(path).existsSync();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(isDir ? Icons.folder : Icons.insert_drive_file, size: 16, color: AppTheme.accentColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: () => context.read<AppStateProvider>().removeFile(path),
            child: const Icon(Icons.close, size: 16, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2(AppStateProvider provider) {
    final signalingData = _offer?.toBase64() ?? '';
    final bool canShowQr = signalingData.length <= _qrMaxChars;

    return Card(
      color: AppTheme.cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _currentStep > 1 ? AppTheme.primaryColor : AppTheme.surfaceColor,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text('2', style: TextStyle(
                      color: _currentStep > 1 ? Colors.white : AppTheme.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    )),
                  ),
                ),
                const SizedBox(width: 10),
                const Text('信令信息', style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            if (signalingData.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        signalingData,
                        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 11, fontFamily: 'monospace'),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      children: [
                        IconButton(
                          onPressed: () => _copyToClipboard(signalingData),
                          icon: const Icon(Icons.copy, size: 18, color: AppTheme.accentColor),
                          tooltip: '复制',
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (canShowQr) ...[
                GestureDetector(
                  onTap: () => setState(() => _showQr = !_showQr),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(_showQr ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        color: AppTheme.accentColor, size: 18,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _showQr ? '收起二维码' : '以二维码展示',
                        style: const TextStyle(color: AppTheme.accentColor, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (_showQr) ...[
                  const SizedBox(height: 12),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: QrImageView(
                        data: signalingData,
                        version: QrVersions.auto,
                        size: 120,
                        backgroundColor: Colors.white,
                        errorStateBuilder: (context, error) {
                          return Container(
                            width: 120,
                            height: 120,
                            color: Colors.white,
                            child: Center(
                              child: Text(
                                '数据过大\n无法生成',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.red[700], fontSize: 11),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.warningColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.warningColor.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber, color: AppTheme.warningColor, size: 16),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '信令数据过大，无法生成二维码。请使用文本方式复制并分享给接收方。',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const Text('请将此信令发送给接收方', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      provider.connectionState == webrtc.ConnectionState.connected
                          ? Icons.check_circle
                          : Icons.hourglass_empty,
                      color: provider.connectionState == webrtc.ConnectionState.connected
                          ? AppTheme.successColor
                          : AppTheme.accentColor,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        provider.connectionState == webrtc.ConnectionState.connected
                            ? '连接已建立，开始传输'
                            : '等待接收方连接...',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else
              const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }



  Widget _buildCompletedView(AppStateProvider provider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.successColor.withValues(alpha: 0.2),
              ),
              child: const Icon(Icons.check_circle_outline, size: 50, color: AppTheme.successColor),
            ),
            const SizedBox(height: 20),
            const Text('传输完成', style: TextStyle(color: AppTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                provider.reset();
                Navigator.pop(context);
              },
              child: const Text('返回'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFiles(AppStateProvider provider) async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true, withData: false);
    if (result != null) {
      for (final file in result.files) {
        if (file.path != null) {
          provider.addFile(file.path!);
        }
      }
    }
  }

  Future<void> _pickFolder(AppStateProvider provider) async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      provider.addFolder(result);
    }
  }

  Future<void> _generateOffer(AppStateProvider provider) async {
    setState(() => _currentStep = 0);
    final offer = await provider.generateOffer();
    setState(() {
      _offer = offer;
      _currentStep = 1;
    });
  }



  void _handleCancel(AppStateProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('取消传输'),
        content: const Text('确定要取消吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('继续')),
          ElevatedButton(
            onPressed: () { Navigator.pop(context); provider.cancelTransfer(); },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _showSnackBar('已复制到剪贴板');
  }



  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
  }
}
