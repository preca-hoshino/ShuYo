import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../core/academic_constants.dart';
import '../../core/academic_url_resolver.dart';
import '../../core/client_user_agent.dart';
import '../models/academic_schedule.dart';
import '../models/common.dart';
import 'academic_auth_service.dart';
import 'http_timeout.dart';

class AcademicApiException implements Exception {
  const AcademicApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() {
    final code = statusCode;
    if (code == null) {
      return message;
    }
    return '$message ($code)';
  }
}

class AcademicAuthException extends AcademicApiException {
  const AcademicAuthException([
    super.message = '需要先登录教务系统',
    int? statusCode,
  ]) : super(statusCode: statusCode);
}

class AcademicTermQuery {
  const AcademicTermQuery({
    required this.yearCode,
    required this.termCode,
    this.academicYearName = '',
    this.termName = '',
  });

  final String yearCode;
  final String termCode;
  final String academicYearName;
  final String termName;

  bool get isValid => yearCode.isNotEmpty && termCode.isNotEmpty;
}

class AcademicScheduleApiClient {
  AcademicScheduleApiClient({
    AcademicAuthService? authService,
    http.Client? httpClient,
  })  : _authService = authService ?? AcademicAuthService(),
        _httpClient = httpClient ?? _defaultHttpClient();

  final AcademicAuthService _authService;
  final http.Client _httpClient;

  static http.Client _defaultHttpClient() {
    return IOClient(HttpClient());
  }

  Future<AcademicSchedule> fetchCurrentSchedule() {
    return HttpTimeout.request(
      _fetchCurrentSchedule(),
      timeout: HttpTimeout.composed,
      message: '课表同步超时，请稍后再试',
    );
  }

