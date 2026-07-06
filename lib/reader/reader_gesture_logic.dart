import 'package:flutter/widgets.dart';

import '../config/global/global_setting.dart';
import 'reader_action_controller.dart';

class ReaderGestureLogic {
  static void handleTap({
    required ReaderActionController actionController,
    required ReadSettingState readSetting,
    required Size screenSize,
    required TapDownDetails details,
    required VoidCallback onToggleMenu,
    VoidCallback? onBeforePageTurn,
  }) {
    if (readSetting.readMode == 0) {
      onToggleMenu();
      return;
    }

    final tapPosition = details.globalPosition;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;
    final thirdWidth = screenWidth / 3;
    final thirdHeight = screenHeight / 3;
    final inCenterControlArea =
        tapPosition.dx >= thirdWidth &&
        tapPosition.dx < thirdWidth * 2 &&
        tapPosition.dy >= thirdHeight &&
        tapPosition.dy < thirdHeight * 2;

    if (inCenterControlArea) {
      onToggleMenu();
      return;
    }

    final shouldNext = switch (readSetting.tapPageTurnMode) {
      ReaderTapPageTurnMode.fullScreen => true,
      ReaderTapPageTurnMode.leftHand => tapPosition.dx < (screenWidth / 2),
      ReaderTapPageTurnMode.rightHand => tapPosition.dx >= (screenWidth / 2),
    };

    onBeforePageTurn?.call();
    if (shouldNext) {
      actionController.onPageActionNext();
    } else {
      actionController.onPageActionPrev();
    }
  }
}
