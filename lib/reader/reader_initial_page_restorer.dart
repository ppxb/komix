import 'dart:async';

import 'package:flutter/widgets.dart';

class ReaderInitialPageRestorer {
  final bool Function() isMounted;
  final VoidCallback requestRebuild;

  bool _shouldRestoreInitialPage = false;
  bool _isRestoringInitialPage = false;
  bool _isRestoreScheduled = false;
  int _restoreAttempts = 0;
  int _initialPageIndex = 0;

  ReaderInitialPageRestorer({
    required this.isMounted,
    required this.requestRebuild,
  });

  int get initialPageIndex => _initialPageIndex;

  bool get shouldRestoreInitialPage => _shouldRestoreInitialPage;

  bool get isRestoringInitialPage => _isRestoringInitialPage;

  void configure(int initialPageIndex) {
    _initialPageIndex = initialPageIndex < 0 ? 0 : initialPageIndex;
    _shouldRestoreInitialPage = _initialPageIndex > 0;
    _isRestoringInitialPage = _shouldRestoreInitialPage;
    _isRestoreScheduled = false;
    _restoreAttempts = 0;
  }

  void reset() {
    _initialPageIndex = 0;
    _shouldRestoreInitialPage = false;
    _isRestoringInitialPage = false;
    _isRestoreScheduled = false;
    _restoreAttempts = 0;
  }

  void clampInitialPage(int lastPageIndex) {
    _initialPageIndex = _initialPageIndex.clamp(0, lastPageIndex).toInt();
  }

  void schedule(VoidCallback restore) {
    if (!_shouldRestoreInitialPage || _isRestoreScheduled) return;

    _isRestoreScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _isRestoreScheduled = false;
      restore();
    });
  }

  void markRestored() {
    _shouldRestoreInitialPage = false;
  }

  void finishRestoringDelayed() {
    Future<void>.delayed(const Duration(milliseconds: 120), () {
      if (!isMounted()) return;
      _isRestoringInitialPage = false;
      requestRebuild();
    });
  }

  void retry(VoidCallback scheduleRestore) {
    if (_restoreAttempts >= 8) {
      _shouldRestoreInitialPage = false;
      if (isMounted()) {
        _isRestoringInitialPage = false;
        requestRebuild();
      }
      return;
    }

    _restoreAttempts += 1;
    Future<void>.delayed(const Duration(milliseconds: 120), () {
      if (!isMounted()) return;
      scheduleRestore();
    });
  }
}
