import 'package:shared_preferences/shared_preferences.dart';

class AcademicAccountStore {
  AcademicAccountStore({
    Future<SharedPreferences> Function()? preferencesLoader,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const studentIdKey = 'academic.account.student_id';

  final Future<SharedPreferences> Function() _preferencesLoader;

  Future<String?> loadStudentId() async {
    final value = (await _preferencesLoader()).getString(studentIdKey)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> saveStudentId(String studentId) async {
    final normalized = studentId.trim();
    if (normalized.isEmpty) return;
    await (await _preferencesLoader()).setString(studentIdKey, normalized);
  }

  Future<void> clear() async {
    await (await _preferencesLoader()).remove(studentIdKey);
  }
}
