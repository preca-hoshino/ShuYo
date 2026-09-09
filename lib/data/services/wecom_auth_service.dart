import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../core/client_user_agent.dart';
import '../../core/wecom_constants.dart';
import 'academic_native_auth_service.dart';
import 'http_timeout.dart';

/// 企业微信扫码登录过程中的会话信息。
class WeComQrSession {
  const WeComQrSession({
    required this.key,
    required this.qrImageUrl,
    required this.confirmUrl,
    required this.wxWorkSchemeUrl,
  });

  /// 企微扫码会话标识，用于长轮询与确认页地址。
  final String key;

  /// 二维码图片地址（可直接作为 Image.network 的源）。
  final String qrImageUrl;

  /// 扫码后企微内置浏览器打开的确认页地址。
  final String confirmUrl;

  /// 包装后的 scheme 跳转地址（`wxwork://sso/jump?url=...`），
  /// 在外部浏览器/短信中打开可拉起企业微信。
  final String wxWorkSchemeUrl;
}

/// 长轮询扫码状态。
enum WeComScanStatus {
  /// 尚未扫码。
  waiting,

  /// 已扫码，等待手机确认。
  confirmedPending,

  /// 已确认，取得 auth_code。
  succeeded,

  /// 二维码已过期或已取消。
  expired,
}

/// 扫码长轮询结果。
class WeComScanResult {
  const WeComScanResult._({required this.status, this.authCode});

  const WeComScanResult.waiting() : this._(status: WeComScanStatus.waiting);

  const WeComScanResult.confirmedPending()
      : this._(status: WeComScanStatus.confirmedPending);

  const WeComScanResult.succeeded(String authCode)
      : this._(status: WeComScanStatus.succeeded, authCode: authCode);

  const WeComScanResult.expired() : this._(status: WeComScanStatus.expired);

  final WeComScanStatus status;
  final String? authCode;

  bool get isSuccess => status == WeComScanStatus.succeeded;
}

/// 阶段一的产物：已建立的 SSO 会话。
class WeComSessionResult {
  const WeComSessionResult({
    required this.sessionCookies,
    required this.cookieSourceUri,
  });

  final List<Cookie> sessionCookies;
  final Uri cookieSourceUri;
}

/// 一条带作用域的 Cookie，供写入 WebView 时使用。
class WeComStoredCookie {
  const WeComStoredCookie({
    required this.cookie,
    required this.domain,
    required this.path,
  });

  final Cookie cookie;
  final String domain;
  final String path;
}

/// 企微扫码登录的最终结果。
///
/// [callbackUri] 是**目标业务系统**的授权码回调地址（阶段二 `authorize` 的
/// 302 Location），等价于密码登录流程的 callbackUri；
/// [sessionCookies] 是本次流程收集到的全部 Cookie，必须写入 WebView，
/// 否则加载 [callbackUri] 时 SSO 会认为未登录并重定向回登录页。
class WeComRedeemResult {
  const WeComRedeemResult({
    required this.callbackUri,
    required this.sessionCookies,
  });

  final Uri callbackUri;
  final List<WeComStoredCookie> sessionCookies;
}

/// 企业微信扫码登录错误。
class WeComAuthException implements Exception {
  const WeComAuthException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

/// 企业微信扫码登录服务。
///
/// 采用两阶段设计：
///
/// **阶段一：用企微换 SSO 会话**
/// 1. `GET /wwopen/sso/qrConnect` → HTML 内嵌 `qrImg?key=<key>`，key 为扫码会话标识；
/// 2. 长轮询 `GET /wwopen/sso/l/qrConnect` → JSONP `jsonpCallback({...})`，
///    状态机 `QRCODE_SCAN_NEVER → QRCODE_SCAN_ING → QRCODE_SCAN_SUCC`；
/// 3. `GET /oauth/wecom/qrcode?code=<auth_code>&state=<params>&appid=...`
///    → 302 + `SHU_OAUTH2` 会话 Cookie。
///
/// **阶段二：用 SSO 会话换目标业务系统的授权码**
/// 4. 按目标系统准备 `state`（bbs 预热 / jwxt 随机）；
/// 5. `GET /oauth/authorize?response_type=code&client_id&redirect_uri&scope&state`
///    → 302 到业务系统的 callback 地址（带 `code`）。
///
/// 整个流程共享同一个 Cookie 容器，否则第 5 步会因缺少 `SHU_OAUTH2`
/// 而被判定为未登录。需要 state 预热的系统（如论坛）在 [WeComScanPage]
/// 里改为让 WebView 自行走完整链路。
class WeComAuthService {
  WeComAuthService({HttpClient? httpClient})
      : _client = httpClient ?? HttpClient() {
    _client.connectionTimeout = HttpTimeout.connect;
  }

