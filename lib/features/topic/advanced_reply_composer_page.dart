import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/models/composer.dart';
import '../../data/models/topic_detail.dart';
import '../../data/services/forum_draft_store.dart';
import '../../data/services/local_image_picker.dart';
import '../../data/services/payload_factory.dart';
import '../../shared/navigation/shuyo_route.dart';
import '../../shared/theme/shuyo_theme.dart';
import '../../shared/widgets/advanced_markdown_editor.dart';
import '../../shared/widgets/composer_attachments.dart';

class AdvancedReplyComposerResult {
  const AdvancedReplyComposerResult({
    required this.raw,
    required this.images,
    required this.submitted,
  });

  final String raw;
  final List<UploadedImage> images;
  final bool submitted;
}

class AdvancedReplyComposerPage extends StatefulWidget {
  const AdvancedReplyComposerPage({
    super.key,
    required this.detail,
    required this.initialRaw,
    required this.initialImages,
    required this.replyToPostNumber,
    required this.draftSession,
    required this.onUploadImage,
    required this.onSubmit,
  });

  final TopicDetail detail;
  final String initialRaw;
  final List<UploadedImage> initialImages;
  final int? replyToPostNumber;
  final ForumDraftSession draftSession;
  final Future<UploadedImage> Function(PickedImage image) onUploadImage;
  final Future<bool> Function(ReplyDraft draft) onSubmit;

  @override
  State<AdvancedReplyComposerPage> createState() =>
      _AdvancedReplyComposerPageState();
}

class _AdvancedReplyComposerPageState extends State<AdvancedReplyComposerPage> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _images = <UploadedImage>[];
  bool _uploading = false;
  bool _submitting = false;
  bool _submitted = false;
  bool _allowPop = false;

  bool get _canSend =>
      !_uploading &&
      !_submitting &&
      (_controller.text.trim().isNotEmpty || _images.isNotEmpty);

  @override
  void initState() {
    super.initState();
    _controller.text = widget.initialRaw;
    _images.addAll(widget.initialImages);
    _controller.addListener(_scheduleDraftSave);
  }

  @override
  void dispose() {
    if (!_submitted) {
      unawaited(_saveDraftNow());
    }
    _controller.removeListener(_scheduleDraftSave);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_close());
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: '返回',
            onPressed: _close,
            icon: const Icon(Icons.arrow_back),
          ),
          title: const Text('进阶回复'),
          actions: [
            TextButton(
              onPressed: _submitting ? null : _showPreview,
              child: const Text('预览'),
            ),
            TextButton(
              onPressed: _canSend ? _submit : null,
              child: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    )
                  : const Text('发送'),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              children: [
                _ReplyTargetBanner(postNumber: widget.replyToPostNumber),
                const SizedBox(height: 12),
                Expanded(
                  child: AdvancedMarkdownEditor(
                    controller: _controller,
                    focusNode: _focusNode,
                    enabled: !_submitting,
                    uploading: _uploading,
                    onUploadImage: _pickAndUpload,
                    onPreview: _showPreview,
                    onInsertPoll: _insertPoll,
                    showPreviewInToolbar: false,
                    hintText: widget.replyToPostNumber == null
                        ? '写评论'
                        : '回复 #${widget.replyToPostNumber}',
                    expands: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndUpload() async {
    if (_uploading || _submitting) {
      return;
    }
    setState(() => _uploading = true);
    try {
      final picked = await LocalImagePicker.pickImage();
      if (picked == null) {
        return;
      }
      final uploaded = await widget.onUploadImage(picked);
      _images.add(uploaded);
      MarkdownEditing.insertImageMarkdown(_controller, uploaded);
      if (mounted) {
        setState(() {});
        _scheduleDraftSave();
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('图片上传失败：$error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
    }
  }

  Future<void> _insertPoll() async {
    final markdown = await showPollMarkdownDialog(context);
    if (markdown == null || !mounted) {
      return;
    }
    MarkdownEditing.insertBlock(_controller, markdown);
    _focusNode.requestFocus();
    _scheduleDraftSave();
  }

  Future<void> _submit() async {
    final raw = _controller.text.trim();
    final images = _referencedImages();
    if (raw.trim().isEmpty || _uploading || _submitting) {
      return;
    }
    final confirmed = await _confirmSubmit();
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _submitting = true);
    await _saveDraftNow();
    final success = await widget.onSubmit(
      ReplyDraft(
        topicId: widget.detail.id,
        categoryId: widget.detail.categoryId,
        raw: raw,
        replyToPostNumber: widget.replyToPostNumber,
        archetype: widget.detail.archetype,
        images: images,
      ),
    );
    if (!mounted) {
      return;
    }
    if (success) {
      _submitted = true;
      await widget.draftSession.discard();
      if (!mounted) {
        return;
      }
      setState(() => _allowPop = true);
      Navigator.of(context).pop(
        const AdvancedReplyComposerResult(
          raw: '',
          images: [],
          submitted: true,
        ),
      );
      return;
    }
    setState(() => _submitting = false);
  }

  Future<bool?> _confirmSubmit() {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('确认发送回复'),
          content: const Text('是否确认发送？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('发送'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showPreview() async {
    await Navigator.of(context).push<void>(
      shuyoRoute(
        builder: (context) => MarkdownPreviewPage(
          appBarTitle: '预览回复',
          heading: widget.detail.title,
          meta: widget.replyToPostNumber == null
              ? '回复主题'
              : '回复 #${widget.replyToPostNumber}',
          raw: _controller.text.trim(),
          images: _referencedImages(),
        ),
      ),
    );
  }

  Future<void> _close() async {
    if (_allowPop) return;
    await _saveDraftNow();
    if (!mounted) return;
    setState(() => _allowPop = true);
    Navigator.of(context).pop(
      AdvancedReplyComposerResult(
        raw: _controller.text,
        images: _referencedImages(),
        submitted: false,
      ),
    );
  }

  void _scheduleDraftSave() {
    if (_submitting || _submitted) {
      return;
    }
    widget.draftSession.update(
      widget.draftSession.draft.copyWith(
        raw: _controller.text,
        replyToPostNumber: widget.replyToPostNumber,
        clearReplyToPostNumber: widget.replyToPostNumber == null,
        images: _referencedImages(),
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _saveDraftNow() async {
    if (_submitted) {
      return;
    }
    widget.draftSession.update(
      widget.draftSession.draft.copyWith(
        raw: _controller.text,
        replyToPostNumber: widget.replyToPostNumber,
        clearReplyToPostNumber: widget.replyToPostNumber == null,
        images: _referencedImages(),
      ),
    );
    await widget.draftSession.flush();
  }

  List<UploadedImage> _referencedImages() {
    return referencedComposerImages(_controller.text, _images);
  }
}

class _ReplyTargetBanner extends StatelessWidget {
  const _ReplyTargetBanner({required this.postNumber});

  final int? postNumber;

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(
          postNumber == null ? '回复主题' : '回复 #$postNumber',
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
