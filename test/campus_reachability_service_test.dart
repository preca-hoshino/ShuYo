import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuyo/core/forum_url_resolver.dart';
import 'package:shuyo/data/demo/demo_session.dart';
import 'package:shuyo/data/services/campus_reachability_service.dart';
import 'package:shuyo/features/auth/native_login_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 用可控的探测结果构造服务，避免测试触网。
CampusReachabilityService _service({
  required bool reachable,
  Object? error,
  void Function(Uri uri)? onProbe,
}) {
  return CampusReachabilityService(
    probe: (uri) async {
      onProbe?.call(uri);
      if (reachable) return true;
      throw error ?? const SocketException('unreachable');
    },
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => ForumUrlResolver.configure(useWebVpn: false));

  group('CampusReachabilityService', () {
    test('probes the direct forum entry, not the WebVPN host', () async {
      Uri? probed;
      await _service(reachable: true, onProbe: (uri) => probed = uri)
          .checkDirectForum();

      expect(probed?.host, 'bbs.shu.edu.cn');
      expect(probed?.path, '/auth/oauth2_basic');
    });

    test('reports unreachable when the connection cannot be established',
        () async {
      final result = await _service(reachable: false).checkDirectForum();

      expect(result.isUnreachable, isTrue);
      expect(result.status, CampusReachabilityStatus.unreachable);
    });

    test('reports reachable regardless of the HTTP status code', () async {
      // 教务入口在校外仍返回 301/403，判定只看连接层，否则会误判成不可达。
      final result = await _service(reachable: true).checkDirectForum();

      expect(result.isUnreachable, isFalse);
      expect(result.status, CampusReachabilityStatus.reachable);
    });

    test('treats an unexpected probe failure as unknown, not unreachable',
        () async {
      final result = await _service(
        reachable: false,
        error: const FormatException('unexpected'),
      ).checkDirectForum();

      // 无法归因的失败不能让界面提示用户切换网络。
      expect(result.status, CampusReachabilityStatus.unknown);
      expect(result.isUnreachable, isFalse);
    });

    test('probes exactly once so a failure never blocks the user twice',
        () async {
      var attempts = 0;
      final service = CampusReachabilityService(
        probe: (uri) async {
          attempts++;
          throw const SocketException('unreachable');
        },
      );

      final result = await service.checkDirectForum();

      // 校外访问论坛会立即失败，自动复测只会让用户多等一个超时周期；
      // 探测允许误报，重试交给调用方的「仍然尝试」。
      expect(attempts, 1);
      expect(result.isUnreachable, isTrue);
    });
  });

  group('forum login preflight', () {
    testWidgets('blocks the WeCom entry off campus and offers WebVPN guidance',
        (tester) async {
      var probes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: NativeLoginPage.forum(
            reachabilityService: _service(
              reachable: false,
              onProbe: (_) => probes++,
            ),
          ),
        ),
      );

      await tester.tap(find.text('使用企业微信登录'));
      await tester.pumpAndSettle();

      expect(probes, greaterThan(0));
      expect(find.text('无法连接乐乎论坛'), findsOneWidget);
      expect(find.textContaining('开启 WebVPN'), findsOneWidget);
      // 未获得用户确认前不得进入扫码页。
      expect(find.text('使用企业微信扫一扫'), findsNothing);
    });

    testWidgets('skips the preflight when WebVPN is already enabled',
        (tester) async {
      ForumUrlResolver.configure(useWebVpn: true);
      var probes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: NativeLoginPage.forum(
            reachabilityService: _service(
              reachable: false,
              onProbe: (_) => probes++,
            ),
          ),
        ),
      );

      await tester.tap(find.text('使用企业微信登录'));
      await tester.pumpAndSettle();

      // WebVPN 模式下论坛走代理，不该再用直连可达性拦截。
      expect(probes, 0);
      expect(find.text('无法连接乐乎论坛'), findsNothing);
    });

    testWidgets('does not gate the campus account login', (tester) async {
      var probes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: NativeLoginPage(
            reachabilityService: _service(
              reachable: false,
              onProbe: (_) => probes++,
            ),
          ),
        ),
      );

      await tester.tap(find.text('使用企业微信登录'));
      await tester.pumpAndSettle();

      // 教务系统在校外仍可访问，不应出现校园网提示。
      expect(probes, 0);
      expect(find.text('无法连接乐乎论坛'), findsNothing);
    });

    testWidgets('lets the user continue after an unreachable probe',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: NativeLoginPage.forum(
            reachabilityService: _service(reachable: false),
          ),
        ),
      );

      await tester.tap(find.text('使用企业微信登录'));
      await tester.pumpAndSettle();
      expect(find.text('无法连接乐乎论坛'), findsOneWidget);

      await tester.tap(find.text('仍然尝试'));
      await tester.pumpAndSettle();

      // 网络探测允许误报，用户确认后必须放行。
      expect(find.text('无法连接乐乎论坛'), findsNothing);
    });
  });

  group('credential preflight', () {
    Future<void> enterCredentials(WidgetTester tester) async {
      await tester.enterText(find.byType(TextFormField).first, 'student');
      await tester.enterText(find.byType(TextFormField).last, 'secret');
      await tester.tap(find.widgetWithText(FilledButton, '继续'));
      await tester.pumpAndSettle();
    }

    testWidgets('blocks the credential login off campus too', (tester) async {
      var probes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: NativeLoginPage.forum(
            reachabilityService: _service(
              reachable: false,
              onProbe: (_) => probes++,
            ),
          ),
        ),
      );

      await enterCredentials(tester);

      // 同一页面上两条登录路径必须给出一致的结论。
      expect(probes, greaterThan(0));
      expect(find.text('无法连接乐乎论坛'), findsOneWidget);
    });

    testWidgets('retries credentials without probing twice on continue',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: NativeLoginPage.forum(
            reachabilityService: _service(reachable: false),
          ),
        ),
      );

      await enterCredentials(tester);
      await tester.tap(find.text('仍然尝试'));
      await tester.pumpAndSettle();

      expect(find.text('无法连接乐乎论坛'), findsNothing);
    });

    testWidgets('does not preflight the offline demo account', (tester) async {
      var probes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: NativeLoginPage.forum(
            reachabilityService: _service(
              reachable: false,
              onProbe: (_) => probes++,
            ),
          ),
        ),
      );

      await tester.enterText(
        find.byType(TextFormField).first,
        DemoSession.username,
      );
      await tester.enterText(
        find.byType(TextFormField).last,
        DemoSession.password,
      );
      await tester.tap(find.widgetWithText(FilledButton, '继续'));
      await tester.pumpAndSettle();

      // 演示模式完全离线，校外评审不能在进入前被预检拦住。
      expect(probes, 0);
      expect(find.text('无法连接乐乎论坛'), findsNothing);
    });
  });
}
