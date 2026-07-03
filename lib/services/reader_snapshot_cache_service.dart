import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/reader_snapshot.dart';
import '../util/get_path.dart';

class ReaderSnapshotCacheEntry {
  final ReaderChapterSnapshot snapshot;
  final DateTime cachedAt;

  const ReaderSnapshotCacheEntry({
    required this.snapshot,
    required this.cachedAt,
  });

  bool isFresh(Duration maxAge) {
    return DateTime.now().toUtc().difference(cachedAt.toUtc()) <= maxAge;
  }

  factory ReaderSnapshotCacheEntry.fromJson(Map<String, dynamic> json) {
    return ReaderSnapshotCacheEntry(
      snapshot: ReaderChapterSnapshot.fromJson(
        _asStringKeyMap(json['snapshot']),
      ),
      cachedAt:
          DateTime.tryParse(json['cached_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'snapshot': snapshot.toJson(),
      'cached_at': cachedAt.toUtc().toIso8601String(),
    };
  }
}

class ReaderSnapshotCacheService {
  static const defaultMaxAge = Duration(hours: 12);
  static final ReaderSnapshotCacheService instance =
      ReaderSnapshotCacheService._();

  ReaderSnapshotCacheService._();

  Future<ReaderChapterSnapshot?> read({
    required String providerId,
    required String comicId,
    required String chapterId,
    Duration? maxAge,
  }) async {
    try {
      final file = File(await _cacheFilePath(providerId, comicId, chapterId));
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final entry = ReaderSnapshotCacheEntry.fromJson(
        _asStringKeyMap(decoded),
      );
      return entry.isFresh(maxAge ?? defaultMaxAge) ? entry.snapshot : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(ReaderChapterSnapshot snapshot) async {
    final file = File(
      await _cacheFilePath(
        snapshot.providerId,
        snapshot.comic.id,
        snapshot.chapter.id,
      ),
    );
    await file.parent.create(recursive: true);
    final entry = ReaderSnapshotCacheEntry(
      snapshot: snapshot,
      cachedAt: DateTime.now().toUtc(),
    );
    await file.writeAsString(jsonEncode(entry.toJson()), flush: true);
  }

  Future<String> _cacheFilePath(
    String providerId,
    String comicId,
    String chapterId,
  ) async {
    final cachePath = await getCachePath();
    return p.join(
      cachePath,
      'metadata',
      'reader_snapshot',
      _safeSegment(providerId),
      _safeSegment(comicId),
      '${_safeSegment(chapterId)}.json',
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
