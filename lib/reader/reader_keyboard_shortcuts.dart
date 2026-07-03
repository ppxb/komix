import 'package:flutter/services.dart';

import 'reader_action_controller.dart';

bool handleGlobalKeyEvent(
  KeyEvent event,
  ReaderActionController actionController,
) {
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;

  final key = event.logicalKey;

  final isNext =
      key == LogicalKeyboardKey.arrowDown ||
      key == LogicalKeyboardKey.numpad2 ||
      key == LogicalKeyboardKey.keyS ||
      key == LogicalKeyboardKey.arrowRight ||
      key == LogicalKeyboardKey.numpad6 ||
      key == LogicalKeyboardKey.keyD;

  final isPrev =
      key == LogicalKeyboardKey.arrowUp ||
      key == LogicalKeyboardKey.numpad8 ||
      key == LogicalKeyboardKey.keyW ||
      key == LogicalKeyboardKey.arrowLeft ||
      key == LogicalKeyboardKey.numpad4 ||
      key == LogicalKeyboardKey.keyA;

  if (isNext) {
    actionController.onKeyScrollNext();
    return true;
  }

  if (isPrev) {
    actionController.onKeyScrollPrev();
    return true;
  }

  return false;
}
