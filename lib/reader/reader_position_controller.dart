import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:scrollview_observer/scrollview_observer.dart';

import '../config/global/global_setting.dart';
import 'reader_layout.dart';
import 'reader_side_effect_controller.dart';

class ReaderPositionController {
  final BuildContext context;
  final ScrollController scrollController;
  final ListObserverController observerController;
  final PageController pageController;
  final ReaderSideEffectController sideEffects;
  final bool Function() isMounted;
  final bool Function() isSeeking;
  final bool Function() hasPages;
  final int Function() lastPageIndex;
  final List<GlobalKey> Function() slotKeys;
  final double Function(int pageIndex) estimatedPageOffset;
  final bool Function() resetViewerTransform;

  Timer? _pageCorrectionTimer;

  ReaderPositionController({
    required this.context,
    required this.scrollController,
    required this.observerController,
    required this.pageController,
    required this.sideEffects,
    required this.isMounted,
    required this.isSeeking,
    required this.hasPages,
    required this.lastPageIndex,
    required this.slotKeys,
    required this.estimatedPageOffset,
    required this.resetViewerTransform,
  });

  void dispose() {
    _pageCorrectionTimer?.cancel();
  }

  void cancelCorrection() {
    _pageCorrectionTimer?.cancel();
    _pageCorrectionTimer = null;
  }

  void jumpToPage(int pageIndex, {bool correctAfterLayout = false}) {
    if (!isMounted() || !hasPages()) return;

    final readSetting = context.read<GlobalSettingCubit>().state.readSetting;
    final targetPage = pageIndex.clamp(0, lastPageIndex()).toInt();
    resetViewerTransform();
    if (!isColumnReadMode(readSetting.readMode)) {
      if (!pageController.hasClients) return;
      pageController.jumpToPage(targetPage);
      sideEffects.triggerEinkDelay(readSetting);
      return;
    }

    _jumpToColumnPage(targetPage, correctAfterLayout: correctAfterLayout);
  }

  void schedulePageCorrection(int pageIndex) {
    cancelCorrection();
    _pageCorrectionTimer = Timer(const Duration(milliseconds: 80), () {
      if (!isMounted() || isSeeking() || !scrollController.hasClients) return;
      _correctToPage(pageIndex);
      _pageCorrectionTimer = Timer(const Duration(milliseconds: 260), () {
        if (!isMounted() || isSeeking() || !scrollController.hasClients) {
          return;
        }
        _correctToPage(pageIndex);
      });
    });
  }

  void _jumpToColumnPage(
    int targetPage, {
    required bool correctAfterLayout,
  }) {
    if (!scrollController.hasClients) return;
    if (_jumpToBuiltColumnSlot(targetPage)) {
      if (correctAfterLayout) {
        schedulePageCorrection(targetPage);
      }
      return;
    }

    try {
      final future = observerController.jumpTo(
        index: targetPage,
        alignment: 0,
      );
      unawaited(
        future.then<void>(
          (_) {
            if (!isMounted()) return;
            if (correctAfterLayout) {
              schedulePageCorrection(targetPage);
            }
          },
          onError: (_) {
            if (!isMounted()) return;
            _jumpToEstimatedColumnOffset(
              targetPage,
              correctAfterLayout: correctAfterLayout,
            );
          },
        ),
      );
    } catch (_) {
      _jumpToEstimatedColumnOffset(
        targetPage,
        correctAfterLayout: correctAfterLayout,
      );
    }
  }

  bool _jumpToBuiltColumnSlot(int targetPage) {
    final keys = slotKeys();
    if (targetPage < 0 || targetPage >= keys.length) return false;

    final pageContext = keys[targetPage].currentContext;
    if (pageContext == null) return false;

    Scrollable.ensureVisible(
      pageContext,
      alignment: 0,
      duration: Duration.zero,
      curve: Curves.linear,
    );
    return true;
  }

  void _jumpToEstimatedColumnOffset(
    int targetPage, {
    required bool correctAfterLayout,
  }) {
    if (!scrollController.hasClients) return;
    final position = scrollController.position;
    final target = estimatedPageOffset(
      targetPage,
    ).clamp(position.minScrollExtent, position.maxScrollExtent);
    scrollController.jumpTo(target.toDouble());

    if (correctAfterLayout) {
      schedulePageCorrection(targetPage);
    }
  }

  void _correctToPage(int pageIndex) {
    if (!isMounted()) return;
    final readSetting = context.read<GlobalSettingCubit>().state.readSetting;
    if (!isColumnReadMode(readSetting.readMode)) {
      jumpToPage(pageIndex);
      return;
    }

    final target = pageIndex.clamp(0, lastPageIndex()).toInt();
    final keys = slotKeys();
    if (target < 0 || target >= keys.length) return;

    if (!_jumpToBuiltColumnSlot(target)) {
      jumpToPage(target);
    }
  }
}
