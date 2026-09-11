import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/common.dart';
import '../models/composer.dart';

enum ForumDraftType {
  newTopic,
  topicReply,
  newPrivateMessage,
  privateMessageReply,
}

class ForumComposerDraft {
  const ForumComposerDraft({
    this.id = '',
    this.type,
    this.username = '',
    this.title = '',
    this.raw = '',
    this.categoryId,
    this.topicId,
    this.topicTitle = '',
    this.recipient = '',
    this.replyToPostNumber,
    this.images = const [],
    this.revision = 0,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final ForumDraftType? type;
  final String username;
  final String title;
  final String raw;
  final int? categoryId;
  final int? topicId;
  final String topicTitle;
  final String recipient;
  final int? replyToPostNumber;
  final List<UploadedImage> images;
  final int revision;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get hasContent =>
      title.trim().isNotEmpty || raw.trim().isNotEmpty || images.isNotEmpty;

  ForumComposerDraft copyWith({
    String? id,
    ForumDraftType? type,
    String? username,
    String? title,
    String? raw,
    int? categoryId,
    bool clearCategoryId = false,
    int? topicId,
    String? topicTitle,
    String? recipient,
    int? replyToPostNumber,
    bool clearReplyToPostNumber = false,
    List<UploadedImage>? images,
    int? revision,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ForumComposerDraft(
      id: id ?? this.id,
      type: type ?? this.type,
      username: username ?? this.username,
      title: title ?? this.title,
      raw: raw ?? this.raw,
      categoryId: clearCategoryId ? null : categoryId ?? this.categoryId,
      topicId: topicId ?? this.topicId,
      topicTitle: topicTitle ?? this.topicTitle,
      recipient: recipient ?? this.recipient,
      replyToPostNumber: clearReplyToPostNumber
          ? null
          : replyToPostNumber ?? this.replyToPostNumber,
      images: images ?? this.images,
      revision: revision ?? this.revision,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  JsonMap toJson({DateTime? updatedAt}) {
    final now = DateTime.now();
    return {
      'schema_version': 2,
      'id': id,
      'type': type?.name,
      'username': username,
      'title': title,
      'raw': raw,
      'category_id': categoryId,
      'topic_id': topicId,
      'topic_title': topicTitle,
      'recipient': recipient,
      'reply_to_post_number': replyToPostNumber,
      'revision': revision,
      'created_at': (createdAt ?? now).toIso8601String(),
      'updated_at': (updatedAt ?? this.updatedAt ?? now).toIso8601String(),
      'images': images.map(_imageToJson).toList(),
    };
  }

  factory ForumComposerDraft.fromJson(JsonMap json) {
    final imagesJson = json['images'];
    return ForumComposerDraft(
      id: stringValue(json['id']),
      type: _draftType(json['type']),
      username: stringValue(json['username']),
      title: stringValue(json['title']),
      raw: stringValue(json['raw']),
      categoryId: _nullableInt(json['category_id']),
      topicId: _nullableInt(json['topic_id']),
      topicTitle: stringValue(json['topic_title']),
      recipient: stringValue(json['recipient']),
      replyToPostNumber: _nullableInt(json['reply_to_post_number']),
      revision: intValue(json['revision']),
      createdAt: dateValue(json['created_at']),
      updatedAt: dateValue(json['updated_at']),
      images: imagesJson is List
          ? imagesJson
              .whereType<JsonMap>()
              .map(_imageFromJson)
              .whereType<UploadedImage>()
              .toList(growable: false)
          : const [],
    );
  }

  static ForumDraftType? _draftType(Object? value) {
    final name = stringValue(value);
    for (final type in ForumDraftType.values) {
      if (type.name == name) return type;
    }
    return null;
  }

  static JsonMap _imageToJson(UploadedImage image) => {
        'url': image.url,
        'short_url': image.shortUrl,
        'filename': image.filename,
        'width': image.width,
        'height': image.height,
        'thumbnail_width': image.thumbnailWidth,
        'thumbnail_height': image.thumbnailHeight,
      };

  static UploadedImage? _imageFromJson(JsonMap json) {
    final url = stringValue(json['url']);
    final shortUrl = stringValue(json['short_url']);
    if (url.isEmpty && shortUrl.isEmpty) return null;
    return UploadedImage(
      url: url,
      shortUrl: shortUrl.isEmpty ? url : shortUrl,
      filename: stringValue(json['filename'], 'image.jpg'),
      width: intValue(json['width']),
      height: intValue(json['height']),
      thumbnailWidth: intValue(json['thumbnail_width']),
      thumbnailHeight: intValue(json['thumbnail_height']),
    );
  }

  static int? _nullableInt(Object? value) {
    if (value == null) return null;
    final parsed = intValue(value);
    return parsed == 0 ? null : parsed;
  }
}

class ForumDraftStore {
  const ForumDraftStore._();

  static const _v1Prefix = 'forum.composerDraft.v1';
  static const _v2Prefix = 'forum.composerDraft.v2';
  static const expiringMaxAge = Duration(days: 7);
  static const newTopicMaxCount = 10;
  static const otherMaxCount = 50;
  static int _idSequence = 0;
  static Future<void> _writeQueue = Future<void>.value();

  static String createId() {
    _idSequence++;
    return '${DateTime.now().microsecondsSinceEpoch}-$_idSequence';
  }

  static String newTopicKey(String username) =>
      '$_v1Prefix.topic.new.${_part(username)}';

  static String newPrivateMessageKey(String username, String recipient) =>
      '$_v1Prefix.private.new.${_part(username)}.${_part(recipient)}';

  static String topicReplyKey({
    required String username,
    required int topicId,
    required int? replyToPostNumber,
  }) =>
      '$_v1Prefix.topic.reply.${_part(username)}.$topicId.'
      '${replyToPostNumber ?? 'root'}';

  static String privateMessageReplyKey({
    required String username,
    required int topicId,
  }) =>
      '$_v1Prefix.private.reply.${_part(username)}.$topicId';

  static Future<List<ForumComposerDraft>> list(
    String username, {
    ForumDraftType? type,
    int? topicId,
    int? replyToPostNumber,
    bool matchRootReply = false,
    String? recipient,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateV1(prefs, username);
    await _cleanup(prefs);
    final normalizedUser = username.trim().toLowerCase();
    final drafts = <ForumComposerDraft>[];
    for (final key in prefs.getKeys()) {
      if (!key.startsWith('$_v2Prefix.')) continue;
      final draft = _parseDraft(prefs.getString(key));
      if (draft == null ||
          draft.username.trim().toLowerCase() != normalizedUser ||
          (type != null && draft.type != type) ||
          (topicId != null && draft.topicId != topicId) ||
          ((matchRootReply || replyToPostNumber != null) &&
              draft.replyToPostNumber != replyToPostNumber) ||
          (recipient != null &&
              draft.recipient.trim().toLowerCase() !=
                  recipient.trim().toLowerCase())) {
        continue;
      }
      drafts.add(draft);
    }
    drafts.sort(_newestFirst);
    return drafts;
  }

  static Future<ForumComposerDraft?> latest(
    String username, {
    required ForumDraftType type,
    int? topicId,
    int? replyToPostNumber,
    bool matchRootReply = false,
    String? recipient,
  }) async {
    final drafts = await list(
      username,
      type: type,
      topicId: topicId,
      replyToPostNumber: replyToPostNumber,
      matchRootReply: matchRootReply,
      recipient: recipient,
    );
    return drafts.isEmpty ? null : drafts.first;
  }

  static Future<ForumComposerDraft?> loadById(
    String username,
    String id,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateV1(prefs, username);
    final draft = _parseDraft(prefs.getString(_v2Key(username, id)));
    if (draft == null || !draft.hasContent || _isExpired(draft)) return null;
    return draft;
  }

  static Future<void> saveDraft(ForumComposerDraft draft) {
    final normalized = draft.copyWith(
      id: draft.id.isEmpty ? createId() : draft.id,
      revision: draft.revision <= 0 ? 1 : draft.revision,
      createdAt: draft.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );
    return _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      final key = _v2Key(normalized.username, normalized.id);
      if (!normalized.hasContent) {
        await prefs.remove(key);
        return;
      }
      final existing = _parseDraft(prefs.getString(key));
      if (existing != null && existing.revision > normalized.revision) return;
      await prefs.setString(key, jsonEncode(normalized.toJson()));
      await _cleanup(prefs);
    });
  }

  static Future<void> removeDraft(String username, String id) =>
      _enqueue(() async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_v2Key(username, id));
      });

  // v1 API is kept so older installs and existing tests remain readable.
  static Future<ForumComposerDraft?> load(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(key);
    final draft = _parseDraft(value);
    if (draft == null || !draft.hasContent || _legacyExpired(draft)) {
      if (value != null) await prefs.remove(key);
      return null;
    }
    return draft;
  }

  static Future<void> save(String key, ForumComposerDraft draft) async {
    final prefs = await SharedPreferences.getInstance();
    if (!draft.hasContent) {
      await prefs.remove(key);
      return;
    }
    await prefs.setString(key, jsonEncode(draft.toJson()));
  }

  static Future<void> remove(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  static Future<void> cleanup() async {
    final prefs = await SharedPreferences.getInstance();
    await _cleanup(prefs);
  }

  static Future<void> _migrateV1(
    SharedPreferences prefs,
    String username,
  ) async {
    final normalized = username.trim().toLowerCase();
    final keys = prefs.getKeys().where((key) => key.startsWith(_v1Prefix));
    for (final key in keys.toList()) {
      final identity = _legacyIdentity(key);
      if (identity == null || identity.username != normalized) continue;
      final old = _parseDraft(prefs.getString(key));
      if (old == null || !old.hasContent) {
        await prefs.remove(key);
        continue;
      }
      final migrated = old.copyWith(
        id: createId(),
        type: identity.type,
        username: username,
        topicId: identity.topicId,
        recipient: identity.recipient,
        replyToPostNumber: identity.replyToPostNumber,
        clearReplyToPostNumber: identity.replyToPostNumber == null,
        revision: 1,
        createdAt: old.updatedAt ?? DateTime.now(),
      );
      await prefs.setString(
        _v2Key(username, migrated.id),
        jsonEncode(migrated.toJson()),
      );
      await prefs.remove(key);
    }
  }

  static _LegacyIdentity? _legacyIdentity(String key) {
    final suffix = key.substring(_v1Prefix.length + 1);
    final parts = suffix.split('.');
    if (parts.length >= 3 && parts[0] == 'topic' && parts[1] == 'new') {
      return _LegacyIdentity(
        username: Uri.decodeComponent(parts.sublist(2).join('.')),
        type: ForumDraftType.newTopic,
      );
    }
    if (parts.length >= 5 && parts[0] == 'topic' && parts[1] == 'reply') {
      return _LegacyIdentity(
        username: Uri.decodeComponent(parts[2]),
        type: ForumDraftType.topicReply,
        topicId: int.tryParse(parts[3]),
        replyToPostNumber: parts[4] == 'root' ? null : int.tryParse(parts[4]),
      );
    }
    if (parts.length >= 4 && parts[0] == 'private' && parts[1] == 'new') {
      return _LegacyIdentity(
        username: Uri.decodeComponent(parts[2]),
        type: ForumDraftType.newPrivateMessage,
        recipient: Uri.decodeComponent(parts.sublist(3).join('.')),
      );
    }
    if (parts.length >= 4 && parts[0] == 'private' && parts[1] == 'reply') {
      return _LegacyIdentity(
        username: Uri.decodeComponent(parts[2]),
        type: ForumDraftType.privateMessageReply,
        topicId: int.tryParse(parts[3]),
      );
    }
    return null;
  }

  static Future<void> _cleanup(SharedPreferences prefs) async {
    final legacyRecords = <_LegacyRecord>[];
    for (final key in prefs.getKeys().toList()) {
      if (!key.startsWith(_v1Prefix)) continue;
      final draft = _parseDraft(prefs.getString(key));
      if (draft == null || !draft.hasContent || _legacyExpired(draft)) {
        await prefs.remove(key);
        continue;
      }
      legacyRecords.add(_LegacyRecord(key: key, draft: draft));
    }
    legacyRecords.sort(
      (a, b) => _newestFirst(a.draft, b.draft),
    );
    for (final record in legacyRecords.skip(otherMaxCount)) {
      await prefs.remove(record.key);
    }

    final byUser = <String, List<_DraftRecord>>{};
    for (final key in prefs.getKeys().toList()) {
      if (!key.startsWith('$_v2Prefix.')) continue;
      final draft = _parseDraft(prefs.getString(key));
      if (draft == null || !draft.hasContent || _isExpired(draft)) {
        await prefs.remove(key);
        continue;
      }
      byUser.putIfAbsent(draft.username.toLowerCase(), () => []).add(
            _DraftRecord(key: key, draft: draft),
          );
    }
    for (final records in byUser.values) {
      final topics = records
          .where((record) => record.draft.type == ForumDraftType.newTopic)
          .toList()
        ..sort(_newestRecordFirst);
      final others = records
          .where((record) => record.draft.type != ForumDraftType.newTopic)
          .toList()
        ..sort(_newestRecordFirst);
      for (final record in topics.skip(newTopicMaxCount)) {
        await prefs.remove(record.key);
      }
      for (final record in others.skip(otherMaxCount)) {
        await prefs.remove(record.key);
      }
    }
  }

  static bool _isExpired(ForumComposerDraft draft) {
    if (draft.type == ForumDraftType.newTopic) return false;
    final updatedAt = draft.updatedAt;
    return updatedAt == null ||
        DateTime.now().difference(updatedAt) > expiringMaxAge;
  }

  static bool _legacyExpired(ForumComposerDraft draft) {
    final updatedAt = draft.updatedAt;
    return updatedAt == null ||
        DateTime.now().difference(updatedAt) > const Duration(days: 15);
  }

  static int _newestFirst(ForumComposerDraft a, ForumComposerDraft b) =>
      (b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
        a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      );

  static int _newestRecordFirst(_DraftRecord a, _DraftRecord b) =>
      _newestFirst(a.draft, b.draft);

  static ForumComposerDraft? _parseDraft(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      final json = jsonDecode(value);
      return json is JsonMap ? ForumComposerDraft.fromJson(json) : null;
    } on Object {
      return null;
    }
  }

  static String _v2Key(String username, String id) =>
      '$_v2Prefix.${_part(username)}.${_part(id)}';

  static String _part(String value) =>
      Uri.encodeComponent(value.trim().toLowerCase());

  static Future<void> _enqueue(Future<void> Function() action) {
    final completer = Completer<void>();
    _writeQueue = _writeQueue.then((_) => action()).then(
      (_) => completer.complete(),
      onError: (Object error, StackTrace stackTrace) {
        completer.completeError(error, stackTrace);
      },
    );
    return completer.future;
  }
}

class ForumDraftSession with WidgetsBindingObserver {
  ForumDraftSession(this._draft) {
    WidgetsBinding.instance.addObserver(this);
  }

  ForumComposerDraft _draft;
  Timer? _timer;
  Future<void> _pending = Future<void>.value();
  bool _disposed = false;

  ForumComposerDraft get draft => _draft;
  void update(ForumComposerDraft next) {
    if (_disposed) return;
    _draft = next.copyWith(
      id: _draft.id,
      type: _draft.type,
      username: _draft.username,
      revision: _draft.revision + 1,
      createdAt: _draft.createdAt,
    );
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 500), flush);
  }

  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    final snapshot = _draft;
    _pending = _pending.then((_) => ForumDraftStore.saveDraft(snapshot)).then(
          (_) {},
          onError: (Object _) {},
        );
    return _pending;
  }

  Future<void> discard() =>
      ForumDraftStore.removeDraft(_draft.username, _draft.id);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(flush());
    }
  }

  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _disposed = true;
  }
}

class _LegacyIdentity {
  const _LegacyIdentity({
    required this.username,
    required this.type,
    this.topicId,
    this.recipient = '',
    this.replyToPostNumber,
  });

  final String username;
  final ForumDraftType type;
  final int? topicId;
  final String recipient;
  final int? replyToPostNumber;
}

class _DraftRecord {
  const _DraftRecord({required this.key, required this.draft});

  final String key;
  final ForumComposerDraft draft;
}

class _LegacyRecord {
  const _LegacyRecord({required this.key, required this.draft});

  final String key;
  final ForumComposerDraft draft;
}
