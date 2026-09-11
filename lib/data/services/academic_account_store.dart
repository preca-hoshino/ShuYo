import 'package:shared_preferences/shared_preferences.dart';

class AcademicAccountStore {
  AcademicAccountStore({
    Future<SharedPreferences> Function()? preferencesLoader,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const studentIdKey = 'academic.account.student_id';
  static const sessionExpiredKey = 'academic.account.session_expired';

  final Future<SharedPreferences> Function() _preferencesLoader;

  Future<String?> loadStudentId() async {
    final value = (await _preferencesLoader()).getString(studentIdKey)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> saveStudentId(String studentId) async {
    final normalized = studentId.trim();
    if (normalized.isEmpty) return;
    final preferences = await _preferencesLoader();
    await Future.wait([
      preferences.setString(studentIdKey, normalized),
      preferences.setBool(sessionExpiredKey, false),
    ]);
  }

  Future<bool> isSessionExpired() async {
    return (await _preferencesLoader()).getBool(sessionExpiredKey) ?? false;
  }

  Future<void> markSessionExpired() async {
    final preferences = await _preferencesLoader();
    if (preferences.getString(studentIdKey)?.trim().isNotEmpty == true) {
      await preferences.setBool(sessionExpiredKey, true);
    }
  }

  Future<void> clear() async {
    final preferences = await _preferencesLoader();
    await Future.wait([
      preferences.remove(studentIdKey),
      preferences.remove(sessionExpiredKey),
    ]);
  }
}
