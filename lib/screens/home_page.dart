import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state_provider.dart';
import '../utils/app_theme.dart';
import 'sender_page.dart';
import 'receiver_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: AppTheme.gradientDecoration,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildLogo(),
                  const SizedBox(height: 32),
                  _buildTitle(),
                  const SizedBox(height: 48),
                  _buildActionButtons(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.primaryColor, AppTheme.accentColor],
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withValues(alpha: 0.4),
            blurRadius: 30,
            spreadRadius: 5,
          ),
        ],
      ),
      child: const Icon(
        Icons.cloud_sync_rounded,
        size: 50,
        color: Colors.white,
      ),
    );
  }

  Widget _buildTitle() {
    return const Text(
      'ShadeTransfer',
      style: TextStyle(
        color: AppTheme.textPrimary,
        fontSize: 32,
        fontWeight: FontWeight.bold,
        letterSpacing: 4,
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Consumer<AppStateProvider>(
      builder: (context, provider, _) {
        return Column(
          children: [
            SizedBox(
              width: 280,
              child: ElevatedButton.icon(
                onPressed: () {
                  provider.setSenderMode();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SenderPage()),
                  );
                },
                icon: const Icon(Icons.upload_file, size: 22),
                label: const Text('发送文件'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: 280,
              child: OutlinedButton.icon(
                onPressed: () {
                  provider.setReceiverMode();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ReceiverPage()),
                  );
                },
                icon: const Icon(Icons.download, size: 22),
                label: const Text('接收文件'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
