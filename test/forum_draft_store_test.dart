import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/data/services/forum_draft_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('migrates v1 drafts into account-scoped v2 drafts', () async {
    SharedPreferences.setMockInitialValues({});
    final legacyKey = ForumDraftStore.topicReplyKey(
      username: 'Lilin',
      topicId: 824,
      replyToPostNumber: 6,
    );
    await ForumDraftStore.save(
      legacyKey,
      const ForumComposerDraft(raw: '迁移后的回复'),
    );

    final drafts = await ForumDraftStore.list('Lilin');

    expect(drafts, hasLength(1));
    expect(drafts.single.type, ForumDraftType.topicReply);
    expect(drafts.single.topicId, 824);
    expect(drafts.single.replyToPostNumber, 6);
    expect(drafts.single.raw, '迁移后的回复');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(legacyKey), isFalse);
  });

  test('keeps drafts isolated by account', () async {
    SharedPreferences.setMockInitialValues({});
    await ForumDraftStore.saveDraft(
      ForumComposerDraft(
        id: 'first',
        type: ForumDraftType.newTopic,
        username: 'Lilin',
        raw: 'Lilin 的草稿',
      ),
    );
    await ForumDraftStore.saveDraft(
      ForumComposerDraft(
        id: 'second',
        type: ForumDraftType.newTopic,
        username: 'Other',
        raw: '其他账号的草稿',
      ),
    );

    expect((await ForumDraftStore.list('Lilin')).single.raw, 'Lilin 的草稿');
    expect((await ForumDraftStore.list('Other')).single.raw, '其他账号的草稿');
  });

  test('keeps newest 10 topic drafts and newest 50 other drafts', () async {
    SharedPreferences.setMockInitialValues({});
    for (var index = 0; index < 12; index++) {
      await ForumDraftStore.saveDraft(
        ForumComposerDraft(
          id: 'topic-$index',
          type: ForumDraftType.newTopic,
          username: 'Lilin',
          raw: '新帖 $index',
        ),
      );
    }
    for (var index = 0; index < 55; index++) {
      await ForumDraftStore.saveDraft(
        ForumComposerDraft(
          id: 'reply-$index',
          type: ForumDraftType.topicReply,
          username: 'Lilin',
          topicId: 1000 + index,
          raw: '回复 $index',
        ),
      );
    }

    final drafts = await ForumDraftStore.list('Lilin');
    expect(
      drafts.where((draft) => draft.type == ForumDraftType.newTopic),
      hasLength(10),
    );
    expect(
      drafts.where((draft) => draft.type != ForumDraftType.newTopic),
      hasLength(50),
    );
    expect(drafts.any((draft) => draft.id == 'topic-0'), isFalse);
    expect(drafts.any((draft) => draft.id == 'reply-0'), isFalse);
  });

  test('newer revisions cannot be overwritten by stale saves', () async {
    SharedPreferences.setMockInitialValues({});
    const base = ForumComposerDraft(
      id: 'revisioned',
      type: ForumDraftType.topicReply,
      username: 'Lilin',
      topicId: 824,
    );
    await ForumDraftStore.saveDraft(
      base.copyWith(raw: '较新内容', revision: 2),
    );
    await ForumDraftStore.saveDraft(
      base.copyWith(raw: '旧内容', revision: 1),
    );

    final loaded = await ForumDraftStore.loadById('Lilin', 'revisioned');
    expect(loaded?.raw, '较新内容');
    expect(loaded?.revision, 2);
  });
}
