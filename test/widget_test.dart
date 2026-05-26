import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prayu_app/widgets/network_error_view.dart';

void main() {
  testWidgets('NetworkErrorView calls retry callback', (tester) async {
    var retryCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NetworkErrorView(
            onRetry: () {
              retryCount++;
            },
          ),
        ),
      ),
    );

    expect(find.text('네트워크 연결에 실패했습니다.'), findsOneWidget);
    expect(find.text('다시시도'), findsOneWidget);

    await tester.tap(find.text('다시시도'));
    await tester.pump();

    expect(retryCount, 1);
  });
}
