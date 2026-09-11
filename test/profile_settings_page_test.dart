import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuyo/data/models/discourse_user.dart';
import 'package:shuyo/data/models/user_profile.dart';
import 'package:shuyo/data/repositories/forum_repository.dart';
import 'package:shuyo/features/profile/profile_settings_page.dart';
import 'package:shuyo/shared/theme/shuyo_theme.dart';

void main() {
  testWidgets('save is disabled until profile fields change', (tester) async {
    await _pumpPage(tester, _ProfileRepository());

    TextButton saveButton() => tester.widget<TextButton>(
          find.widgetWithText(TextButton, '保存'),
        );

    expect(saveButton().onPressed, isNull);

    final bio = find.byType(TextField);
    await tester.enterText(bio, '新签名');
    await tester.pump();
    expect(saveButton().onPressed, isNotNull);

    await tester.enterText(bio, '');
    await tester.pump();
    expect(saveButton().onPressed, isNull);
  });

  testWidgets('bio input is limited to 20 user-perceived characters',
      (tester) async {
    await _pumpPage(tester, _ProfileRepository());

    final bio = find.byType(TextField);
    await tester.enterText(bio, '一二三四五六七八九十一二三四五六七八九十超');
    await tester.pump();

    expect(
        tester.widget<TextField>(bio).controller!.text, '一二三四五六七八九十一二三四五六七八九十');
    expect(find.text('20/20'), findsOneWidget);
  });

  testWidgets('back navigation warns when changes are unsaved', (tester) async {
    await _pumpPage(tester, _ProfileRepository());
    await tester.enterText(find.byType(TextField), '未保存');
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('放弃未保存的修改？'), findsOneWidget);
    expect(find.text('继续修改'), findsOneWidget);
  });

  testWidgets(
      'avatar actions use the edit badge and clear background is staged',
      (tester) async {
    await _pumpPage(tester, _ProfileRepository(backgroundUrl: '/cover.jpg'));

    expect(find.text('系统分配'), findsNothing);
    expect(find.text('个人资料标题'), findsNothing);
    expect(find.text('个人主页背景'), findsOneWidget);

    await tester.tap(find.byTooltip('编辑头像'));
    await tester.pumpAndSettle();
    expect(find.text('选择自定义头像'), findsOneWidget);
    expect(find.text('使用默认头像'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    final clear = find.widgetWithText(OutlinedButton, '清除背景');
    expect(tester.widget<OutlinedButton>(clear).onPressed, isNotNull);
    await tester.tap(clear);
    await tester.pump();
    final repository = tester
        .widget<ProfileSettingsPage>(find.byType(ProfileSettingsPage))
        .repository as _ProfileRepository;
    expect(repository.savedDraft, isNull);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '保存'))
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();
    expect(repository.savedDraft?.profileBackgroundUploadUrl, isEmpty);
  });

  testWidgets('default avatar remains local until save', (tester) async {
    final repository = _ProfileRepository(customAvatar: true);
    await _pumpPage(tester, repository);

    await tester.tap(find.byTooltip('编辑头像'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用默认头像'));
    await tester.pumpAndSettle();

    expect(repository.systemAvatarCalls, 0);
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();
    expect(repository.systemAvatarCalls, 1);
  });

  testWidgets('saved page returns a committed change result', (tester) async {
    final repository = _ProfileRepository(customAvatar: true);
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: ShuYoThemes.byId(ShuYoThemes.defaultId).themeData(),
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                result = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => ProfileSettingsPage(
                      repository: repository,
                    ),
                  ),
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑头像'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用默认头像'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('打开'), findsOneWidget);
    expect(result, isTrue);
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  ForumRepository repository,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ShuYoThemes.byId(ShuYoThemes.defaultId).themeData(),
      home: ProfileSettingsPage(repository: repository),
    ),
  );
  await tester.pumpAndSettle();
}

class _ProfileRepository implements ForumRepository {
  _ProfileRepository({String backgroundUrl = '', bool customAvatar = false})
      : current = UserProfile(
          user: DiscourseUser(
            id: 1,
            username: 'tester',
            avatarTemplate: customAvatar ? '/custom/{size}.png' : '',
          ),
          profileBackgroundUploadUrl: backgroundUrl,
          systemAvatarTemplate: '/system/{size}.png',
          customAvatarTemplate: customAvatar ? '/custom/{size}.png' : '',
          customAvatarUploadId: customAvatar ? 12 : null,
          canEdit: true,
          canUploadProfileHeader: true,
        );

  UserProfile current;
  ProfileSettingsDraft? savedDraft;
  int systemAvatarCalls = 0;

  @override
  UserProfile get profile => current;

  @override
  Future<UserProfile> fetchCurrentUserProfile(
      {bool forceRefresh = false}) async {
    return current;
  }

  @override
  Future<UserProfile> updateProfileSettings(ProfileSettingsDraft draft) async {
    savedDraft = draft;
    return current = UserProfile(
      user: current.user,
      bioRaw: draft.bioRaw,
      profileBackgroundUploadUrl: draft.profileBackgroundUploadUrl,
      cardBackgroundUploadUrl: draft.cardBackgroundUploadUrl,
      hideProfile: draft.hideProfile,
      timezone: draft.timezone,
      defaultCalendar: draft.defaultCalendar,
      canEdit: true,
      canUploadProfileHeader: true,
    );
  }

  @override
  Future<UserProfile> useSystemAvatar() async {
    systemAvatarCalls++;
    return current = UserProfile(
      user: const DiscourseUser(
        id: 1,
        username: 'tester',
        avatarTemplate: '/system/{size}.png',
      ),
      bioRaw: current.bioRaw,
      profileBackgroundUploadUrl: current.profileBackgroundUploadUrl,
      systemAvatarTemplate: '/system/{size}.png',
      hideProfile: current.hideProfile,
      canEdit: true,
      canUploadProfileHeader: true,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
