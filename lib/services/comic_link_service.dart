import 'dart:convert';
import 'dart:io';

import '../main.dart';
import '../object_box/model.dart';
import '../object_box/objectbox.g.dart';
import 'comic_folder_service.dart';

class ComicLinkService {
  const ComicLinkService._();

  static const String _deviceId = 'local';

  static List<ComicLink> listLinks(
    String? folderPath,
    ComicFolderType type, {
    bool sortAscending = false,
  }) {
    final folderSyncId = ComicFolderService.folderSyncIdByPath(
      folderPath,
      type,
    );
    final folderCondition = folderSyncId == null
        ? ComicLink_.folderSyncId.isNull()
        : ComicLink_.folderSyncId.equals(folderSyncId);
    final query = objectbox.comicLinkBox
        .query(
          ComicLink_.typeData
              .equals(type.name)
              .and(ComicLink_.deletedAt.isNull())
              .and(folderCondition),
        )
        .build();
    try {
      final links = query.find();
      links.sort((a, b) {
        return sortAscending
            ? a.createdAt.compareTo(b.createdAt)
            : b.createdAt.compareTo(a.createdAt);
      });
      return links;
    } finally {
      query.close();
    }
  }

  static List<ComicLink> linksOfComic(
    String comicUniqueKey,
    ComicFolderType type,
  ) {
    final query = objectbox.comicLinkBox
        .query(
          ComicLink_.typeData
              .equals(type.name)
              .and(ComicLink_.deletedAt.isNull())
              .and(ComicLink_.comicUniqueKey.equals(comicUniqueKey)),
        )
        .build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  static ComicLink addComic(
    String comicUniqueKey,
    String? folderPath,
    ComicFolderType type,
  ) {
    final folderSyncId = ComicFolderService.folderSyncIdByPath(
      folderPath,
      type,
    );
    final uniqueKey = _uniqueKey(comicUniqueKey, folderSyncId, type);
    final existing = _findLink(uniqueKey);
    final now = _now();
    if (existing != null) {
      if (existing.deletedAt != null) {
        existing
          ..deletedAt = null
          ..createdAt = now
          ..updatedAt = now
          ..versionVectorJson = _bumpVersionVector(existing.versionVectorJson);
        objectbox.comicLinkBox.put(existing);
      }
      return existing;
    }

    final link = ComicLink(
      uniqueKey: uniqueKey,
      comicUniqueKey: comicUniqueKey,
      folderSyncId: folderSyncId,
      typeData: type.name,
      versionVectorJson: _encodeVersionVector({_deviceId: 1}),
      createdAt: now,
      updatedAt: now,
    );
    objectbox.comicLinkBox.put(link);
    return link;
  }

  static void removeComic(
    String comicUniqueKey,
    String? folderPath,
    ComicFolderType type,
  ) {
    final folderSyncId = ComicFolderService.folderSyncIdByPath(
      folderPath,
      type,
    );
    _removeComicBySyncId(comicUniqueKey, folderSyncId, type);
  }

  static void removeComicFromAll(String comicUniqueKey, ComicFolderType type) {
    final query = objectbox.comicLinkBox
        .query(
          ComicLink_.typeData
              .equals(type.name)
              .and(ComicLink_.deletedAt.isNull())
              .and(ComicLink_.comicUniqueKey.equals(comicUniqueKey)),
        )
        .build();
    try {
      final links = query.find();
      for (final link in links) {
        _removeComicBySyncId(link.comicUniqueKey, link.folderSyncId, type);
      }
    } finally {
      query.close();
    }

    if (type == ComicFolderType.favorite) {
      _markFavoriteDeletedIfNoLinks(comicUniqueKey);
    } else if (type == ComicFolderType.download) {
      _deleteDownloadIfNoLinks(comicUniqueKey);
    } else if (type == ComicFolderType.history) {
      _markHistoryDeletedIfNoLinks(comicUniqueKey);
    }
  }

  static void moveComic(
    String comicUniqueKey,
    String? fromPath,
    String? toPath,
    ComicFolderType type,
  ) {
    final normalizedFrom = fromPath ?? kComicFolderRootPath;
    final normalizedTo = toPath ?? kComicFolderRootPath;
    if (normalizedFrom == normalizedTo) return;

    addComic(comicUniqueKey, toPath, type);
    removeComic(comicUniqueKey, fromPath, type);
  }

  static void removeLinksInFolderTree(String folderPath, ComicFolderType type) {
    final folderSyncId = ComicFolderService.folderSyncIdByPath(
      folderPath,
      type,
    );
    if (folderSyncId == null) return;

    final subtreeSyncIds = _collectSubtreeSyncIds(folderSyncId, type);
    final query = objectbox.comicLinkBox
        .query(
          ComicLink_.typeData
              .equals(type.name)
              .and(ComicLink_.deletedAt.isNull()),
        )
        .build();
    try {
      final links = query.find();
      for (final link in links) {
        final linkFolderSyncId = link.folderSyncId;
        if (linkFolderSyncId != null &&
            subtreeSyncIds.contains(linkFolderSyncId)) {
          _removeComicBySyncId(link.comicUniqueKey, linkFolderSyncId, type);
        }
      }
    } finally {
      query.close();
    }
  }

  static void _removeComicBySyncId(
    String comicUniqueKey,
    String? folderSyncId,
    ComicFolderType type,
  ) {
    final uniqueKey = _uniqueKey(comicUniqueKey, folderSyncId, type);
    final link = _findLink(uniqueKey);
    if (link == null || link.deletedAt != null) return;

    if (type == ComicFolderType.download) {
      objectbox.comicLinkBox.remove(link.id);
    } else {
      final now = _now();
      link
        ..deletedAt = now
        ..updatedAt = now
        ..versionVectorJson = _bumpVersionVector(link.versionVectorJson);
      objectbox.comicLinkBox.put(link);
    }

    if (type == ComicFolderType.favorite) {
      _markFavoriteDeletedIfNoLinks(comicUniqueKey);
    } else if (type == ComicFolderType.download) {
      _deleteDownloadIfNoLinks(comicUniqueKey);
    } else if (type == ComicFolderType.history) {
      _markHistoryDeletedIfNoLinks(comicUniqueKey);
    }
  }

  static ComicLink? _findLink(String uniqueKey) {
    final query = objectbox.comicLinkBox
        .query(ComicLink_.uniqueKey.equals(uniqueKey))
        .build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  static void _markFavoriteDeletedIfNoLinks(String comicUniqueKey) {
    if (linksOfComic(comicUniqueKey, ComicFolderType.favorite).isNotEmpty) {
      return;
    }

    final query = objectbox.unifiedFavoriteBox
        .query(UnifiedComicFavorite_.uniqueKey.equals(comicUniqueKey))
        .build();
    try {
      final favorite = query.findFirst();
      if (favorite == null || favorite.deleted) return;
      favorite
        ..deleted = true
        ..updatedAt = DateTime.now().toUtc();
      objectbox.unifiedFavoriteBox.put(favorite);
    } finally {
      query.close();
    }
  }

  static void _deleteDownloadIfNoLinks(String comicUniqueKey) {
    if (linksOfComic(comicUniqueKey, ComicFolderType.download).isNotEmpty) {
      return;
    }

    final query = objectbox.unifiedDownloadBox
        .query(UnifiedComicDownload_.uniqueKey.equals(comicUniqueKey))
        .build();
    try {
      final download = query.findFirst();
      if (download == null) return;
      _deleteDownloadFiles(download.storageRoot);
      objectbox.unifiedDownloadBox.remove(download.id);
    } finally {
      query.close();
    }
  }

  static void _markHistoryDeletedIfNoLinks(String comicUniqueKey) {
    if (linksOfComic(comicUniqueKey, ComicFolderType.history).isNotEmpty) {
      return;
    }

    final query = objectbox.unifiedHistoryBox
        .query(UnifiedComicHistory_.uniqueKey.equals(comicUniqueKey))
        .build();
    try {
      final history = query.findFirst();
      if (history == null || history.deleted) return;
      history
        ..deleted = true
        ..updatedAt = DateTime.now().toUtc();
      objectbox.unifiedHistoryBox.put(history);
    } finally {
      query.close();
    }
  }

  static void _deleteDownloadFiles(String storageRoot) {
    final root = storageRoot.trim();
    if (root.isEmpty) return;
    try {
      final directory = Directory(root);
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    } catch (error, stackTrace) {
      logger.e('Failed to delete download files: $root', error: error);
      logger.d(stackTrace);
    }
  }

  static Set<String> _collectSubtreeSyncIds(
    String rootSyncId,
    ComicFolderType type,
  ) {
    final result = <String>{rootSyncId};
    final queue = <String>[rootSyncId];
    while (queue.isNotEmpty) {
      final parentId = queue.removeLast();
      final query = objectbox.comicFolderBox
          .query(
            ComicFolder_.typeData
                .equals(type.name)
                .and(ComicFolder_.deletedAt.isNull())
                .and(ComicFolder_.parentSyncId.equals(parentId)),
          )
          .build();
      try {
        final children = query.find();
        for (final child in children) {
          if (result.add(child.syncId)) {
            queue.add(child.syncId);
          }
        }
      } finally {
        query.close();
      }
    }
    return result;
  }

  static String _uniqueKey(
    String comicUniqueKey,
    String? folderSyncId,
    ComicFolderType type,
  ) {
    return '$comicUniqueKey|${folderSyncId ?? ''}|${type.name}';
  }

  static Map<String, int> _parseVersionVector(String json) {
    if (json.trim().isEmpty) return <String, int>{};
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      return map.map((key, value) {
        return MapEntry(key, (value as num).toInt());
      });
    } catch (_) {
      return <String, int>{};
    }
  }

  static String _encodeVersionVector(Map<String, int> vector) {
    return jsonEncode(vector);
  }

  static String _bumpVersionVector(String json) {
    final vector = _parseVersionVector(json);
    vector[_deviceId] = (vector[_deviceId] ?? 0) + 1;
    return _encodeVersionVector(vector);
  }

  static int _now() {
    return DateTime.now().toUtc().millisecondsSinceEpoch;
  }
}
