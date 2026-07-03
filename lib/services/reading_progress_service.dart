import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ReadingProgress {
  final String providerId;
  final String comicId;
  final String comicTitle;
  final String coverUrl;
  final String chapterId;
  final String chapterTitle;
  final int chapterIndex;
  final int chapterCount;
  final double scrollProgress;
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
    required this.scrollProgress,
    required this.updatedAt,
  });

  bool get canContinue => chapterIndex > 0 || scrollProgress > 0.01;

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
      scrollProgress: (json['scroll_progress'] as num?)?.toDouble() ?? 0,
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
      'scroll_progress': scrollProgress.clamp(0.0, 1.0),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

class ReadingProgressService {
  ReadingProgressService._();

  static final ReadingProgressService instance = ReadingProgressService._();

  static const _keyPrefix = 'reading_progress:v1:';

  Future<ReadingProgress?> getProgress(String providerId, String comicId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(providerId, comicId));
    if (raw == null || raw.isEmpty) return null;

    try {
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      return ReadingProgress.fromJson(Map<String, dynamic>.from(json));
    } catch (_) {
      return null;
    }
  }

  Future<void> saveProgress(ReadingProgress progress) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(progress.providerId, progress.comicId),
      jsonEncode(progress.toJson()),
    );
  }

  String _key(String providerId, String comicId) {
    return '$_keyPrefix${Uri.encodeComponent(providerId)}:${Uri.encodeComponent(comicId)}';
  }
}
