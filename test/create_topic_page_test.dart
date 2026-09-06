import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/data/models/category.dart';
import 'package:shuyo/data/repositories/forum_repository.dart';
import 'package:shuyo/features/forum/create_topic_page.dart';
import 'package:shuyo/shared/theme/shuyo_theme.dart';
import 'package:shuyo/shared/widgets/advanced_markdown_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
      'advanced composer keeps category behind keyboard and resizes editor',
      (tester) async {
    final repository = await FixtureForumRepository.load();
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(
      MaterialApp(
        theme: ShuYoThemes.byId(ShuYoThemes.defaultId).themeData(),
        home: CreateTopicPage(
          repository: repository,
          categories: const [
            ForumCategory(
              id: 1,
              name: '测试分区',
              slug: 'test',
              color: '333333',
              textColor: 'FFFFFF',
            ),
          ],
          initialCategoryId: 1,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('选择编辑模式'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('进阶').last);
    await tester.pumpAndSettle();

    final category = find.text('测试分区');
    final editor = find.byType(AdvancedMarkdownEditor);
    final categoryTopBefore = tester.getTopLeft(category).dy;
    final editorBottomBefore = tester.getBottomRight(editor).dy;

    const keyboardHeight = 300.0;
    tester.view.viewInsets = FakeViewPadding(
      bottom: keyboardHeight * tester.view.devicePixelRatio,
    );
    await tester.pumpAndSettle();

    final keyboardTop =
        tester.view.physicalSize.height / tester.view.devicePixelRatio -
            keyboardHeight;
    expect(tester.getTopLeft(category).dy, categoryTopBefore);
    expect(tester.getTopLeft(category).dy, greaterThan(keyboardTop));
    expect(tester.getBottomRight(editor).dy, lessThan(keyboardTop));

    tester.view.viewInsets = FakeViewPadding(
      bottom: 30 * tester.view.devicePixelRatio,
    );
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(category).dy, categoryTopBefore);
    expect(tester.getBottomRight(editor).dy, editorBottomBefore);
  });
}
