import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuyo/core/certificate_policy.dart';
import 'package:shuyo/core/forum_url_resolver.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    ForumUrlResolver.configure(useWebVpn: false);
  });

  test('only Android direct BBS can use the temporary certificate exception',
      () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    ForumUrlResolver.configure(useWebVpn: false);
    expect(CertificatePolicy.allowsHost('bbs.shu.edu.cn'), isTrue);
    expect(CertificatePolicy.allowsHost('oauth.shu.edu.cn'), isFalse);

    ForumUrlResolver.configure(useWebVpn: true);
    expect(CertificatePolicy.allowsHost('bbs.shu.edu.cn'), isFalse);
    expect(
      CertificatePolicy.allowsHost(ForumUrlResolver.webVpnHost),
      isFalse,
    );
  });

  test('iOS never bypasses an invalid BBS certificate', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    ForumUrlResolver.configure(useWebVpn: false);

    expect(CertificatePolicy.allowsHost('bbs.shu.edu.cn'), isFalse);
  });
}
