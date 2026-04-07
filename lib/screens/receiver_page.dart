import 'package:flutter/material.dart';


import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';


import '../models/signaling_data.dart';
import '../models/transfer_session.dart';
import '../services/app_state_provider.dart';
import '../services/webrtc_service.dart' as webrtc;
import '../utils/app_theme.dart';
import '../widgets/transfer_progress_widget.dart';

class ReceiverPage extends StatefulWidget {
  final bool useNfc;
  const ReceiverPage({super.key, this.useNfc = false});

  @override
  State<ReceiverPage> createState() => _ReceiverPageState();
}

class _ReceiverPageState extends State<ReceiverPage> {
  int _currentStep = 0;
  String _inputOffer = '';
  SignalingData? _offer;
  final TextEditingController _offerController = TextEditingController();
  MobileScannerController? _scannerController;


  @override
  void dispose() {
    _offerController.dispose();
    _scannerController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('接收'),
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
                const Text('输入信令', style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _offerController,
              maxLines: 3,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: '粘贴发送方的信令...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.all(10),
                isDense: true,
              ),
              onChanged: (value) => setState(() => _inputOffer = value),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _inputOffer.isNotEmpty ? () => _handleStart(provider) : null,
                child: const Text('开始'),
              ),
            ),
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
            const Text('接收完成', style: TextStyle(color: AppTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.bold)),
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

  void _handleStart(AppStateProvider provider) {
    if (_inputOffer.isEmpty) {
      _showSnackBar('请先输入信令信息');
      return;
    }
    try {
      _offer = SignalingData.fromBase64(_inputOffer.trim());
      setState(() => _currentStep = 1);
      provider.receiveOffer(_offer!);
    } catch (e) {
      _showSnackBar('无效的信令信息: ${e.toString()}');
    }
  }







  void _handleCancel(AppStateProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('取消接收'),
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



  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
  }
}
