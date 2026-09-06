import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shuyo/core/academic_url_resolver.dart';
import 'package:shuyo/core/forum_url_resolver.dart';
import 'package:shuyo/data/services/academic_native_auth_service.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  test('academic password encryption produces randomized 1024-bit RSA data',
      () {
    final first = AcademicPasswordEncryptor.encrypt('test-password');
    final second = AcademicPasswordEncryptor.encrypt('test-password');

    expect(base64Decode(first), hasLength(128));
    expect(base64Decode(second), hasLength(128));
    expect(second, isNot(first));
  });

  test('sendError explains the rate limit and alternate method', () {
    expect(
      AcademicNativeAuthService.messageForCode('sendError'),
      '验证码发送过于频繁，请切换验证方式或稍后再试',
    );
  });

  test('academic reauthentication preserves only forum-owned cookies', () {
    final forumSession = WebViewCookie(
      name: '_forum_session',
      value: 'forum-session',
      domain: ForumUrlResolver.webVpnHost,
    );

    expect(
      AcademicNativeAuthService
          .shouldPreserveCookieDuringAcademicReauthentication(
        sourceUri: Uri.parse(ForumUrlResolver.webVpnBaseUrl),
        cookie: forumSession,
      ),
      isTrue,
    );
    expect(
      AcademicNativeAuthService
          .shouldPreserveCookieDuringAcademicReauthentication(
        sourceUri: Uri.parse(ForumUrlResolver.webVpnBaseUrl),
        cookie: WebViewCookie(
          name: 'webvpn-token',
          value: 'stale-token',
          domain: ForumUrlResolver.webVpnHost,
        ),
      ),
      isFalse,
    );
    expect(
      AcademicNativeAuthService
          .shouldPreserveCookieDuringAcademicReauthentication(
        sourceUri: Uri.parse(AcademicUrlResolver.webVpnBaseUrl),
        cookie: WebViewCookie(
          name: 'JSESSIONID',
          value: 'stale-session',
          domain: AcademicUrlResolver.webVpnHost,
        ),
      ),
      isFalse,
    );
  });
}
