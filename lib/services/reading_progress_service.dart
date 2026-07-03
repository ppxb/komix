import 'dart:convert';

import '../main.dart';
import '../object_box/model.dart';
import '../object_box/objectbox.g.dart';
import 'comic_link_service.dart';

class ReadingProgress {
  final String providerId;
  final String comicId;
  final String comicTitle;
  final String coverUrl;
  final String chapterId;
  final String chapterTitle;
  final int chapterIndex;
  final int chapterCount;
  final int pageIndex;
  final int pageCount;
  final DateTime updatedAt;

  const ReadingProgress({
    required this.providerId,
    required this.comicId,
    required this.comicTitle,
    required this.coverUrl,
    required this.chapterId,
    required this.chapterTitle,
    required this.chapterIndex,
    required this.chapterCount,
    required this.pageIndex,
    required this.pageCount,
    required this.updatedAt,
  });

  bool get canContinue => pageCount > 0 && (chapterIndex > 0 || pageIndex > 0);

  factory ReadingProgress.fromJson(Map<String, dynamic> json) {
    return ReadingProgress(
      providerId: json['provider_id'] as String? ?? '',
      comicId: json['comic_id'] as String? ?? '',
      comicTitle: json['comic_title'] as String? ?? '',
      coverUrl: json['cover_url'] as String? ?? '',
      chapterId: json['chapter_id'] as String? ?? '',
      chapterTitle: json['chapter_title'] as String? ?? '',
      chapterIndex: (json['chapter_index'] as num?)?.toInt() ?? 0,
      chapterCount: (json['chapter_count'] as num?)?.toInt() ?? 0,
      pageIndex: (json['page_index'] as num?)?.toInt() ?? 0,
      pageCount: (json['page_count'] as num?)?.toInt() ?? 0,
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'provider_id': providerId,
      'comic_id': comicId,
      'comic_title': comicTitle,
      'cover_url': coverUrl,
      'chapter_id': chapterId,
      'chapter_title': chapterTitle,
      'chapter_index': chapterIndex,
      'chapter_count': chapterCount,
      'page_index': pageIndex,
      'page_count': pageCount,
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

class ReadingProgressService {
  ReadingProgressService._();

  static final ReadingProgressService instance = ReadingProgressService._();

  Future<ReadingProgress?> getProgress(
    String providerId,
    String comicId,
  ) async {
    final query = objectbox.unifiedHistoryBox
        .query(UnifiedComicHistory_.uniqueKey.equals(_key(providerId, comicId)))
        .build();
    try {
      final history = query.findFirst();
      if (history == null || history.deleted) return null;
      return _fromHistory(history);
    } finally {
      query.close();
    }
  }

  Future<void> saveProgress(ReadingProgress progress) async {
    final box = objectbox.unifiedHistoryBox;
    final key = _key(progress.providerId, progress.comicId);
    final query = box.query(UnifiedComicHistory_.uniqueKey.equals(key)).build();

    try {
      final existing = query.findFirst();
      final now = progress.updatedAt.toUtc();
      final entity =
          existing ??
          UnifiedComicHistory(
            uniqueKey: key,
            source: progress.providerId,
            comicId: progress.comicId,
            title: progress.comicTitle,
            description: '',
            cover: progress.coverUrl,
            creator: '',
            titleMeta: '',
            metadata: '',
            chapterId: progress.chapterId,
            chapterTitle: progress.chapterTitle,
            chapterOrder: progress.chapterIndex,
            pageIndex: progress.pageIndex,
            createdAt: now,
            lastReadAt: now,
            updatedAt: now,
            deleted: false,
            schemaVersion: 2,
          );

      entity
        ..source = progress.providerId
        ..comicId = progress.comicId
        ..title = progress.comicTitle
        ..cover = progress.coverUrl
        ..chapterId = progress.chapterId
        ..chapterTitle = progress.chapterTitle
        ..chapterOrder = progress.chapterIndex
        ..pageIndex = progress.pageIndex
        ..metadata = jsonEncode({
          'chapter_count': progress.chapterCount,
          'page_count': progress.pageCount,
        })
        ..lastReadAt = now
        ..updatedAt = now
        ..deleted = false;

      box.put(entity);
      ComicLinkService.addComic(key, null, ComicFolderType.history);
    } finally {
      query.close();
    }
  }

  Future<List<ReadingProgress>> getAllProgress() async {
    final items = objectbox.unifiedHistoryBox
        .getAll()
        .where((history) => !history.deleted)
        .map(_fromHistory)
        .where(
          (progress) =>
              progress.providerId.isNotEmpty &&
              progress.comicId.isNotEmpty &&
              progress.pageCount > 0,
        )
        .toList();

    items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return items;
  }

  ReadingProgress _fromHistory(UnifiedComicHistory history) {
    final metadata = _decodeMetadata(history.metadata);
    final pageCount = (metadata['page_count'] as num?)?.toInt() ?? 0;
    final chapterCount = (metadata['chapter_count'] as num?)?.toInt() ?? 0;

    return ReadingProgress(
      providerId: history.source,
      comicId: history.comicId,
      comicTitle: history.title,
      coverUrl: history.cover,
      chapterId: history.chapterId,
      chapterTitle: history.chapterTitle,
      chapterIndex: history.chapterOrder,
      chapterCount: chapterCount,
      pageIndex: history.pageIndex,
      pageCount: pageCount,
      updatedAt: history.lastReadAt.toUtc(),
    );
  }

  Map<String, dynamic> _decodeMetadata(String raw) {
    if (raw.trim().isEmpty) return const <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return const <String, dynamic>{};
  }

  String _key(String providerId, String comicId) {
    return '$providerId:$comicId';
  }
}
