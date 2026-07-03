import 'dart:async';
import 'dart:io';

import '../util/volume_key_handler.dart';
import 'reader_action_controller.dart';

class ReaderVolumeController {
  final ReaderActionController actionController;
  StreamSubscription<String>? _subscription;
  bool _isInterceptionEnabled = false;

  ReaderVolumeController({required this.actionController});

  void listen() {
    if (!Platform.isAndroid) return;
    _subscription?.cancel();
    _subscription = VolumeKeyHandler.volumeKeyEvents.listen(_handleEvent);
  }

  void enableInterception() {
    if (!Platform.isAndroid || _isInterceptionEnabled) return;
    _isInterceptionEnabled = true;
    unawaited(VolumeKeyHandler.enableVolumeKeyInterception());
  }

  void disableInterception() {
    if (!Platform.isAndroid || !_isInterceptionEnabled) return;
    _isInterceptionEnabled = false;
    unawaited(VolumeKeyHandler.disableVolumeKeyInterception());
  }

  void dispose() {
    if (!Platform.isAndroid) return;
    disableInterception();
    unawaited(_subscription?.cancel());
  }

  void _handleEvent(String event) {
    if (event == 'volume_down') {
      actionController.onVolumeActionNext();
    } else if (event == 'volume_up') {
      actionController.onVolumeActionPrev();
    }
  }
}
