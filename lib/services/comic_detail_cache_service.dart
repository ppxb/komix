import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/comic.dart';
import '../util/get_path.dart';

class ComicDetailCacheEntry {
  final Comic comic;
  final List<Chapter> chapters;
  final DateTime cachedAt;

  const ComicDetailCacheEntry({
    required this.comic,
    required this.chapters,
    required this.cachedAt,
  });

  bool isFresh(Duration maxAge) {
    return DateTime.now().toUtc().difference(cachedAt.toUtc()) <= maxAge;
  }

  factory ComicDetailCacheEntry.fromJson(Map<String, dynamic> json) {
    final rawChapters = json['chapters'];
    return ComicDetailCacheEntry(
      comic: Comic.fromJson(_asStringKeyMap(json['comic'])),
      chapters: rawChapters is List
          ? rawChapters
                .whereType<Map>()
                .map((item) => Chapter.fromJson(_asStringKeyMap(item)))
                .toList(growable: false)
          : const <Chapter>[],
      cachedAt:
          DateTime.tryParse(json['cached_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'comic': comic.toJson(),
      'chapters': chapters.map((chapter) => chapter.toJson()).toList(),
      'cached_at': cachedAt.toUtc().toIso8601String(),
    };
  }
}

class ComicDetailCacheService {
  static const defaultMaxAge = Duration(hours: 12);
  static final ComicDetailCacheService instance = ComicDetailCacheService._();

  ComicDetailCacheService._();

  Future<ComicDetailCacheEntry?> read(
    String providerId,
    String comicId, {
    Duration? maxAge,
  }) async {
    try {
      final file = File(await _cacheFilePath(providerId, comicId));
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final entry = ComicDetailCacheEntry.fromJson(_asStringKeyMap(decoded));
      return entry.isFresh(maxAge ?? defaultMaxAge) ? entry : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> write({
    required String providerId,
    required String comicId,
    required Comic comic,
    required List<Chapter> chapters,
  }) async {
    final file = File(await _cacheFilePath(providerId, comicId));
    await file.parent.create(recursive: true);
    final entry = ComicDetailCacheEntry(
      comic: comic,
      chapters: List<Chapter>.unmodifiable(chapters),
      cachedAt: DateTime.now().toUtc(),
    );
    await file.writeAsString(jsonEncode(entry.toJson()), flush: true);
  }

  Future<String> _cacheFilePath(String providerId, String comicId) async {
    final cachePath = await getCachePath();
    return p.join(
      cachePath,
      'metadata',
      'comic_detail',
      _safeSegment(providerId),
      '${_safeSegment(comicId)}.json',
    );
  }
}

Map<String, dynamic> _asStringKeyMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return <String, dynamic>{};
}

String _safeSegment(String value) {
  final sanitized = value
      .trim()
      .replaceAll(RegExp(r'[^a-zA-Z0-9_\-.]'), '_');
  return sanitized.isEmpty ? '_' : sanitized;
}
