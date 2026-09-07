import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuyo/data/models/client_backend.dart';
import 'package:shuyo/shared/widgets/app_header.dart';
import 'package:shuyo/shared/widgets/webvpn_status_indicator.dart';

void main() {
  testWidgets('places the WebVPN dot to the left of settings', (tester) async {
    final checkedAt = DateTime.now().toUtc();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppHeader(
            title: '首页',
            showSettings: true,
            beforeSettings: WebVpnStatusIndicator(
              status: _status(WebVpnServiceState.available, checkedAt),
            ),
            onSettings: () {},
            onNotification: () {},
          ),
        ),
      ),
    );

    final indicator = find.byKey(const ValueKey('webvpn-status-indicator'));
    expect(indicator, findsOneWidget);
    expect(
      tester.getCenter(indicator).dx,
      lessThan(tester.getCenter(find.byTooltip('设置')).dx),
    );
    final dot = tester.widget<Container>(
      find.byKey(const ValueKey('webvpn-status-dot')),
    );
    final decoration = dot.decoration! as BoxDecoration;
    expect(decoration.color, const Color(0xFF3478F6));
  });

  testWidgets('opens a concise unavailable status dialog', (tester) async {
    final checkedAt = DateTime.now().toUtc();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WebVpnStatusIndicator(
            status: _status(WebVpnServiceState.unavailable, checkedAt),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('webvpn-status-indicator')),
    );
    await tester.pumpAndSettle();

    expect(find.text('WebVPN服务状态'), findsOneWidget);
    expect(find.textContaining('WebVPN服务暂不可用'), findsOneWidget);
    expect(find.textContaining('服务器连续多次'), findsNothing);
  });
}

WebVpnServiceStatus _status(WebVpnServiceState state, DateTime checkedAt) {
  return WebVpnServiceStatus(
    state: state,
    checkedAt: checkedAt,
    statusSince: checkedAt,
    lastSuccessAt: state == WebVpnServiceState.available ? checkedAt : null,
    latencyMs: 100,
    reason: 'test',
  );
}
