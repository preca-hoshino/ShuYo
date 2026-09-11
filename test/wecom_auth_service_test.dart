import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shuyo/core/wecom_constants.dart';
import 'package:shuyo/data/services/wecom_auth_service.dart';

void main() {
  group('WeComAuthService', () {
    test('encodeOAuthParams produces base64url without padding', () {
      final encoded = WeComAuthService.encodeOAuthParams({
        'responseType': 'code',
        'clientId': 'abc',
      });
      // base64url (no + / = chars)
      expect(encoded, isNot(contains('+')));
      expect(encoded, isNot(contains('/')));
      expect(encoded, isNot(contains('=')));
      // Can be decoded back (normalize restores the stripped padding)
      final decoded = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(encoded))),
      );
      expect(decoded['responseType'], 'code');
      expect(decoded['clientId'], 'abc');
    });

    test('encodeOAuthParams handles Chinese text (ensureAscii=false)', () {
      final encoded = WeComAuthService.encodeOAuthParams({
        'clientName': '本科生教务系统',
      });
      final decoded = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(encoded))),
      );
      expect(decoded['clientName'], '本科生教务系统');
    });

    test('parseStatus maps QRCODE_SCAN_SUCC with auth_code to success',
        () async {
      // WeComScanResult 的静态构造器行为：
      expect(
        const WeComScanResult.succeeded('abc123').isSuccess,
        true,
      );
      expect(const WeComScanResult.succeeded('abc123').authCode, 'abc123');
    });

    test('weComRedeemState always encodes the academic client', () {
      // state 固定编码 jwxt 参数：企微自建应用只绑定教务系统，用论坛参数
      // 会被 /oauth/wecom/qrcode 判为 badRequestParams。目标系统的差异在
      // authorizeTarget 阶段处理。
      final decoded = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(
          WeComAuthService.weComRedeemState,
        ))),
      );
      expect(decoded['clientId'], 'Km5t225E8KECKQ6ZDm5K2P6aS2459Cua');
      expect(decoded['scope'], 'jw');
      expect(WeComAuthService.weComRedeemState, isNot(contains('=')));
      expect(WeComAuthService.weComRedeemState, isNot(contains('+')));
      expect(WeComAuthService.weComRedeemState, isNot(contains('/')));
    });

    test('WeComSessionResult carries the SSO session cookies', () {
      final result = WeComSessionResult(
        sessionCookies: [Cookie('SHU_OAUTH2', 'session')],
        cookieSourceUri:
            Uri.parse('https://newsso.shu.edu.cn/oauth/wecom/qrcode'),
      );
      expect(result.sessionCookies.single.name, 'SHU_OAUTH2');
      expect(result.cookieSourceUri.host, 'newsso.shu.edu.cn');
    });
  });

  group('WeComOAuthTarget', () {
    test('academic target encodes the jwxt client', () {
      final decoded = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(
          WeComAuthService.encodeOAuthParams(
              WeComOAuthTarget.academic.toParams()),
        ))),
      );
      expect(decoded['clientId'], 'Km5t225E8KECKQ6ZDm5K2P6aS2459Cua');
      expect(decoded['clientName'], '本科生教务系统');
      expect(decoded['scope'], 'jw');
      expect(decoded['redirectUri'], 'https://jwxt.shu.edu.cn/sso/shulogin');
      expect(decoded['responseType'], 'code');
      expect(decoded['state'], '');
    });

    test('forum target encodes the bbs client', () {
      final decoded = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(
          WeComAuthService.encodeOAuthParams(WeComOAuthTarget.forum.toParams()),
        ))),
      );
      expect(decoded['clientId'], 'vp8G2H42GGE86LP822LHF6Hs7f46483H');
      expect(decoded['scope'], '');
      expect(
        decoded['redirectUri'],
        'https://bbs.shu.edu.cn/auth/oauth2_basic/callback',
      );
    });

    test('state strategies match the target system config', () {
      // jwxt 自生成随机 state；bbs 需先访问自身入口预取 state。
      expect(WeComOAuthTarget.academic.generateState, isTrue);
      expect(WeComOAuthTarget.academic.stateBootstrapUrl, isNull);
      expect(WeComOAuthTarget.forum.generateState, isFalse);
      expect(
        WeComOAuthTarget.forum.stateBootstrapUrl,
        'https://bbs.shu.edu.cn/auth/oauth2_basic',
      );
    });
  });
}
