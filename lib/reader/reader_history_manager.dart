import 'dart:async';

import '../models/comic.dart';
import '../services/reading_progress_service.dart';

class ReaderHistoryManager {
  final String providerId;
  final Comic comic;
  final int chapterCount;
  final String Function() getChapterId;
  final String Function() getChapterTitle;
  final int Function() getChapterIndex;
  final int Function() getPageIndex;
  final int Function() getPageCount;

  Timer? _timer;
  DateTime? _lastUpdateTime;
  bool _isWriting = false;
  bool _isLoading = true;

  ReaderHistoryManager({
    required this.providerId,
    required this.comic,
    required this.chapterCount,
    required this.getChapterId,
    required this.getChapterTitle,
    required this.getChapterIndex,
    required this.getPageIndex,
    required this.getPageCount,
  });

  Future<void> init() async {
    _startTimer();
  }

  void markLoaded() {
    _isLoading = false;
  }

  void markLoading() {
    _isLoading = true;
  }

  void stop() {
    _timer?.cancel();
  }

  Future<void> flushNow() {
    return _writeProgress(force: true);
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      unawaited(_writeProgress());
    });
  }

  Future<void> _writeProgress({bool force = false}) async {
    if (_isLoading || _isWriting) return;

    final pageCount = getPageCount();
    if (pageCount <= 0) return;

    if (!force &&
        _lastUpdateTime != null &&
        DateTime.now().difference(_lastUpdateTime!).inMilliseconds < 100) {
      return;
    }

    _isWriting = true;
    try {
      await ReadingProgressService.instance.saveProgress(
        ReadingProgress(
          providerId: providerId,
          comicId: comic.id,
          comicTitle: comic.title,
          coverUrl: comic.coverUrl,
          chapterId: getChapterId(),
          chapterTitle: getChapterTitle(),
          chapterIndex: getChapterIndex(),
          chapterCount: chapterCount,
          pageIndex: getPageIndex().clamp(0, pageCount - 1).toInt(),
          pageCount: pageCount,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
    } finally {
      _isWriting = false;
      _lastUpdateTime = DateTime.now();
    }
  }
}
