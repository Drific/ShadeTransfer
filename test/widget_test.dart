import 'package:flutter_test/flutter_test.dart';

import 'package:shade_transfer/main.dart';

void main() {
  testWidgets('App starts and shows home page', (WidgetTester tester) async {
    await tester.pumpWidget(const ShadeTransferApp());

    expect(find.text('ShadeTransfer'), findsOneWidget);
    expect(find.text('发送文件'), findsOneWidget);
    expect(find.text('接收文件'), findsOneWidget);
  });

  testWidgets('Can navigate to sender page', (WidgetTester tester) async {
    await tester.pumpWidget(const ShadeTransferApp());

    await tester.tap(find.text('发送文件'));
    await tester.pumpAndSettle();

    expect(find.text('选择文件'), findsOneWidget);
  });

  testWidgets('Can navigate to receiver page', (WidgetTester tester) async {
    await tester.pumpWidget(const ShadeTransferApp());

    await tester.tap(find.text('接收文件'));
    await tester.pumpAndSettle();

    expect(find.text('扫描二维码'), findsOneWidget);
  });
}
