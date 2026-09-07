import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/data/models/composer.dart';
import 'package:shuyo/data/models/topic_detail.dart';
import 'package:shuyo/data/services/forum_draft_store.dart';
import 'package:shuyo/data/services/payload_factory.dart';
import 'package:shuyo/features/topic/advanced_reply_composer_page.dart';

void main() {
  testWidgets('system back flushes advanced reply into the shared draft',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final session = ForumDraftSession(
      ForumComposerDraft(
        id: 'advanced-back',
        type: ForumDraftType.topicReply,
        username: 'Lilin',
        topicId: 824,
        topicTitle: '测试主题',
      ),
    );
    addTearDown(session.dispose);
    const detail = TopicDetail(
      id: 824,
      title: '测试主题',
      categoryId: 1,
      postsCount: 1,
      highestPostNumber: 1,
      canCreatePost: true,
      canDelete: false,
      posts: [],
      postStreamIds: [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (context) => AdvancedReplyComposerPage(
                    detail: detail,
                    initialRaw: '',
                    initialImages: const [],
                    replyToPostNumber: null,
                    draftSession: session,
                    onUploadImage: (_) => Future<UploadedImage>.error('unused'),
                    onSubmit: (ReplyDraft _) async => false,
                  ),
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '不会丢失的进阶回复');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(session.draft.raw, '不会丢失的进阶回复');
    final stored = await ForumDraftStore.loadById('Lilin', 'advanced-back');
    expect(stored?.raw, '不会丢失的进阶回复');
  });
}
