import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../main.dart';
import '../models/comic.dart';
import '../models/reader_snapshot.dart';
import '../object_box/model.dart';
import '../object_box/objectbox.g.dart';
import '../providers/provider_registry.dart';
import '../type/enum.dart';
import '../util/foreground_task/data/download_task_json.dart';
import '../util/get_path.dart';
import 'provider_image_cache.dart';

class DownloadTaskView {
  final int id;
  final String providerId;
  final String comicId;
  final String comicName;
  final String status;
  final bool isCompleted;
  final bool isDownloading;

  const DownloadTaskView({
    required this.id,
    required this.providerId,
    required this.comicId,
    required this.comicName,
    required this.status,
    required this.isCompleted,
    required this.isDownloading,
  });

  bool get isFailed => isCompleted && status.startsWith('下载失败');
  bool get isCancelled => isCompleted && status.startsWith('已取消');
}

class DownloadedComic {
  final String providerId;
  final String comicId;
  final String title;
  final String description;
  final String coverUrl;
  final String creator;
  final List<String> tags;
  final List<Chapter> chapters;
  final Map<String, List<DownloadedPageImage>> pageImagesByChapterId;
  final String storageRoot;
  final DateTime downloadedAt;

  const DownloadedComic({
    required this.providerId,
    required this.comicId,
    required this.title,
    required this.description,
    required this.coverUrl,
    required this.creator,
    required this.tags,
    required this.chapters,
    required this.pageImagesByChapterId,
    required this.storageRoot,
    required this.downloadedAt,
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
      updatedAt: downloadedAt.toIso8601String(),
    );
  }
}

class DownloadedPageImage {
  final String id;
  final String name;
  final String path;
  final String url;
  final Map<String, dynamic> extern;

  const DownloadedPageImage({
    required this.id,
    required this.name,
    required this.path,
    required this.url,
    required this.extern,
  });

