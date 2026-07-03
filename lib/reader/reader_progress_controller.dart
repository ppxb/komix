import 'dart:async';

import 'package:flutter/services.dart';

import '../config/global/global_setting.dart';
import 'reader_cubit.dart';
import 'reader_history_manager.dart';
import 'reader_position_controller.dart';
import 'reader_side_effect_controller.dart';

class ReaderProgressController {
  final ReaderCubit readerCubit;
  final ReaderHistoryManager historyManager;
  final ReaderPositionController positionController;
  final ReaderSideEffectController sideEffects;
  final bool Function() isMounted;
  final bool Function() hasChapters;
  final bool Function() hasPages;
  final bool Function() isMenuVisible;
  final int Function() currentPageIndex;
  final int Function() lastPageIndex;
  final int Function() slotCount;
  final ReadSettingState Function() readSetting;
  final void Function(int pageIndex) setPageIndex;
  final void Function(bool visible) setMenuVisible;
  final bool Function() resetViewerTransform;

  Timer? _saveTimer;
  bool _isSeeking = false;

  ReaderProgressController({
    required this.readerCubit,
    required this.historyManager,
    required this.positionController,
    required this.sideEffects,
    required this.isMounted,
    required this.hasChapters,
    required this.hasPages,
    required this.isMenuVisible,
    required this.currentPageIndex,
    required this.lastPageIndex,
    required this.slotCount,
    required this.readSetting,
    required this.setPageIndex,
    required this.setMenuVisible,
    required this.resetViewerTransform,
  });

  bool get isSeeking => _isSeeking;

  void dispose() {
    _saveTimer?.cancel();
  }

  void cancelPendingSave() {
    _saveTimer?.cancel();
    _saveTimer = null;
  }

  void scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), () {
      if (!isMounted()) return;
      unawaited(saveNow());
    });
  }

  Future<void> saveNow() {
    if (!hasChapters() || slotCount() <= 0) {
      return Future<void>.value();
    }
    return historyManager.flushNow();
  }

  void handleScrollChanged() {
    if (_isSeeking) return;
    scheduleSave();
  }

  void handleObservedPageIndex(int pageIndex) {
    if (!isMounted() || _isSeeking || !hasPages()) return;
    _syncPageIndex(pageIndex);
    scheduleSave();
  }

  void handlePagedPageChanged(int pageIndex) {
    if (!isMounted() || _isSeeking || !hasPages()) return;

    _syncPageIndex(pageIndex);
    scheduleSave();
    resetViewerTransform();
    sideEffects.triggerEinkDelay(readSetting());

    if (isMenuVisible()) {
      setMenuVisible(false);
    }
  }

  void handleProgressChangeStart(double _) {
    if (!isMounted()) return;
    cancelPendingSave();
    positionController.cancelCorrection();
    sideEffects.stopAutoRead();
    _isSeeking = true;
    readerCubit.updateSliderRolling(true);
    readerCubit.updateIsComicRolling(true);
    HapticFeedback.selectionClick();
  }

  void handleProgressChanged(double value) {
    if (!isMounted()) return;
    final pageIndex = _clampPageIndex(value.round());
    if (pageIndex == currentPageIndex()) return;
    setPageIndex(pageIndex);
    readerCubit.updateSliderChanged(pageIndex.toDouble());
    HapticFeedback.selectionClick();
  }

  void handleProgressChangeEnd(double value) {
    if (!isMounted()) return;
    final pageIndex = _clampPageIndex(value.round());
    _isSeeking = false;
    readerCubit.updateSliderRolling(false);
    readerCubit.updateIsComicRolling(false);
    setPageIndex(pageIndex);
    readerCubit.updatePageIndex(pageIndex);
    positionController.jumpToPage(pageIndex);
    unawaited(saveNow());
    sideEffects.syncReadSetting(readSetting());
  }

  void _syncPageIndex(int pageIndex) {
    final safePageIndex = _clampPageIndex(pageIndex);
    if (safePageIndex != currentPageIndex()) {
      setPageIndex(safePageIndex);
    }
    readerCubit.updatePageIndex(safePageIndex);
  }

  int _clampPageIndex(int pageIndex) {
    return pageIndex.clamp(0, lastPageIndex()).toInt();
  }
}
