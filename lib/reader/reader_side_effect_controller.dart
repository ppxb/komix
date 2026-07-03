import 'dart:async';

import 'package:flutter/services.dart';

import '../config/global/global_setting.dart';
import 'reader_action_controller.dart';
import 'reader_layout.dart';
import 'reader_volume_controller.dart';

class ReaderSideEffectController {
  final ReaderActionController actionController;
  final bool Function() isMounted;
  final bool Function() isMenuVisible;
  final bool Function() isSeeking;
  final int Function() slotCount;
  final VoidCallback requestRebuild;
  final ReaderVolumeController _volumeController;

  Timer? _autoReadTimer;
  Timer? _einkDelayTimer;
  int? _autoReadIntervalMs;
  bool _isAutoReadPaused = false;
  bool _lastAutoScrollEnabled = false;
  bool _showEinkMask = false;

  ReaderSideEffectController({
    required this.actionController,
    required this.isMounted,
    required this.isMenuVisible,
    required this.isSeeking,
    required this.slotCount,
    required this.requestRebuild,
  }) : _volumeController = ReaderVolumeController(
         actionController: actionController,
       );

  bool get isAutoReadPaused => _isAutoReadPaused;

  bool get showEinkMask => _showEinkMask;

  void listenVolume() {
    _volumeController.listen();
  }

  void dispose() {
    _autoReadTimer?.cancel();
    _einkDelayTimer?.cancel();
    _volumeController.dispose();
  }

  void applySystemUiVisibility(
    bool visible,
    SystemUiOverlayStyle overlayStyle,
  ) {
    SystemChrome.setSystemUIOverlayStyle(overlayStyle);
    if (visible) {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
      );
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  void restoreSystemUi() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
    );
  }

  void syncReadSetting(ReadSettingState readSetting) {
    _syncAutoRead(readSetting);
    _syncVolumeKeyInterception(readSetting);
  }

  void stopAutoRead() {
    _autoReadTimer?.cancel();
    _autoReadTimer = null;
    _autoReadIntervalMs = null;
  }

  void toggleAutoReadPaused(ReadSettingState readSetting) {
    _isAutoReadPaused = !_isAutoReadPaused;
    requestRebuild();
    _syncAutoRead(readSetting);
  }

  void hideEinkMask() {
    _einkDelayTimer?.cancel();
    _einkDelayTimer = null;
    if (_showEinkMask && isMounted()) {
      _showEinkMask = false;
      requestRebuild();
    }
  }

  void triggerEinkDelay(ReadSettingState readSetting) {
    if (isColumnReadMode(readSetting.readMode) ||
        !readSetting.einkOptimization) {
      hideEinkMask();
      return;
    }

    final delayMs = readSetting.einkDelayMs.clamp(50, 500).toInt();
    _einkDelayTimer?.cancel();
    _showEinkMask = true;
    requestRebuild();
    _einkDelayTimer = Timer(Duration(milliseconds: delayMs), () {
      if (!isMounted()) return;
      _showEinkMask = false;
      requestRebuild();
    });
  }

  void _syncAutoRead(ReadSettingState readSetting) {
    final autoScrollEnabled = readSetting.autoScroll;
    if (!autoScrollEnabled) {
      _lastAutoScrollEnabled = false;
      _isAutoReadPaused = false;
      stopAutoRead();
      return;
    }

    if (!_lastAutoScrollEnabled) {
      _isAutoReadPaused = false;
    }
    _lastAutoScrollEnabled = true;

    final intervalMs = isColumnReadMode(readSetting.readMode)
        ? readSetting.autoScrollColumnIntervalMs.clamp(300, 5000)
        : readSetting.autoScrollPageIntervalMs.clamp(800, 10000);
    final intervalMsInt = intervalMs.toInt();
    final shouldRun =
        !_isAutoReadPaused &&
        !isMenuVisible() &&
        !isSeeking() &&
        slotCount() > 0;

    if (!shouldRun) {
      stopAutoRead();
      return;
    }

    if (_autoReadTimer != null && _autoReadIntervalMs == intervalMsInt) {
      return;
    }

    _autoReadTimer?.cancel();
    _autoReadIntervalMs = intervalMsInt;
    _autoReadTimer = Timer.periodic(Duration(milliseconds: intervalMsInt), (_) {
      if (!isMounted() || isMenuVisible() || isSeeking()) return;
      actionController.onAutoReadTick();
    });
  }

  void _syncVolumeKeyInterception(ReadSettingState readSetting) {
    if (readSetting.volumeKeyPageTurn && !isMenuVisible()) {
      _volumeController.enableInterception();
    } else {
      _volumeController.disableInterception();
    }
  }
}
