import 'dart:convert';

import '../main.dart';
import '../object_box/model.dart';
import '../object_box/objectbox.g.dart';

const String kComicFolderRootPath = '';

class ComicFolderService {
  const ComicFolderService._();

  static const String _deviceId = 'local';
  static int _syncCounter = 0;

  static String get _newSyncId {
    _syncCounter += 1;
    return 'local-${DateTime.now().microsecondsSinceEpoch}-$_syncCounter';
  }

  static String? folderSyncIdByPath(String? path, ComicFolderType type) {
    if (path == null || path.isEmpty) return null;
    final query = objectbox.comicFolderBox
        .query(
          ComicFolder_.uniqueKey
              .equals(_uniqueKey(path, type))
              .and(ComicFolder_.deletedAt.isNull()),
        )
        .build();
    try {
      return query.findFirst()?.syncId;
    } finally {
      query.close();
    }
  }

  static String folderPath(
    ComicFolder folder, {
    Map<String, ComicFolder>? syncIdMap,
  }) {
    final bySyncId = syncIdMap ?? _buildSyncIdMap(folder.type);
    final parts = <String>[];
    final visited = <String>{};
    ComicFolder? current = folder;
    while (current != null) {
      if (current.syncId.isNotEmpty && !visited.add(current.syncId)) break;
      parts.add(current.name);
      final parentId = current.parentSyncId;
      if (parentId == null || parentId.isEmpty) break;
      current = bySyncId[parentId];
    }
    return '/${parts.reversed.join('/')}';
  }

  static List<ComicFolder> listChildFolders(
    String parentPath,
    ComicFolderType type, {
    bool sortAscending = false,
  }) {
    final parentSyncId = _parentSyncIdByPath(parentPath, type);
    final condition = parentSyncId == null
        ? ComicFolder_.parentSyncId.isNull()
        : ComicFolder_.parentSyncId.equals(parentSyncId);
    final query = objectbox.comicFolderBox
        .query(
          ComicFolder_.typeData
              .equals(type.name)
              .and(ComicFolder_.deletedAt.isNull())
              .and(condition),
        )
        .build();
    try {
      final folders = query.find();
      folders.sort((a, b) {
        return sortAscending
            ? a.createdAt.compareTo(b.createdAt)
            : b.createdAt.compareTo(a.createdAt);
      });
      return folders;
    } finally {
      query.close();
    }
  }

  static List<ComicFolder> listAllFolders(
    ComicFolderType type, {
    bool sortAscending = false,
  }) {
    final query = objectbox.comicFolderBox
        .query(
          ComicFolder_.typeData
              .equals(type.name)
              .and(ComicFolder_.deletedAt.isNull()),
        )
        .build();
    try {
      final folders = query.find();
      folders.sort((a, b) {
        return sortAscending
            ? a.createdAt.compareTo(b.createdAt)
            : b.createdAt.compareTo(a.createdAt);
      });
      return folders;
    } finally {
      query.close();
    }
  }

  static ComicFolder createFolder(
    String parentPath,
    String name,
    ComicFolderType type,
  ) {
    final safeName = name.trim();
    if (safeName.isEmpty) {
      throw ArgumentError('folder name is empty');
    }
    if (safeName.contains('/')) {
      throw ArgumentError('folder name cannot contain /');
    }

    final now = _now();
    final newPath = _folderPath(parentPath, safeName);
    final uniqueKey = _uniqueKey(newPath, type);
    final parentSyncId = _parentSyncIdByPath(parentPath, type);
    final existing = _findFolderByUniqueKey(uniqueKey);
    if (existing != null) {
      if (existing.deletedAt == null) {
        throw StateError('folder already exists');
      }
      existing
        ..name = safeName
        ..parentSyncId = parentSyncId
        ..deletedAt = null
        ..createdAt = now
        ..updatedAt = now
        ..versionVectorJson = _bumpVersionVector(existing.versionVectorJson);
      objectbox.comicFolderBox.put(existing);
      return existing;
    }

    final folder = ComicFolder(
      syncId: _newSyncId,
      parentSyncId: parentSyncId,
      uniqueKey: uniqueKey,
      name: safeName,
      typeData: type.name,
      versionVectorJson: _encodeVersionVector({_deviceId: 1}),
      createdAt: now,
      updatedAt: now,
    );
    objectbox.comicFolderBox.put(folder);
    return folder;
  }