  factory DownloadedPageImage.fromMap(Map<String, dynamic> map) {
    return DownloadedPageImage(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      path: map['path']?.toString() ?? '',
      url: map['url']?.toString() ?? '',
      extern: Map<String, dynamic>.from(
        map['extern'] as Map? ?? const <String, dynamic>{},
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {'id': id, 'name': name, 'path': path, 'url': url, 'extern': extern};
  }
}

class _DownloadedChapterRecord {
  final Chapter chapter;
  final List<DownloadedPageImage> images;

  const _DownloadedChapterRecord({required this.chapter, required this.images});

  Map<String, dynamic> toMap() {
    return {
      'id': chapter.id,
      'name': chapter.name,
      'order': chapter.order,
      'comic_id': chapter.comicId,
      'logicalKey': chapter.id,
      'taskChapterId': chapter.id,
      'images': images.map((image) => image.toMap()).toList(),
    };
  }
}

class DownloadService {
  DownloadService._();

  static final DownloadService instance = DownloadService._();

  final ValueNotifier<int> revision = ValueNotifier<int>(0);
  bool _isProcessing = false;
  final Set<int> _cancelledTaskIds = <int>{};
  final Map<int, Completer<void>> _cancelSignals = <int, Completer<void>>{};

  void startProcessing() {
    _resetInterruptedTasks();
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

  Future<List<DownloadedComic>> getDownloadedComics() async {
    final items = objectbox.unifiedDownloadBox
        .getAll()
        .where((download) => !download.deleted)
        .map(_downloadedFromEntity)
        .where(
          (download) =>
              download.providerId.isNotEmpty &&
              download.comicId.isNotEmpty &&
              download.title.isNotEmpty &&
              download.chapters.isNotEmpty &&
              download.pageImagesByChapterId.isNotEmpty,
        )
        .toList();
    items.sort((a, b) => b.downloadedAt.compareTo(a.downloadedAt));
    return items;
  }

  Future<void> cancelTask(int taskId) async {
    final task = objectbox.downloadTaskBox.get(taskId);
    if (task == null || task.isCompleted) return;

    _cancelledTaskIds.add(taskId);
    _triggerCancelSignal(taskId);
    task
      ..status = task.isDownloading ? '取消中' : '已取消'
      ..isCompleted = !task.isDownloading
      ..isDownloading = task.isDownloading;
    objectbox.downloadTaskBox.put(task);
    _notifyChanged();
  }

  Future<void> retryTask(int taskId) async {
    final task = objectbox.downloadTaskBox.get(taskId);
    if (task == null || task.taskInfo == null) return;

    _cancelledTaskIds.remove(taskId);
    task
      ..isCompleted = false
      ..isDownloading = false
      ..status = '等待重试';
    objectbox.downloadTaskBox.put(task);
    _notifyChanged();
    unawaited(_processQueue());
  }

  Future<void> removeTask(int taskId) async {
    final task = objectbox.downloadTaskBox.get(taskId);
    if (task == null) return;
    if (task.isDownloading && !task.isCompleted) {
      await cancelTask(taskId);
      return;
    }
    _cancelledTaskIds.remove(taskId);
    objectbox.downloadTaskBox.remove(taskId);
    _notifyChanged();
  }

  Future<ReaderChapterSnapshot> getDownloadedChapterSnapshot({
    required DownloadedComic download,
    required Chapter chapter,
  }) async {
    final pages = await _resolveDownloadedReaderPages(
      download: download,
      chapter: chapter,
    );
    if (pages.isEmpty) {
      throw StateError('本地章节文件不存在: ${chapter.name}');
    }

    final comic = download.toComic();
    return ReaderChapterSnapshot(
      providerId: download.providerId,
      comic: comic,
      chapter: chapter,
      chapters: download.chapters,
      pages: pages,
      extern: const <String, dynamic>{'local': true},
    );
  }

  void _prepareCancelSignal(int taskId) {
    _cancelSignals.remove(taskId);
  }

  Future<void> _cancelFutureFor(int taskId) {
    return _cancelSignals.putIfAbsent(taskId, () => Completer<void>()).future;
  }

  void _triggerCancelSignal(int taskId) {
    final signal = _cancelSignals.putIfAbsent(taskId, () => Completer<void>());
    if (!signal.isCompleted) {
      signal.complete();
    }
  }

  Future<T> _raceWithCancellation<T>(int taskId, Future<T> future) async {
    _throwIfCancelled(taskId);
    final signal = _cancelSignals.putIfAbsent(taskId, () => Completer<void>());
    final result = await Future.any<T>([
      future,
      signal.future.then<T>((_) => throw const _DownloadCancelled()),
    ]);
    _throwIfCancelled(taskId);
    return result;
  }

  Future<void> _deleteDownloadedComicFiles({
    required String providerId,
    required String comicId,
  }) async {
    if (providerId.trim().isEmpty || comicId.trim().isEmpty) return;

    final existing = _findDownloadedComic(_key(providerId, comicId));
    if (existing != null) {
      objectbox.unifiedDownloadBox.remove(existing.id);
    }

    try {
      final targetDir = Directory(
        p.join(
          await getDownloadPath(),
          providerId.trim(),
          'original',
          _sanitizeStoredPath(comicId),
        ),
      );
      if (await targetDir.exists()) {
        await targetDir.delete(recursive: true);
      }
    } catch (error, stackTrace) {
      logger.w(
        '删除取消下载文件失败: providerId=$providerId comicId=$comicId',
        error: error,
      );
      logger.d(stackTrace);
    }
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
    final comic = await _loadComic(
      providerId: task.from,
      comicId: task.comicId,
    );

    dbTask
      ..isDownloading = true
      ..status = '开始下载'
      ..comicName = comic.title.isEmpty ? task.comicName : comic.title;
    objectbox.downloadTaskBox.put(dbTask);
    _notifyChanged();

    var downloadedPages = 0;
    final downloadedChapters = <_DownloadedChapterRecord>[];
    _prepareCancelSignal(dbTask.id);

    try {
      _throwIfCancelled(dbTask.id);
      for (
        var chapterIndex = 0;
        chapterIndex < chapters.length;
        chapterIndex++
      ) {
        _throwIfCancelled(dbTask.id);
        final chapter = chapters[chapterIndex];
        dbTask.status = '获取章节 ${chapterIndex + 1}/${chapters.length}';
        objectbox.downloadTaskBox.put(dbTask);
        _notifyChanged();

        final snapshot = await _raceWithCancellation(
          dbTask.id,
          provider.getReaderChapterSnapshot(
            comic: comic,
            chapter: chapter,
            chapters: chapters,
          ),
        );
        final downloadedImages = <DownloadedPageImage>[];

        for (
          var pageIndex = 0;
          pageIndex < snapshot.pages.length;
          pageIndex++
        ) {
          _throwIfCancelled(dbTask.id);
          final page = snapshot.pages[pageIndex];
          dbTask.status =
              '下载 ${chapterIndex + 1}/${chapters.length} · '
              '${pageIndex + 1}/${snapshot.pages.length}';
          objectbox.downloadTaskBox.put(dbTask);
          _notifyChanged();

          final downloadedPath = await _raceWithCancellation(
            dbTask.id,
            ProviderImageCache.downloadPicture(
              providerId: snapshot.providerId,
              comicId: snapshot.comic.id,
              chapterId: snapshot.chapter.id,
              url: page.url,
              path: page.path,
              pictureType: _pictureTypeFromExtern(page.extern),
              extern: page.extern,
              cancelSignal: _cancelFutureFor(dbTask.id),
            ),
          );
          _throwIfCancelled(dbTask.id);
          final storedName = p.basename(downloadedPath);
          downloadedImages.add(
            DownloadedPageImage(
              id: page.id.trim().isNotEmpty ? page.id.trim() : storedName,
              name: page.originalName.trim().isNotEmpty
                  ? page.originalName.trim()
                  : storedName,
              path: storedName,
              url: page.url,
              extern: page.extern,
            ),
          );
          downloadedPages += 1;
        }
        downloadedChapters.add(
          _DownloadedChapterRecord(
            chapter: chapter,
            images: List<DownloadedPageImage>.unmodifiable(downloadedImages),
          ),
        );
      }

      await _saveDownloadedComic(
        providerId: task.from,
        comic: comic,
        chapters: downloadedChapters,
      );

      dbTask
        ..isCompleted = true
        ..isDownloading = false
        ..status = '下载完成，共 $downloadedPages 页';
      objectbox.downloadTaskBox.put(dbTask);
      _notifyChanged();
    } on _DownloadCancelled {
      await _deleteDownloadedComicFiles(
        providerId: task.from,
        comicId: task.comicId,
      );
      dbTask
        ..isCompleted = true
        ..isDownloading = false
        ..status = '已取消';
      objectbox.downloadTaskBox.put(dbTask);
      _cancelledTaskIds.remove(dbTask.id);
      _notifyChanged();
    } catch (error, stackTrace) {
      if (_cancelledTaskIds.contains(dbTask.id)) {
        await _deleteDownloadedComicFiles(
          providerId: task.from,
          comicId: task.comicId,
        );
        dbTask
          ..isCompleted = true
          ..isDownloading = false
          ..status = '已取消';
        objectbox.downloadTaskBox.put(dbTask);
        _cancelledTaskIds.remove(dbTask.id);
        _notifyChanged();
        return;
      }
      logger.e('下载失败: ${task.comicName}', error: error);
      logger.d(stackTrace);
      dbTask
        ..isCompleted = true
        ..isDownloading = false
        ..status = '下载失败: $error';
      objectbox.downloadTaskBox.put(dbTask);
      _notifyChanged();
    } finally {
      _cancelSignals.remove(dbTask.id);
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
    required List<_DownloadedChapterRecord> chapters,
  }) async {
    final key = _key(providerId, comic.id);
    final existing = _findDownloadedComic(key);
    final now = DateTime.now().toUtc();
    final storageRoot = p.join(
      await getDownloadPath(),
      providerId.trim(),
      'original',
      _sanitizeStoredPath(comic.id),
    );

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
          chapters.map((chapter) => chapter.toMap()).toList(),
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
      id: task.id,
      providerId: providerId,
      comicId: comicId,
      comicName: task.comicName,
      status: task.status,
      isCompleted: task.isCompleted,
      isDownloading: task.isDownloading,
    );
  }

  DownloadedComic _downloadedFromEntity(UnifiedComicDownload download) {
    final creator = _decodeMap(download.creator)['name']?.toString() ?? '';
    final metadata = _decodeMap(download.metadata);
    final tags = _decodeTags(metadata['tags']);
    final chapters = _decodeChapters(download.chapters, download.comicId);
    final pageImagesByChapterId = _decodePageImagesByChapterId(
      download.chapters,
    );

    return DownloadedComic(
      providerId: download.source,
      comicId: download.comicId,
      title: download.title,
      description: download.description,
      coverUrl: _decodeCoverUrl(download.cover),
      creator: creator,
      tags: tags,
      chapters: chapters,
      pageImagesByChapterId: pageImagesByChapterId,
      storageRoot: download.storageRoot,
      downloadedAt: download.downloadedAt.toUtc(),
    );
  }

  Future<List<ReaderPageImage>> _resolveDownloadedReaderPages({
    required DownloadedComic download,
    required Chapter chapter,
  }) async {
    final storedImages =
        download.pageImagesByChapterId[chapter.id] ??
        const <DownloadedPageImage>[];
    if (storedImages.isNotEmpty) {
      final chapterDir = await _downloadedChapterDirectory(
        storageRoot: download.storageRoot,
        providerId: download.providerId,
        comicId: download.comicId,
        chapterId: chapter.id,
      );
      final pages = <ReaderPageImage>[];
      for (final image in storedImages) {
        final filePath = _resolveDownloadedImagePath(chapterDir, image);
        if (!await _isReadableFile(File(filePath))) continue;

        final name = image.name.trim().isNotEmpty
            ? image.name.trim()
            : p.basename(filePath);
        pages.add(
          ReaderPageImage(
            id: image.id.trim().isNotEmpty ? image.id.trim() : name,
            url: image.url,
            path: filePath,
            originalName: name,
            extern: {...image.extern, 'local': true},
          ),
        );
      }
      return List<ReaderPageImage>.unmodifiable(pages);
    }

    return const <ReaderPageImage>[];
  }

  Future<Directory> _downloadedChapterDirectory({
    required String storageRoot,
    required String providerId,
    required String comicId,
    required String chapterId,
  }) async {
    final comicDir = storageRoot.trim().isEmpty
        ? p.join(
            await getDownloadPath(),
            providerId.trim(),
            'original',
            _sanitizeStoredPath(comicId),
          )
        : storageRoot.trim();
    return Directory(p.join(comicDir, _sanitizeStoredPath(chapterId)));
  }

  String _resolveDownloadedImagePath(
    Directory chapterDir,
    DownloadedPageImage image,
  ) {
    final storedPath = image.path.trim().isNotEmpty
        ? image.path.trim()
        : image.name.trim();
    if (p.isAbsolute(storedPath)) {
      return storedPath;
    }
    return p.join(chapterDir.path, _sanitizeStoredPath(storedPath));
  }

  Future<bool> _isReadableFile(File file) async {
    try {
      if (!await file.exists()) return false;
      return await file.length() > 0;
    } catch (_) {
      return false;
    }
  }

  void _throwIfCancelled(int taskId) {
    if (_cancelledTaskIds.contains(taskId)) {
      throw const _DownloadCancelled();
    }
  }

  void _resetInterruptedTasks() {
    final query = objectbox.downloadTaskBox
        .query(
          DownloadTask_.isCompleted
              .equals(false)
              .and(DownloadTask_.isDownloading.equals(true)),
        )
        .build();
    try {
      final tasks = query.find();
      if (tasks.isEmpty) return;

      for (final task in tasks) {
        final wasCancelling = task.status.contains('取消');
        task
          ..isCompleted = wasCancelling
          ..isDownloading = false
          ..status = wasCancelling ? '已取消' : '等待恢复';
      }
      objectbox.downloadTaskBox.putMany(tasks);
      _notifyChanged();
    } finally {
      query.close();
    }
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

  String _sanitizeStoredPath(String rawPath) {
    final raw = rawPath.trim();
    if (raw.isEmpty) return '_';
    final candidate = p.isAbsolute(raw) ? p.basename(raw) : raw;
    final sanitized = candidate.replaceAll(RegExp(r'[^a-zA-Z0-9_\-.]'), '_');
    return sanitized.isEmpty ? '_' : sanitized;
  }

  String _decodeCoverUrl(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return '';
    final decoded = _decodeMap(text);
    final url = decoded['url']?.toString().trim() ?? '';
    return url.isNotEmpty ? url : text;
  }

  List<Chapter> _decodeChapters(String raw, String comicId) {
    if (raw.trim().isEmpty) return const <Chapter>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <Chapter>[];
      return decoded
          .whereType<Map>()
          .map((item) {
            final map = Map<String, dynamic>.from(item);
            return Chapter(
              id: map['id']?.toString() ?? '',
              comicId: map['comic_id']?.toString() ?? comicId,
              name: map['name']?.toString() ?? '',
              order: (map['order'] as num?)?.toInt() ?? 0,
            );
          })
          .where((chapter) => chapter.id.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const <Chapter>[];
    }
  }

  Map<String, List<DownloadedPageImage>> _decodePageImagesByChapterId(
    String raw,
  ) {
    if (raw.trim().isEmpty) {
      return const <String, List<DownloadedPageImage>>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const <String, List<DownloadedPageImage>>{};
      }

      final imagesByChapterId = <String, List<DownloadedPageImage>>{};
      for (final item in decoded.whereType<Map>()) {
        final map = Map<String, dynamic>.from(item);
        final chapterId = map['id']?.toString() ?? '';
        if (chapterId.isEmpty) continue;
        final rawImages = map['images'];
        if (rawImages is! List) continue;

        final images = rawImages
            .whereType<Map>()
            .map(
              (image) =>
                  DownloadedPageImage.fromMap(Map<String, dynamic>.from(image)),
            )
            .where((image) => image.path.trim().isNotEmpty)
            .toList(growable: false);
        if (images.isNotEmpty) {
          imagesByChapterId[chapterId] = images;
        }
      }
      return imagesByChapterId;
    } catch (_) {
      return const <String, List<DownloadedPageImage>>{};
    }
  }

  List<String> _decodeTags(dynamic raw) {
    if (raw is List) {
      return raw
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
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

  void _notifyChanged() {
    revision.value += 1;
  }
}

class _DownloadCancelled implements Exception {
  const _DownloadCancelled();
}
