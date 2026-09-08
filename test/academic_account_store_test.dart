import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/data/services/academic_account_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('academic account expiration persists until a successful login',
      () async {
    final store = AcademicAccountStore();
    await store.saveStudentId('25120001');
    expect(await store.isSessionExpired(), isFalse);

    await store.markSessionExpired();
    expect(await store.loadStudentId(), '25120001');
    expect(await store.isSessionExpired(), isTrue);

    await store.saveStudentId('25120001');
    expect(await store.isSessionExpired(), isFalse);
  });

  test('logout removes both the account and its expiration state', () async {
    final store = AcademicAccountStore();
    await store.saveStudentId('25120001');
    await store.markSessionExpired();

    await store.clear();

    expect(await store.loadStudentId(), isNull);
    expect(await store.isSessionExpired(), isFalse);
  });
}