  static void renameFolder(String path, String newName, ComicFolderType type) {
    final safeName = newName.trim();
    if (path == kComicFolderRootPath || safeName.isEmpty) return;
    if (safeName.contains('/')) {
      throw ArgumentError('folder name cannot contain /');
    }

    final folder = _findFolderByUniqueKey(_uniqueKey(path, type));
    if (folder == null || folder.deletedAt != null) return;

    final parentPath = _parentPath(path);
    final newPath = _folderPath(parentPath, safeName);
    final newUniqueKey = _uniqueKey(newPath, type);
    final duplicated = _findFolderByUniqueKey(newUniqueKey);
    if (duplicated != null && duplicated.id != folder.id) {
      if (duplicated.deletedAt == null) {
        throw StateError('folder already exists');
      }
      objectbox.comicFolderBox.remove(duplicated.id);
    }

    folder
      ..name = safeName
      ..uniqueKey = newUniqueKey
      ..updatedAt = _now()
      ..versionVectorJson = _bumpVersionVector(folder.versionVectorJson);
    objectbox.comicFolderBox.put(folder);
  }

  static void deleteFolder(String path, ComicFolderType type) {
    if (path == kComicFolderRootPath) return;
    final folder = _findFolderByUniqueKey(_uniqueKey(path, type));
    if (folder == null || folder.deletedAt != null) return;

    final now = _now();
    final subtreeSyncIds = _collectSubtreeSyncIds(folder.syncId, type);
    final query = objectbox.comicFolderBox
        .query(ComicFolder_.syncId.oneOf(subtreeSyncIds.toList()))
        .build();
    try {
      final folders = query.find();
      for (final item in folders) {
        if (item.deletedAt != null) continue;
        item
          ..deletedAt = now
          ..updatedAt = now
          ..versionVectorJson = _bumpVersionVector(item.versionVectorJson);
      }
      if (folders.isNotEmpty) {
        objectbox.comicFolderBox.putMany(folders);
      }
    } finally {
      query.close();
    }
  }

  static Map<String, ComicFolder> _buildSyncIdMap(ComicFolderType type) {
    return {for (final folder in listAllFolders(type)) folder.syncId: folder};
  }

  static String _folderPath(String parentPath, String name) {
    if (parentPath == kComicFolderRootPath) return '/$name';
    return '$parentPath/$name';
  }

  static String _uniqueKey(String path, ComicFolderType type) {
    final parentPath = _parentPath(path);
    final parentSyncId = parentPath == kComicFolderRootPath
        ? ''
        : (folderSyncIdByPath(parentPath, type) ?? '');
    final name = path == kComicFolderRootPath ? '' : path.split('/').last;
    return '$parentSyncId|$name|${type.name}';
  }

  static String? _parentSyncIdByPath(String? path, ComicFolderType type) {
    if (path == null || path.isEmpty) return null;
    return folderSyncIdByPath(path, type);
  }

  static String _parentPath(String path) {
    if (path == kComicFolderRootPath) return kComicFolderRootPath;
    final trimmed = path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    final index = trimmed.lastIndexOf('/');
    if (index <= 0) return kComicFolderRootPath;
    return trimmed.substring(0, index);
  }

  static ComicFolder? _findFolderByUniqueKey(String uniqueKey) {
    final query = objectbox.comicFolderBox
        .query(ComicFolder_.uniqueKey.equals(uniqueKey))
        .build();
    try {
      return query.findFirst();
    } finally {
      query.close();
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