  Future<AcademicSchedule> _fetchCurrentSchedule() async {
    _debug(
        'sync start mode=${AcademicUrlResolver.usesWebVpn ? 'webvpn' : 'direct'}');
    try {
      final term = await fetchCurrentTermQuery();
      if (!term.isValid) {
        throw const AcademicApiException('未能识别当前学期');
      }
      _debug('term resolved year=${term.yearCode} term=${term.termCode}');
      final json = await fetchScheduleJson(term);
      final schedule = AcademicScheduleParser.parse(json);
      _debug('sync success');
      return schedule;
    } on Object catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('[SHU_SCHEDULE_API] sync failed: $error');
        debugPrintStack(
          label: '[SHU_SCHEDULE_API] stack',
          stackTrace: stackTrace,
        );
      }
      rethrow;
    }
  }

  Future<AcademicTermQuery> fetchCurrentTermQuery() async {
    final response = await HttpTimeout.request(
      _httpClient.get(
        _uri(AcademicConstants.scheduleIndexPath),
        headers: await _headers(accept: 'text/html,application/xhtml+xml'),
      ),
      message: '教务系统请求超时，请稍后再试',
    );
    _debugResponse('schedule-index', response);
    _ensureSuccess(response);
    final html = response.body;
    _ensureNotLoginPage(html);
    final yearCode = _selectedOptionValue(html, 'xnm') ??
        _hiddenInputValue(html, 'xnm') ??
        '';
    final termCode = _selectedOptionValue(html, 'xqm') ??
        _hiddenInputValue(html, 'xqm') ??
        '';
    return AcademicTermQuery(
      yearCode: yearCode,
      termCode: termCode,
      academicYearName: _selectedOptionText(html, 'xnm') ??
          _hiddenInputValue(html, 'xnmc') ??
          '',
      termName: _selectedOptionText(html, 'xqm') ??
          _hiddenInputValue(html, 'xqmmc') ??
          '',
    );
  }

  Future<JsonMap> fetchScheduleJson(AcademicTermQuery term) async {
    final body = Uri(
      queryParameters: {
        'xnm': term.yearCode,
        'xqm': term.termCode,
        'kzlx': 'ck',
        'xsdm': '',
        'kclbdm': '',
        'kclxdm': '',
      },
    ).query;
    final response = await HttpTimeout.request(
      _httpClient.post(
        _uri(AcademicConstants.scheduleDataPath),
        headers: await _headers(
          accept: '*/*',
          formRequest: true,
        ),
        body: body,
      ),
      message: '教务系统请求超时，请稍后再试',
    );
    _debugResponse('schedule-data', response);
    _ensureSuccess(response);
    _ensureNotLoginPage(response.body);
    final decoded = jsonDecode(response.body);
    if (decoded is! JsonMap) {
      throw const AcademicApiException('教务系统返回了无法识别的课表数据');
    }
    if (decoded['kbList'] is! List || decoded['xsxx'] is! JsonMap) {
      throw const AcademicApiException('教务系统返回的数据不包含课表');
    }
    return decoded;
  }

  Future<Map<String, String>> _headers({
    required String accept,
    bool formRequest = false,
  }) async {
    final cookie = await _authService.cookieHeader(
      targetUri: _uri(AcademicConstants.scheduleIndexPath),
    );
    if (cookie == null || cookie.isEmpty) {
      _debug('cookie header unavailable');
      throw const AcademicAuthException('未读取到教务系统 Cookie，请先打开教务系统并确认已登录');
    }
    final cookieNames = cookie
        .split(';')
        .map((part) => part.trim().split('=').first)
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    _debug('request cookies=$cookieNames');
    return {
      'accept': accept,
      'cookie': cookie,
      'referer': AcademicUrlResolver.usesWebVpn
          ? AcademicUrlResolver.scheduleIndexUri.toString()
          : '${AcademicUrlResolver.baseUrl}${AcademicConstants.scheduleIndexPath}',
      'user-agent': ClientUserAgent.mobileBrowser,
      'x-requested-with': formRequest ? 'XMLHttpRequest' : '',
      if (formRequest)
        'content-type': 'application/x-www-form-urlencoded;charset=UTF-8',
    }..removeWhere((_, value) => value.isEmpty);
  }

  Uri _uri(String path) => AcademicUrlResolver.uri(path);

  void _ensureSuccess(http.Response response) {
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw AcademicAuthException('教务登录已失效', response.statusCode);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AcademicApiException(
        '教务系统请求失败',
        statusCode: response.statusCode,
      );
    }
  }

  void _ensureNotLoginPage(String body) {
    if (_loginPageSignals(body).isNotEmpty) {
      throw const AcademicAuthException('教务登录已失效，请重新登录');
    }
  }

  void _debugResponse(String requestName, http.Response response) {
    if (!kDebugMode) return;
    final requestUri = response.request?.url;
    final title = RegExp(
      r'<title[^>]*>([\s\S]*?)</title>',
      caseSensitive: false,
    )
        .firstMatch(response.body)
        ?.group(1)
        ?.replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final safeTitle =
        title == null ? '-' : title.substring(0, title.length.clamp(0, 80));
    final contentType = response.headers['content-type'] ?? '-';
    final signals = _loginPageSignals(response.body);
    _debug(
      'response request=$requestName '
      'uri=${requestUri == null ? '-' : _describeUri(requestUri)} '
      'status=${response.statusCode} contentType=$contentType '
      'bytes=${response.bodyBytes.length} title="$safeTitle" '
      'loginSignals=$signals',
    );
  }

  List<String> _loginPageSignals(String body) {
    final lower = body.toLowerCase();
    return <(String, String)>[
      ('oauth2-login', '/oauth2/login'),
      ('newsso-host', 'newsso.shu.edu.cn'),
      ('legacy-login', 'jwglxt/xtgl/login_slogin'),
      ('username-double-quote', 'name="yhm"'),
      ('username-single-quote', "name='yhm'"),
    ]
        .where((entry) => lower.contains(entry.$2))
        .map((entry) => entry.$1)
        .toList();
  }

  String _describeUri(Uri uri) {
    final keys = uri.queryParameters.keys.toList()..sort();
    return '${uri.host}${uri.path}${keys.isEmpty ? '' : ' queryKeys=$keys'}';
  }

  void _debug(String message) {
    if (kDebugMode) debugPrint('[SHU_SCHEDULE_API] $message');
  }

  String? _selectedOptionValue(String html, String selectId) {
    final option = _selectedOption(html, selectId);
    if (option == null) {
      return null;
    }
    return RegExp(
      r'''value\s*=\s*["']([^"']*)["']''',
      caseSensitive: false,
    ).firstMatch(option)?.group(1);
  }

  String? _selectedOptionText(String html, String selectId) {
    final option = _selectedOption(html, selectId);
    if (option == null) {
      return null;
    }
    return option
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .trim();
  }

  String? _selectedOption(String html, String selectId) {
    final select = RegExp(
      '<select[^>]+id=["\\\']$selectId["\\\'][\\s\\S]*?</select>',
      caseSensitive: false,
    ).firstMatch(html)?.group(0);
    if (select == null) {
      return null;
    }
    return RegExp(
      r'''<option\b[^>]*selected\b[^>]*>[\s\S]*?</option>''',
      caseSensitive: false,
    ).firstMatch(select)?.group(0);
  }

  String? _hiddenInputValue(String html, String name) {
    final input = RegExp(
      '<input[^>]+name=["\\\']$name["\\\'][^>]*>',
      caseSensitive: false,
    ).firstMatch(html)?.group(0);
    if (input == null) {
      return null;
    }
    return RegExp(
      r'''value\s*=\s*["']([^"']*)["']''',
      caseSensitive: false,
    ).firstMatch(input)?.group(1);
  }
}
