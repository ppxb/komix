import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/comic.dart';
import 'reader_chapter_view_state.dart';
import 'reader_cubit.dart';
import 'reader_history_manager.dart';
import 'reader_position_controller.dart';
import 'reader_progress_controller.dart';
import 'reader_session_controller.dart';
import 'reader_side_effect_controller.dart';

typedef ReaderChapterFutureSetter =
    void Function(Future<ReaderChapterData> chapterFuture);

typedef ReaderChapterStateSetter =
    void Function({
      required int chapterIndex,
      required Future<ReaderChapterData> chapterFuture,
      required int pageIndex,
    });

class ReaderChapterNavigationController {
  final List<Chapter> chapters;
  final ReaderCubit readerCubit;
  final ReaderChapterViewState chapterView;
  final ReaderHistoryManager historyManager;
  final ReaderSessionController sessionController;
  final ReaderSideEffectController sideEffects;
  final ReaderPositionController positionController;
  final ReaderProgressController progressController;
  final ScrollController scrollController;
  final PageController pageController;
  final int Function() chapterIndex;
  final bool Function() isRestoringInitialPage;
  final bool Function() resetViewerTransform;
  final ReaderChapterFutureSetter setChapterFuture;
  final ReaderChapterStateSetter setChapterState;

  ReaderChapterNavigationController({
    required this.chapters,
    required this.readerCubit,
    required this.chapterView,
    required this.historyManager,
    required this.sessionController,
    required this.sideEffects,
    required this.positionController,
    required this.progressController,
    required this.scrollController,
    required this.pageController,
    required this.chapterIndex,
    required this.isRestoringInitialPage,
    required this.resetViewerTransform,
    required this.setChapterFuture,
    required this.setChapterState,
  });

  Future<void> reloadChapter() {
    sideEffects.hideEinkMask();
    resetViewerTransform();
    final currentIndex = chapterIndex();
    sessionController.removePrefetch(currentIndex);
    final future = sessionController.loadChapter(currentIndex);
    setChapterFuture(future);
    return future.then<void>((_) {}, onError: (_) {});
  }

  bool handleBoundary(
    bool isNext, {
    required int chapterEndPageIndex,
  }) {
    if (progressController.isSeeking ||
        isRestoringInitialPage() ||
        chapters.isEmpty) {
      return false;
    }

    final targetIndex = chapterIndex() + (isNext ? 1 : -1);
    if (targetIndex < 0 || targetIndex >= chapters.length) {
      return false;
    }

    goToChapter(
      targetIndex,
      initialPageIndex: isNext ? 0 : chapterEndPageIndex,
    );
    return true;
  }

  void goToChapter(int index, {int initialPageIndex = 0}) {
    final currentIndex = chapterIndex();
    if (index < 0 || index >= chapters.length || index == currentIndex) {
      return;
    }

    progressController.cancelPendingSave();
    sideEffects.stopAutoRead();
    sideEffects.hideEinkMask();
    resetViewerTransform();
    unawaited(progressController.saveNow());
    positionController.cancelCorrection();
    historyManager.markLoading();

    final oldImageSizeCubit = chapterView.reset();
    final targetInitialPageIndex = initialPageIndex < 0 ? 0 : initialPageIndex;
    setChapterState(
      chapterIndex: index,
      chapterFuture: sessionController.takeChapterFuture(index),
      pageIndex: targetInitialPageIndex,
    );
    unawaited(oldImageSizeCubit?.close());

    readerCubit.updateTotalSlots(0);
    readerCubit.updatePageIndex(0);

    if (scrollController.hasClients) {
      scrollController.jumpTo(0);
    }
    if (pageController.hasClients) {
      pageController.jumpToPage(0);
    }
  }
}
