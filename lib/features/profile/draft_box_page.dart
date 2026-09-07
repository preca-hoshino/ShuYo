import 'package:flutter/material.dart';

import '../../data/repositories/forum_repository.dart';
import '../../data/services/forum_draft_store.dart';
import '../../shared/navigation/shuyo_route.dart';
import '../../shared/theme/shuyo_theme.dart';
import '../../shared/time_format.dart';
import '../../shared/widgets/empty_state.dart';
import '../forum/create_topic_page.dart';
import 'user_profile_page.dart';

class DraftBoxPage extends StatefulWidget {
  const DraftBoxPage({super.key, required this.repository});

  final ForumRepository repository;

  @override
  State<DraftBoxPage> createState() => _DraftBoxPageState();
}

class _DraftBoxPageState extends State<DraftBoxPage> {
  late Future<List<ForumComposerDraft>> _future;

  String get _username => widget.repository.profile.username;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('草稿箱')),
      body: FutureBuilder<List<ForumComposerDraft>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
                child: CircularProgressIndicator(strokeWidth: 3));
          }
          if (snapshot.hasError) {
            return EmptyState(
              icon: Icons.error_outline,
              title: '草稿加载失败',
              message: '${snapshot.error}',
              action: TextButton.icon(
                onPressed: () => setState(_reload),
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            );
          }
          final drafts = snapshot.data ?? const <ForumComposerDraft>[];
          if (drafts.isEmpty) {
            return const EmptyState(
              icon: Icons.drafts_outlined,
              title: '暂无草稿',
              message: '未完成的帖子和私信会保存在这里',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: drafts.length,
            separatorBuilder: (context, index) =>
                Divider(height: 1, color: context.shuyoColors.border),
            itemBuilder: (context, index) => _draftTile(drafts[index]),
          );
        },
      ),
    );
  }

  Widget _draftTile(ForumComposerDraft draft) {
    final colors = context.shuyoColors;
    return ListTile(
      leading: Icon(_icon(draft.type), color: colors.textSecondary),
      title: Text(
        _title(draft),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${_typeLabel(draft.type)} · ${_preview(draft)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            TimeFormat.compact(draft.updatedAt, relativeWithinDay: true),
            style: TextStyle(color: colors.textMuted, fontSize: 12),
          ),
          IconButton(
            tooltip: '删除草稿',
            onPressed: () => _delete(draft),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      onTap: () => _open(draft),
    );
  }

  Future<void> _open(ForumComposerDraft draft) async {
    switch (draft.type) {
      case ForumDraftType.newTopic:
        await Navigator.of(context).push<CreatedTopicResult>(
          shuyoRoute(
            builder: (context) => CreateTopicPage(
              repository: widget.repository,
              categories: widget.repository.categories,
              initialCategoryId: draft.categoryId,
              initialDraftId: draft.id,
            ),
          ),
        );
      case ForumDraftType.topicReply:
        return;
      case ForumDraftType.newPrivateMessage:
        await showPrivateMessageComposer(
          context,
          repository: widget.repository,
          recipient: draft.recipient,
          initialDraftId: draft.id,
        );
      case ForumDraftType.privateMessageReply:
        return;
      case null:
        return;
    }
    if (mounted) setState(_reload);
  }

  Future<void> _delete(ForumComposerDraft draft) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除草稿？'),
        content: const Text('删除后无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ForumDraftStore.removeDraft(_username, draft.id);
    if (mounted) setState(_reload);
  }

  void _reload() {
    _future = _visibleDrafts();
  }

  Future<List<ForumComposerDraft>> _visibleDrafts() async {
    final drafts = await ForumDraftStore.list(_username);
    return drafts
        .where(
          (draft) =>
              draft.type == ForumDraftType.newTopic ||
              draft.type == ForumDraftType.newPrivateMessage,
        )
        .toList(growable: false);
  }

  String _title(ForumComposerDraft draft) {
    if (draft.title.trim().isNotEmpty) return draft.title.trim();
    if (draft.topicTitle.trim().isNotEmpty) return draft.topicTitle.trim();
    if (draft.recipient.trim().isNotEmpty) return '发给 ${draft.recipient}';
    final topicId = draft.topicId;
    return topicId == null ? '未命名草稿' : '主题 #$topicId';
  }

  String _preview(ForumComposerDraft draft) {
    final raw = draft.raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (raw.isNotEmpty) return raw;
    if (draft.images.isNotEmpty) return '${draft.images.length} 张图片';
    return '暂无正文';
  }

  String _typeLabel(ForumDraftType? type) => switch (type) {
        ForumDraftType.newTopic => '新帖',
        ForumDraftType.topicReply => '帖子回复',
        ForumDraftType.newPrivateMessage => '新私信',
        ForumDraftType.privateMessageReply => '私信回复',
        null => '草稿',
      };

  IconData _icon(ForumDraftType? type) => switch (type) {
        ForumDraftType.newTopic => Icons.post_add_outlined,
        ForumDraftType.topicReply => Icons.reply_outlined,
        ForumDraftType.newPrivateMessage => Icons.mail_outline,
        ForumDraftType.privateMessageReply => Icons.chat_bubble_outline,
        null => Icons.drafts_outlined,
      };
}