  final HttpClient _client;
  final AcademicSessionCookieStore _cookies = AcademicSessionCookieStore();
  static final _qrImgKeyPattern = RegExp(r'qrImg\?key=([0-9a-fA-F]+)');
  static final _jsonpPattern = RegExp(r'jsonpCallback\((\{.*?\})\)');

  void dispose() => _client.close(force: true);

  /// 本次流程收集到的全部 Cookie。
  ///
  /// 必须在阶段二结束后取出并写入 WebView，否则回调会因缺少会话而失败
  /// （论坛更会因缺少 `_forum_session` 返回 `csrf_detected`）。
  ///
  /// `SHU_OAUTH2` 会额外镜像到论坛使用的 SSO 域（[WeComConstants.forumSsoHost]），
  /// 因为该 cookie 按 host 隔离，而论坛的 `authorize` 走的是另一个域名。
  List<WeComStoredCookie> get cookieJar {
    final jar = <WeComStoredCookie>[
      for (final entry in _cookies.entries)
        WeComStoredCookie(
          cookie: entry.cookie,
          domain: entry.domain,
          path: entry.path,
        ),
    ];
    final ssoHost = Uri.parse(WeComConstants.ssoBase).host;
    for (final entry in [...jar]) {
      if (entry.cookie.name != WeComConstants.sessionCookieName) continue;
      if (entry.domain != ssoHost) continue;
      jar.add(
        WeComStoredCookie(
          cookie: entry.cookie,
          domain: WeComConstants.forumSsoHost,
          path: entry.path,
        ),
      );
    }
    return jar;
  }

  static void _debug(String message) {
    if (kDebugMode) debugPrint('[SHU_WECOM] $message');
  }

  /// 编码 OAuth 参数为 base64url 无填充字符串（与 `_extractParams` 格式一致）。
  ///
  /// 注意：必须使用 base64url 无 `=` 填充，否则企微/SSO 返回 `badRequestParams`。
  static String encodeOAuthParams(Map<String, String> params) {
    final json = jsonEncode(params);
    return base64Url.encode(utf8.encode(json)).replaceAll('=', '');
  }

  /// 企微扫码换取 SSO 会话时固定使用的 `state`。
  ///
  /// `state` 固定编码教务系统参数——企微自建应用只绑定教务系统，
  /// `/oauth/wecom/qrcode` 用它校验请求合法性；换成论坛参数会返回
  /// `{"message":"badRequestParams"}`。目标系统的差异在阶段二处理。
  static String get weComRedeemState =>
      encodeOAuthParams(WeComOAuthTarget.academic.toParams());

  /// 发起企微扫码会话，返回二维码与唤起链接。
  Future<WeComQrSession> startQrSession() async {
    _debug('startQrSession begin');
    final uri = Uri.parse(WeComConstants.qrConnectBase).replace(
      queryParameters: {
        'appid': WeComConstants.appId,
        'agentid': WeComConstants.agentId,
        'redirect_uri': WeComConstants.redirectUri,
        'state': weComRedeemState,
        'lang': 'zh',
        'version': '1.2.7',
        'login_type': 'jssdk',
      },
    );
    final response = await _get(uri, host: _RequestHost.weCom);
    final body = await utf8.decodeStream(response).timeout(HttpTimeout.normal);
    final match = _qrImgKeyPattern.firstMatch(body);
    if (match == null) {
      _debug('startQrSession no-key bodyLength=${body.length}');
      throw const WeComAuthException(
        'qrcodeKeyNotFound',
        '未能获取企业微信登录二维码，请稍后重试',
      );
    }
    final key = match.group(1)!;
    _debug('startQrSession key=${key.substring(0, 8)}…');
    final confirmUrl = '${WeComConstants.confirmBase}?k=$key&notretry=yes';
    return WeComQrSession(
      key: key,
      qrImageUrl: '${WeComConstants.qrImgBase}?key=$key',
      confirmUrl: confirmUrl,
      wxWorkSchemeUrl:
          '${WeComConstants.schemeJumpBase}${Uri.encodeComponent(confirmUrl)}',
    );
  }

