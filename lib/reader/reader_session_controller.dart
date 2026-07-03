import 'dart:async';
import 'dart:ui';

import '../models/comic.dart';
import '../models/reader_snapshot.dart';
import '../providers/provider_registry.dart';
import 'image_size_cache_store.dart';

typedef ReaderChapterSnapshotLoader =
    Future<ReaderChapterSnapshot> Function({
      required Comic comic,
      required Chapter chapter,
      required List<Chapter> chapters,
    });

class ReaderChapterData {
  final ReaderChapterSnapshot snapshot;
  final Map<int, Size> persistedSizes;

  const ReaderChapterData({
    required this.snapshot,
    required this.persistedSizes,
  });
}

class ReaderSessionController {
  final String providerId;
  final Comic comic;
  final List<Chapter> chapters;
  final ReaderChapterSnapshotLoader? snapshotLoader;
  final void Function()? onLoadStarted;

  final Map<int, Future<ReaderChapterData>> _prefetchedChapterData = {};

  ReaderSessionController({
    required this.providerId,
    required this.comic,
    required this.chapters,
    this.snapshotLoader,
    this.onLoadStarted,
  });

  String chapterTitle(int index) {
    if (chapters.isEmpty) return '暂无章节';
    final chapter = chapters[index];
    return chapters.length == 1 ? '单章节' : chapter.name;
  }

  Future<ReaderChapterData> loadChapter(
    int index, {
    bool markHistoryLoading = true,
  }) async {
    if (markHistoryLoading) {
      onLoadStarted?.call();
    }
    if (chapters.isEmpty) {
      throw StateError('暂无章节');
    }

    final chapter = chapters[index];
    final loader = snapshotLoader;
    final snapshot = loader != null
        ? await loader(comic: comic, chapter: chapter, chapters: chapters)
        : await _loadProviderChapterSnapshot(chapter);
    final pageSizeKeys = buildPageSizeKeys(snapshot);
    final persistedSizes = await ImageSizeCacheStore(
      sourceTag: providerId,
      pageKeys: pageSizeKeys,
    ).readIndexedSizes(pageKeys: pageSizeKeys, count: snapshot.pages.length);

    return ReaderChapterData(
      snapshot: snapshot,
      persistedSizes: persistedSizes,
    );
  }

  Future<ReaderChapterData> takeChapterFuture(int index) {
    return _prefetchedChapterData.remove(index) ?? loadChapter(index);
  }

  void prefetchAdjacentChapters(int currentIndex) {
    if (chapters.length <= 1) return;

    final keepIndexes = <int>{currentIndex - 1, currentIndex + 1};
    _prefetchedChapterData.removeWhere(
      (index, _) => !keepIndexes.contains(index),
    );
    _prefetchChapter(currentIndex - 1, currentIndex);
    _prefetchChapter(currentIndex + 1, currentIndex);
  }

  void removePrefetch(int index) {
    _prefetchedChapterData.remove(index);
  }

  void clearPrefetch() {
    _prefetchedChapterData.clear();
  }

  Future<ReaderChapterSnapshot> _loadProviderChapterSnapshot(
    Chapter chapter,
  ) async {
    final provider = ProviderRegistry().getProvider(providerId);
    if (provider == null) {
      throw StateError('未找到数据源: $providerId');
    }
    return provider.getReaderChapterSnapshot(
      comic: comic,
      chapter: chapter,
      chapters: chapters,
    );
  }

  void _prefetchChapter(int index, int currentIndex) {
    if (index < 0 ||
        index >= chapters.length ||
        index == currentIndex ||
        _prefetchedChapterData.containsKey(index)) {
      return;
    }

    final future = loadChapter(index, markHistoryLoading: false);
    _prefetchedChapterData[index] = future;
    unawaited(
      future.then<void>(
        (_) {},
        onError: (_) {
          if (_prefetchedChapterData[index] == future) {
            _prefetchedChapterData.remove(index);
          }
        },
      ),
    );
  }

  static List<String> buildPageSizeKeys(ReaderChapterSnapshot snapshot) {
    return snapshot.pages
        .map(
          (page) =>
              '${snapshot.providerId}|${snapshot.comic.id}|${snapshot.chapter.id}|${page.cacheKey}',
        )
        .toList(growable: false);
  }
}
