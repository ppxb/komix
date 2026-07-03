import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../main.dart';
import '../models/comic.dart';
import '../object_box/model.dart';
import '../object_box/objectbox.g.dart';
import '../providers/provider_registry.dart';
import '../type/enum.dart';
import '../util/foreground_task/data/download_task_json.dart';
import '../util/get_path.dart';
import 'provider_image_cache.dart';

class DownloadTaskView {
  final String providerId;
  final String comicId;
  final String comicName;
  final String status;
  final bool isCompleted;
  final bool isDownloading;

  const DownloadTaskView({
    required this.providerId,
    required this.comicId,
    required this.comicName,
    required this.status,
    required this.isCompleted,
    required this.isDownloading,
  });
}

class DownloadService {
  DownloadService._();

  static final DownloadService instance = DownloadService._();

  final ValueNotifier<int> revision = ValueNotifier<int>(0);
  bool _isProcessing = false;

  void startProcessing() {
    unawaited(_processQueue());
  }

  Future<bool> enqueueComic({
    required String providerId,
    required Comic comic,
    required List<Chapter> chapters,
  }) async {
    if (chapters.isEmpty) {
      throw StateError('暂无可下载章节');
    }

    final existing = _findOpenTask(providerId: providerId, comicId: comic.id);
    if (existing != null) {
      return false;
    }

    final task = DownloadTask()
      ..comicId = _key(providerId, comic.id)
      ..comicName = comic.title
      ..isCompleted = false
      ..isDownloading = false
      ..status = '等待下载'
      ..taskInfo = DownloadTaskJson(
        from: providerId,
        comicId: comic.id,
        comicName: comic.title,
        chapterRefs: chapters
            .map(
              (chapter) => DownloadChapterTaskRef(
                chapterId: chapter.id,
                requestId: chapter.id,
                storageChapterId: chapter.id,
                logicalKey: chapter.id,
                title: chapter.name,
                order: chapter.order,
              ),
            )
            .toList(growable: false),
      );

    objectbox.downloadTaskBox.put(task);
    _notifyChanged();
    unawaited(_processQueue());
    return true;
  }

  Future<List<DownloadTaskView>> getTasks() async {
    final tasks = objectbox.downloadTaskBox.getAll();
    tasks.sort((a, b) => b.id.compareTo(a.id));
    return tasks.map(_toView).toList(growable: false);
  }

  DownloadTask? _findOpenTask({
    required String providerId,
    required String comicId,
  }) {
    final taskKey = _key(providerId, comicId);
    final query = objectbox.downloadTaskBox
        .query(
          DownloadTask_.comicId
              .equals(taskKey)
              .and(DownloadTask_.isCompleted.equals(false)),
        )
        .build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  Future<void> _processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;
    try {
      while (true) {
        final task = _nextPendingTask();
        if (task == null) return;
        await _processTask(task);
      }
    } finally {
      _isProcessing = false;
      _notifyChanged();
    }
  }

