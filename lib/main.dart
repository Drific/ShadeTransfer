// lib/main.dart

import 'package:flutter/material.dart';
import 'constants/charset.dart';
import 'services/encoding_service.dart';

void main() {
  // Quick self-test
  _selfTest();
  runApp(const ShadeTransferApp());
}

void _selfTest() {
  // Round-trip test: random bytes → encode → decode
  for (int i = 0; i < 100; i++) {
    final original = EncodingService.randomString(8);
    final decoded = EncodingService.decodeBigInt(original);
    final reencoded = EncodingService.encodeBigInt(decoded);
    assert(original == reencoded, 'Round-trip failed at $i');
  }

  // ICE candidate test
  final ice = EncodingService.encodeIceCandidate('192.168.1.100', 8080);
  final result = EncodingService.decodeIceCandidate(ice);
  assert(result.ip == '192.168.1.100');
  assert(result.port == 8080);

  // Checksum test
  final data = 'hello world';
  final cs = EncodingService.checksum(data);
  assert(EncodingService.verifyChecksum(data, cs));
  assert(!EncodingService.verifyChecksum('hello worle', cs));

  // Charset validation
  assert(!ice.contains('o'));
  assert(!ice.contains('O'));
  assert(!ice.contains('0'));
  assert(!ice.contains('1'));
  assert(!ice.contains('I'));
  assert(!ice.contains('l'));

  print('All tests passed.');
  print('Charset (${Charset.base} chars): ${Charset.all}');
  print('ICE example: $ice → ${result.ip}:${result.port}');
}

class ShadeTransferApp extends StatelessWidget {
  const ShadeTransferApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ShadeTransfer',
      debugShowCheckedModeBanner: false,
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'ShadeTransfer',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'v0.0.0.1',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
            const SizedBox(height: 48),
            // Placeholder — real UI comes with shadcn_ui integration
            const Text('Ready.'),
          ],
        ),
      ),
    );
  }
}