  /// 长轮询等待用户扫码确认，直到成功、过期或达到超时时间。
  ///
  /// [onStatusChanged] 会在状态变化时回调（用于界面展示）。
  Future<WeComScanResult> waitForScan(
    String key, {
    Duration timeout = const Duration(seconds: 180),
    void Function(WeComScanStatus status)? onStatusChanged,
  }) async {
    final deadline = DateTime.now().add(timeout);
    WeComScanStatus lastStatus = WeComScanStatus.waiting;
    while (DateTime.now().isBefore(deadline)) {
      final result = await _pollOnce(key);
      lastStatus = result.status;
      onStatusChanged?.call(lastStatus);
      if (result.status == WeComScanStatus.succeeded) {
        return result;
      }
      if (result.status == WeComScanStatus.expired) {
        return result;
      }
      if (result.status == WeComScanStatus.confirmedPending) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 1000));
      }
    }
    return WeComScanResult.expired();
  }

  /// 阶段一：把企微 `auth_code` 换成 SSO 会话。
  ///
  /// [state] 必须为 [weComRedeemState]（教务参数），且必须携带 `appid`。
  Future<WeComSessionResult> redeem(String authCode, String state) async {
    _debug('redeem begin code=${authCode.substring(0, 6)}…');
    final uri =
        Uri.parse('${WeComConstants.ssoBase}/oauth/wecom/qrcode').replace(
      queryParameters: {
        'code': authCode,
        'state': state,
        'appid': WeComConstants.appId,
      },
    );
    final response = await _get(uri, host: _RequestHost.sso);
    final statusCode = response.statusCode;
    final cookies = _parseCookies(response);
    final location = response.headers.value(HttpHeaders.locationHeader) ?? '';
    // 失败判定：Location 含 message=wecomAuthFailed，或响应体含
    // badRequestParams（缺 appid / state 非 base64url 时都会命中）。
    if (statusCode < 300 ||
        statusCode >= 400 ||
        location.contains('wecomAuthFailed')) {
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(HttpTimeout.normal);
      throw WeComAuthException(
        'redeemFailed',
        text.contains('badRequestParams')
            ? '企业微信授权失败，请重新尝试'
            : '企业微信授权失败（HTTP $statusCode）',
      );
    }
    _debug('redeem ok status=$statusCode '
        'cookies=${cookies.map((c) => c.name).toList()}');
    _cookies.save(uri, cookies);
    await response.drain<void>();
    return WeComSessionResult(sessionCookies: cookies, cookieSourceUri: uri);
  }

  /// 阶段二：用已建立的 SSO 会话向 [target] 换取业务系统授权码回调地址。
  ///
  /// 先按目标系统的策略准备 `state`，再请求 `/oauth/authorize`，
  /// 返回其 302 的 Location。
  Future<Uri> authorizeTarget(WeComOAuthTarget target) async {
    _debug('authorizeTarget begin client=${target.clientName}');
    final state = await _prepareState(target);
    _debug('authorizeTarget stateLength=${state.length}');
    final uri = Uri.parse(WeComConstants.ssoBase).replace(
      path: WeComConstants.authorizePath,
      queryParameters: {
        'response_type': 'code',
        'client_id': target.clientId,
        'redirect_uri': target.redirectUri,
        if (target.scope.isNotEmpty) 'scope': target.scope,
        if (state.isNotEmpty) 'state': state,
      },
    );
    final response = await _get(uri, host: _RequestHost.sso);
    final statusCode = response.statusCode;
    final location = response.headers.value(HttpHeaders.locationHeader);
    await response.drain<void>();
    if (statusCode < 300 || statusCode >= 400 || location == null) {
      throw WeComAuthException(
        'authorizeFailed',
        'SSO 未返回 ${target.clientName} 的授权地址（HTTP $statusCode）',
      );
    }
    // 会话未被复用时会跳回登录页，说明 SHU_OAUTH2 没有生效。
    if (location.contains(WeComConstants.loginPathMarker)) {
      throw const WeComAuthException(
        'sessionNotReused',
        '企业微信会话未能复用，请重新登录',
      );
    }
    final callbackUri = uri.resolve(location);
    _validateRedirect(callbackUri, target.redirectUri);
    _debug('authorizeTarget ok location=${callbackUri.host}${callbackUri.path} '
        'queryKeys=${callbackUri.queryParameters.keys.toList()..sort()}');
    return callbackUri;
  }

  /// 按目标系统准备 `state`。
  Future<String> _prepareState(WeComOAuthTarget target) async {
    final bootstrapUrl = target.stateBootstrapUrl;
    if (bootstrapUrl != null && bootstrapUrl.isNotEmpty) {
      return _bootstrapState(Uri.parse(bootstrapUrl));
    }
    if (target.generateState) {
      // jwxt 的授权请求不带 state，本地生成随机值防 CSRF。
      final random = Random.secure();
      return List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
    }
    return '';
  }

  /// 向业务系统入口要一个 `state`。
  ///
  /// 入口通常不是 SSO 站点（如论坛的 `bbs.shu.edu.cn`），
  /// 因此 Referer/Origin 要覆盖为该入口自身的 origin，而非固定的 SSO 域，
  /// 否则可能被目标系统拒绝或行为不一致。
  Future<String> _bootstrapState(Uri uri) async {
    final origin = uri.replace(path: '', query: null, fragment: null);
    final response = await _get(
      uri,
      host: _RequestHost.sso,
      referer: origin.toString(),
      origin: origin.toString(),
    );
    final location = response.headers.value(HttpHeaders.locationHeader);
    await response.drain<void>();
    if (location == null || location.isEmpty) return '';
    return uri.resolve(location).queryParameters['state'] ?? '';
  }

  /// 单次长轮询请求，返回扫码状态。
  ///
  /// 除企微域 Referer/Origin 外还带 `x-requested-with: XMLHttpRequest`
  /// 与 JS 的 Accept，保证企微侧识别为异步请求。
  Future<WeComScanResult> _pollOnce(String key) async {
    final uri = Uri.parse(WeComConstants.longPollBase).replace(
      queryParameters: {
        'callback': 'jsonpCallback',
        'key': key,
        'redirect_uri': WeComConstants.redirectUri,
        'appid': WeComConstants.appId,
        '_': DateTime.now().millisecondsSinceEpoch.toString(),
      },
    );
    HttpClientResponse response;
    try {
      response = await _get(
        uri,
        host: _RequestHost.weCom,
        accept:
            'text/javascript, application/javascript, application/ecmascript, */*; q=0.01',
        extraHeaders: const {'x-requested-with': 'XMLHttpRequest'},
      );
    } on TimeoutException {
      // 长轮询单个请求超时（约 40s）不视为失败，继续下一次轮询。
      return WeComScanResult.waiting();
    } on Object {
      return WeComScanResult.waiting();
    }
    final body = await utf8.decodeStream(response).timeout(HttpTimeout.normal);
    final match = _jsonpPattern.firstMatch(body);
    if (match == null) {
      return WeComScanResult.waiting();
    }
    try {
      final json = jsonDecode(match.group(1)!) as Map<String, dynamic>;
      final status = json['status']?.toString() ?? '';
      final authCode = json['auth_code']?.toString() ?? '';
      return _parseStatus(status, authCode);
    } on Object {
      return WeComScanResult.waiting();
    }
  }

  WeComScanResult _parseStatus(String status, String authCode) {
    switch (status) {
      case 'QRCODE_SCAN_SUCC':
        if (authCode.isNotEmpty) {
          return WeComScanResult.succeeded(authCode);
        }
        return WeComScanResult.confirmedPending();
      case 'QRCODE_SCAN_ING':
        return WeComScanResult.confirmedPending();
      case 'QRCODE_SCAN_ERR':
      case 'QRCODE_SCAN_OVERDUE':
      case 'QRCODE_SCAN_CANCEL':
        return WeComScanResult.expired();
      default:
        return WeComScanResult.waiting();
    }
  }

  /// 发起请求并按 [host] 选择请求头。
  ///
  /// 默认头指向 SSO 站点，只有企微扫码相关请求才覆盖成企微域的头，
  /// 否则企微侧可能拒绝。可通过 [referer]/[origin] 显式覆盖默认来源。
  Future<HttpClientResponse> _get(
    Uri uri, {
    required _RequestHost host,
    String? accept,
    Map<String, String> extraHeaders = const {},
    String? referer,
    String? origin,
  }) async {
    final request = await _client.getUrl(uri).timeout(HttpTimeout.connect);
    request.followRedirects = false;
    request.headers
      ..set(
        HttpHeaders.acceptHeader,
        accept ?? 'text/html,application/xhtml+xml,*/*;q=0.8',
      )
      ..set(HttpHeaders.userAgentHeader, ClientUserAgent.mobileBrowser);
    switch (host) {
      case _RequestHost.weCom:
        request.headers
          ..set(
            HttpHeaders.refererHeader,
            referer ?? WeComConstants.qrConnectBase,
          )
          ..set(
            'Origin',
            origin ?? 'https://${WeComConstants.weComHost}',
          );
      case _RequestHost.sso:
        request.headers
          ..set(HttpHeaders.refererHeader, referer ?? WeComConstants.ssoBase)
          ..set('Origin', origin ?? WeComConstants.ssoBase);
    }
    for (final entry in extraHeaders.entries) {
      request.headers.set(entry.key, entry.value);
    }
    final cookieHeader = _cookies.headerFor(uri);
    if (cookieHeader.isNotEmpty) {
      request.headers.set(HttpHeaders.cookieHeader, cookieHeader);
    }
    late final HttpClientResponse response;
    try {
      response = await request.close().timeout(HttpTimeout.normal);
    } on Object catch (error) {
      _debug('request-failed ${uri.host}${uri.path} '
          'type=${error.runtimeType} error=$error');
      rethrow;
    }
    // 除 redeem 外的响应在这里就把 Set-Cookie 收下，模拟 Session 行为。
    final cookies = _parseCookies(response);
    _debug('response ${uri.host}${uri.path} status=${response.statusCode} '
        'location=${response.headers.value(HttpHeaders.locationHeader) ?? '-'} '
        'cookies=${cookies.map((c) => c.name).toList()}');
    _cookies.save(uri, cookies);
    return response;
  }

  /// 宽松解析 `Set-Cookie`。
  ///
  /// `dart:io` 的 [HttpClientResponse.cookies] 会对每条 Set-Cookie 做严格
  /// 校验，遇到企微扫码域下发的非法值（例如含逗号）会**整体**抛出
  /// [FormatException]。这里逐条解析，跳过不符合 RFC 6265 的条目——
  /// 这些 Cookie 只属于企微扫码域，本流程并不需要它们。
  static List<Cookie> _parseCookies(HttpClientResponse response) {
    final cookies = <Cookie>[];
    final values = response.headers[HttpHeaders.setCookieHeader];
    if (values == null) return cookies;
    for (final value in values) {
      try {
        cookies.add(Cookie.fromSetCookieValue(value));
      } on FormatException {
        _debug('skip malformed set-cookie');
      }
    }
    return cookies;
  }

  /// 校验授权回调地址。
  ///
  /// 只允许 [scheme] 为 https 且 host/path 与目标系统的 [expectedRedirect] 一致，
  /// 防止 SSO 返回任意 https 地址时导航到恶意站点（开放重定向）。
  void _validateRedirect(Uri uri, String expectedRedirect) {
    if (uri.scheme != 'https' || uri.host.isEmpty) {
      throw const WeComAuthException(
        'unsafeRedirect',
        '企业微信授权返回了不安全的跳转地址',
      );
    }
    final expected = Uri.parse(expectedRedirect);
    if (uri.host != expected.host || uri.path != expected.path) {
      _debug('redirect mismatch location=${uri.host}${uri.path} '
          'expected=${expected.host}${expected.path}');
      throw const WeComAuthException(
        'unexpectedRedirect',
        '企业微信授权返回了未预期的跳转地址',
      );
    }
  }
}

/// 请求所属站点，决定 Referer/Origin。
enum _RequestHost { weCom, sso }