  DownloadTask? _nextPendingTask() {
    final query = objectbox.downloadTaskBox
        .query(
          DownloadTask_.isCompleted
              .equals(false)
              .and(DownloadTask_.isDownloading.equals(false)),
        )
        .order(DownloadTask_.id)
        .build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  Future<void> _processTask(DownloadTask dbTask) async {
    final task = dbTask.taskInfo;
    if (task == null) {
      dbTask
        ..isCompleted = true
        ..isDownloading = false
        ..status = '下载任务数据无效';
      objectbox.downloadTaskBox.put(dbTask);
      _notifyChanged();
      return;
    }

    final provider = ProviderRegistry().getProvider(task.from);
    if (provider == null) {
      dbTask
        ..isCompleted = true
        ..isDownloading = false
        ..status = '未找到数据源: ${task.from}';
      objectbox.downloadTaskBox.put(dbTask);
      _notifyChanged();
      return;
    }

    final chapters = task.chapterRefs
        .map(
          (ref) => Chapter(
            id: ref.chapterId,
            comicId: task.comicId,
            name: ref.title.isEmpty ? ref.chapterId : ref.title,
            order: ref.order,
          ),
        )
        .toList(growable: false);
    final comic = await _loadComic(providerId: task.from, comicId: task.comicId);

    dbTask
      ..isDownloading = true
      ..status = '开始下载'
      ..comicName = comic.title.isEmpty ? task.comicName : comic.title;
    objectbox.downloadTaskBox.put(dbTask);
    _notifyChanged();

    var downloadedPages = 0;

    try {
      for (
        var chapterIndex = 0;
        chapterIndex < chapters.length;
        chapterIndex++
      ) {
        final chapter = chapters[chapterIndex];
        dbTask.status = '获取章节 ${chapterIndex + 1}/${chapters.length}';
        objectbox.downloadTaskBox.put(dbTask);
        _notifyChanged();

        final snapshot = await provider.getReaderChapterSnapshot(
          comic: comic,
          chapter: chapter,
          chapters: chapters,
        );

        for (
          var pageIndex = 0;
          pageIndex < snapshot.pages.length;
          pageIndex++
        ) {
          final page = snapshot.pages[pageIndex];
          dbTask.status = '下载 ${chapterIndex + 1}/${chapters.length} · '
              '${pageIndex + 1}/${snapshot.pages.length}';
          objectbox.downloadTaskBox.put(dbTask);
          _notifyChanged();

          await ProviderImageCache.downloadPicture(
            providerId: snapshot.providerId,
            comicId: snapshot.comic.id,
            chapterId: snapshot.chapter.id,
            url: page.url,
            path: page.path,
            pictureType: _pictureTypeFromExtern(page.extern),
            extern: page.extern,
          );
          downloadedPages += 1;
        }
      }

      await _saveDownloadedComic(
        providerId: task.from,
        comic: comic,
        chapters: chapters,
      );

      dbTask
        ..isCompleted = true
        ..isDownloading = false
        ..status = '下载完成，共 $downloadedPages 页';
      objectbox.downloadTaskBox.put(dbTask);
      _notifyChanged();
    } catch (error, stackTrace) {
      logger.e('下载失败: ${task.comicName}', error: error);
      logger.d(stackTrace);
      dbTask
        ..isCompleted = true
        ..isDownloading = false
        ..status = '下载失败: $error';
      objectbox.downloadTaskBox.put(dbTask);
      _notifyChanged();
    }
  }

  Future<Comic> _loadComic({
    required String providerId,
    required String comicId,
  }) async {
    final provider = ProviderRegistry().getProvider(providerId);
    if (provider == null) {
      throw StateError('未找到数据源: $providerId');
    }
    return provider.getComicDetail(comicId);
  }

  Future<void> _saveDownloadedComic({
    required String providerId,
    required Comic comic,
    required List<Chapter> chapters,
  }) async {
    final key = _key(providerId, comic.id);
    final existing = _findDownloadedComic(key);
    final now = DateTime.now().toUtc();
    final storageRoot = await getDownloadPath();

    objectbox.unifiedDownloadBox.put(
      UnifiedComicDownload(
        id: existing?.id ?? 0,
        uniqueKey: key,
        source: providerId,
        comicId: comic.id,
        title: comic.title,
        description: comic.description,
        cover: jsonEncode(<String, dynamic>{'url': comic.coverUrl}),
        creator: jsonEncode(<String, dynamic>{
          'name': comic.author.join(' / '),
        }),
        titleMeta: '',
        metadata: jsonEncode(<String, dynamic>{
          'tags': comic.tags,
          'updated_at': comic.updatedAt,
        }),
        totalViews: comic.views,
        totalLikes: comic.likes,
        totalComments: 0,
        isFavourite: false,
        isLiked: false,
        allowComment: false,
        allowLike: false,
        allowFavorite: true,
        allowDownload: true,
        chapters: jsonEncode(
          chapters.map((chapter) => chapter.toJson()).toList(),
        ),
        detailJson: jsonEncode(comic.toJson()),
        storageRoot: storageRoot,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
        downloadedAt: now,
        deleted: false,
        schemaVersion: 2,
      ),
    );
  }

  UnifiedComicDownload? _findDownloadedComic(String key) {
    final query = objectbox.unifiedDownloadBox
        .query(UnifiedComicDownload_.uniqueKey.equals(key))
        .build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  DownloadTaskView _toView(DownloadTask task) {
    final info = task.taskInfo;
    final providerId = info?.from ?? '';
    final comicId = info?.comicId ?? task.comicId;
    return DownloadTaskView(
      providerId: providerId,
      comicId: comicId,
      comicName: task.comicName,
      status: task.status,
      isCompleted: task.isCompleted,
      isDownloading: task.isDownloading,
    );
  }

  PictureType _pictureTypeFromExtern(Map<String, dynamic> extern) {
    final raw = extern['pictureType'];
    if (raw is PictureType) return raw;
    if (raw is String) {
      return PictureType.values.firstWhere(
        (value) => value.name == raw,
        orElse: () => PictureType.page,
      );
    }
    return PictureType.page;
  }

  String _key(String providerId, String comicId) {
    return '${providerId.trim()}:${comicId.trim()}';
  }

  void _notifyChanged() {
    revision.value += 1;
  }
}
