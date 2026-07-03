import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../main.dart';
import '../models/comic.dart';
import '../object_box/model.dart';
import '../object_box/objectbox.g.dart';

class FavoriteComic {
  final String uniqueKey;
  final String providerId;
  final String comicId;
  final String title;
  final String description;
  final String coverUrl;
  final String creator;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;

  const FavoriteComic({
    required this.uniqueKey,
    required this.providerId,
    required this.comicId,
    required this.title,
    required this.description,
    required this.coverUrl,
    required this.creator,
    required this.tags,
    required this.createdAt,
    required this.updatedAt,
  });

  Comic toComic() {
    return Comic(
      id: comicId,
      title: title,
      author: creator.isEmpty ? const <String>[] : <String>[creator],
      coverUrl: coverUrl,
      description: description,
      tags: tags,
      likes: 0,
      views: 0,
      updatedAt: updatedAt.toIso8601String(),
    );
  }
}

class FavoriteService {
  FavoriteService._();

  static final FavoriteService instance = FavoriteService._();

  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  Future<bool> isFavorite(String providerId, String comicId) async {
    final favorite = _findFavorite(_key(providerId, comicId));
    return favorite != null && !favorite.deleted;
  }

  Future<bool> toggleFavorite({
    required String providerId,
    required Comic comic,
  }) async {
    final key = _key(providerId, comic.id);
    final existing = _findFavorite(key);
    final now = DateTime.now().toUtc();

    if (existing != null && !existing.deleted) {
      existing
        ..deleted = true
        ..updatedAt = now;
      objectbox.unifiedFavoriteBox.put(existing);
      _notifyChanged();
      return false;
    }

    final creator = comic.author.join(' / ');
    final entity = UnifiedComicFavorite(
      id: existing?.id ?? 0,
      uniqueKey: key,
      source: providerId,
      comicId: comic.id,
      title: comic.title,
      description: comic.description,
      cover: jsonEncode(<String, dynamic>{
        'url': comic.coverUrl,
        'path': _coverPath(comic),
      }),
      creator: jsonEncode(<String, dynamic>{'name': creator}),
      titleMeta: jsonEncode(<Map<String, dynamic>>[
        if (creator.isNotEmpty) <String, dynamic>{
          'name': '作者',
          'value': creator,
        },
      ]),
      metadata: jsonEncode(<String, dynamic>{
        'tags': comic.tags,
        'updated_at': comic.updatedAt,
        'likes': comic.likes,
        'views': comic.views,
      }),
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      deleted: false,
      schemaVersion: 2,
    );

    objectbox.unifiedFavoriteBox.put(entity);
    _notifyChanged();
    return true;
  }

  Future<void> removeFavorite({
    required String providerId,
    required String comicId,
  }) async {
    final favorite = _findFavorite(_key(providerId, comicId));
    if (favorite == null || favorite.deleted) return;

    favorite
      ..deleted = true
      ..updatedAt = DateTime.now().toUtc();
    objectbox.unifiedFavoriteBox.put(favorite);
    _notifyChanged();
  }

  Future<List<FavoriteComic>> getAllFavorites() async {
    final items = objectbox.unifiedFavoriteBox
        .getAll()
        .where((favorite) => !favorite.deleted)
        .map(_fromEntity)
        .where(
          (favorite) =>
              favorite.providerId.isNotEmpty &&
              favorite.comicId.isNotEmpty &&
              favorite.title.isNotEmpty,
        )
        .toList();

    items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return items;
  }

  UnifiedComicFavorite? _findFavorite(String key) {
    final query = objectbox.unifiedFavoriteBox
        .query(UnifiedComicFavorite_.uniqueKey.equals(key))
        .build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  FavoriteComic _fromEntity(UnifiedComicFavorite favorite) {
    final metadata = _decodeMap(favorite.metadata);
    final creator = _decodeCreator(favorite.creator);
    final tags = _decodeTags(metadata['tags']);

    return FavoriteComic(
      uniqueKey: favorite.uniqueKey,
      providerId: favorite.source,
      comicId: favorite.comicId,
      title: favorite.title,
      description: favorite.description,
      coverUrl: _decodeCoverUrl(favorite.cover),
      creator: creator,
      tags: tags,
      createdAt: favorite.createdAt.toUtc(),
      updatedAt: favorite.updatedAt.toUtc(),
    );
  }

  void _notifyChanged() {
    revision.value += 1;
  }

  String _key(String providerId, String comicId) {
    return '${providerId.trim()}:${comicId.trim()}';
  }

  String _coverPath(Comic comic) {
    final uri = Uri.tryParse(comic.coverUrl);
    final segments = uri?.pathSegments;
    if (segments != null && segments.isNotEmpty) {
      final name = segments.last.trim();
      if (name.isNotEmpty) return name;
    }
    return '${_sanitizeFileName(comic.id)}.jpg';
  }

  String _sanitizeFileName(String input) {
    final sanitized = input
        .trim()
        .replaceAll(RegExp(r'[^a-zA-Z0-9_\-.]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return sanitized.isEmpty ? 'cover' : sanitized;
  }

  String _decodeCoverUrl(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return '';
    final decoded = _decodeMap(text);
    final url = decoded['url']?.toString().trim() ?? '';
    return url.isNotEmpty ? url : text;
  }

  String _decodeCreator(String raw) {
    final decoded = _decodeMap(raw);
    final name = decoded['name']?.toString().trim();
    if (name != null && name.isNotEmpty) return name;
    return raw.trim();
  }

  List<String> _decodeTags(dynamic raw) {
    if (raw is List) {
      return raw
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    if (raw is String && raw.trim().isNotEmpty) {
      return <String>[raw.trim()];
    }
    return const <String>[];
  }

  Map<String, dynamic> _decodeMap(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return const <String, dynamic>{};
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return const <String, dynamic>{};
  }
}
