import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:scrollview_observer/scrollview_observer.dart';

import '../config/global/global_setting.dart';
import 'reader_cubit.dart';

class ReaderActionController {
  final BuildContext context;
  final ScrollController scrollController;
  final ListObserverController observerController;
  final PageController pageController;
  final bool Function(bool isNext)? onBeforeTurnPage;
  final bool Function(bool isNext)? onChapterBoundary;

  ReaderActionController({
    required this.context,
    required this.scrollController,
    required this.observerController,
    required this.pageController,
    this.onBeforeTurnPage,
    this.onChapterBoundary,
  });

  ReadSettingState get _readSetting =>
      context.read<GlobalSettingCubit>().state.readSetting;

  int get _readMode => _readSetting.readMode;

  int get _pageIndex => context.read<ReaderCubit>().state.pageIndex;

  int get _totalSlots => context.read<ReaderCubit>().state.totalSlots;

  bool get _noAnimation => _readSetting.noAnimation;

  int get _autoScrollColumnDistancePercent =>
      _readSetting.autoScrollColumnDistancePercent;

  int get _volumeKeyPageTurnDistancePercent =>
      _readSetting.volumeKeyPageTurnDistancePercent;

  BuildContext get _activeContext => context;

  void onKeyScrollNext() {
    final mode = _readMode;
    if (mode == 0) {
      _scrollVertical(offset: 200.0, durationMs: 100);
    } else {
      _turnPage(isNext: true);
    }
  }

  void onKeyScrollPrev() {
    final mode = _readMode;
    if (mode == 0) {
      _scrollVertical(offset: -200.0, durationMs: 100);
    } else {
      _turnPage(isNext: false);
    }
  }

  void onPageActionNext() {
    final mode = _readMode;
    if (mode == 0) {
      _scrollVertical(page: true, next: true);
    } else {
      _turnPage(isNext: true);
    }
  }

  void onPageActionPrev() {
    final mode = _readMode;
    if (mode == 0) {
      _scrollVertical(page: true, next: false);
    } else {
      _turnPage(isNext: false);
    }
  }

  void onVolumeActionNext() {
    if (!_readSetting.volumeKeyPageTurn) return;
    final mode = _readMode;
    if (mode == 0) {
      _scrollVerticalByPercent(
        percent: _volumeKeyPageTurnDistancePercent,
        next: true,
      );
    } else {
      _turnPage(isNext: true);
    }
  }

  void onVolumeActionPrev() {
    if (!_readSetting.volumeKeyPageTurn) return;
    final mode = _readMode;
    if (mode == 0) {
      _scrollVerticalByPercent(
        percent: _volumeKeyPageTurnDistancePercent,
        next: false,
      );
    } else {
      _turnPage(isNext: false);
    }
  }

  void onAutoReadTick() {
    final mode = _readMode;
    if (mode == 0) {
      _scrollVerticalAuto();
    } else {
      _turnPage(isNext: true);
    }
  }

  void _scrollVertical({
    double offset = 0,
    int durationMs = 0,
    bool page = false,
    bool next = true,
  }) {
    if (page) {
      final totalSlots = _totalSlots;
      if (totalSlots <= 0 || !scrollController.hasClients) return;

      final currentPage = _pageIndex + (next ? 1 : -1);
      if (currentPage < 0 || currentPage >= totalSlots) {
        if (_isVerticalScrollAtEdge(isNext: next) &&
            _tryHandleChapterBoundary(isNext: next)) {
          return;
        }
      }
      final targetPage = currentPage.clamp(0, totalSlots - 1).toInt();

      if (_noAnimation) {
        observerController.jumpTo(
          index: targetPage,
          offset: (_) => MediaQuery.of(_activeContext).padding.top + 5.0,
        );
      } else {
        observerController.animateTo(
          index: targetPage,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          offset: (_) => MediaQuery.of(_activeContext).padding.top + 5.0,
        );
      }
    } else {
      if (!scrollController.hasClients) return;
      if (offset != 0 &&
          _isVerticalScrollAtEdge(isNext: offset > 0) &&
          _tryHandleChapterBoundary(isNext: offset > 0)) {
        return;
      }

      final currentOffset = scrollController.offset;
      final targetOffset = currentOffset + offset;

      scrollController.animateTo(
        targetOffset.clamp(
          scrollController.position.minScrollExtent,
          scrollController.position.maxScrollExtent,
        ).toDouble(),
        duration: Duration(milliseconds: durationMs),
        curve: Curves.easeOutQuad,
      );
    }
  }

  void _scrollVerticalAuto() {
    if (!scrollController.hasClients) return;
    if (_isVerticalScrollAtEdge(isNext: true) &&
        _tryHandleChapterBoundary(isNext: true)) {
      return;
    }

    final viewportHeight = MediaQuery.of(_activeContext).size.height;
    final distancePercent = _autoScrollColumnDistancePercent.clamp(10, 100);
    final targetOffset =
        scrollController.offset + viewportHeight * (distancePercent / 100);
    final clamped = targetOffset.clamp(
      scrollController.position.minScrollExtent,
      scrollController.position.maxScrollExtent,
    ).toDouble();

    if (_noAnimation) {
      scrollController.jumpTo(clamped);
    } else {
      scrollController.animateTo(
        clamped,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _scrollVerticalByPercent({required int percent, required bool next}) {
    if (!scrollController.hasClients) return;
    if (_isVerticalScrollAtEdge(isNext: next) &&
        _tryHandleChapterBoundary(isNext: next)) {
      return;
    }

    final viewportHeight = MediaQuery.of(_activeContext).size.height;
    final distancePercent = percent.clamp(10, 100);
    final direction = next ? 1.0 : -1.0;
    final targetOffset =
        scrollController.offset +
        viewportHeight * (distancePercent / 100) * direction;
    final clamped = targetOffset.clamp(
      scrollController.position.minScrollExtent,
      scrollController.position.maxScrollExtent,
    ).toDouble();

    if (_noAnimation) {
      scrollController.jumpTo(clamped);
    } else {
      scrollController.animateTo(
        clamped,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _turnPage({required bool isNext}) {
    if (onBeforeTurnPage?.call(isNext) ?? false) return;
    if (!pageController.hasClients) return;
    final totalSlots = _totalSlots;
    if (totalSlots <= 0) return;

    final currentPage = _pageIndex + (isNext ? 1 : -1);
    if (currentPage < 0 || currentPage >= totalSlots) {
      if (_tryHandleChapterBoundary(isNext: isNext)) return;
    }

    if (_noAnimation) {
      final targetPage = currentPage.clamp(0, totalSlots - 1).toInt();
      pageController.jumpToPage(targetPage);
      return;
    }

    if (isNext) {
      pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  bool _tryHandleChapterBoundary({required bool isNext}) {
    return onChapterBoundary?.call(isNext) ?? false;
  }

  bool _isVerticalScrollAtEdge({required bool isNext}) {
    final position = scrollController.position;
    const tolerance = 1.0;
    if (isNext) {
      return position.pixels >= position.maxScrollExtent - tolerance;
    }
    return position.pixels <= position.minScrollExtent + tolerance;
  }
}
