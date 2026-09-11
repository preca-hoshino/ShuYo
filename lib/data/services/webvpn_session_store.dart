import 'package:shared_preferences/shared_preferences.dart';

class WebVpnSessionStore {
  WebVpnSessionStore({
    Future<SharedPreferences> Function()? preferencesLoader,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const cachedCookiesKey = 'academic.auth.cached_cookies.webvpn';

  final Future<SharedPreferences> Function() _preferencesLoader;

  Future<void> clearCachedCookiesForReauthentication() async {
    await (await _preferencesLoader()).remove(cachedCookiesKey);
  }
}
