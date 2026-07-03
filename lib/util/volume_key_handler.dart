import 'dart:io';

import 'package:flutter/services.dart';

class VolumeKeyHandler {
  static const MethodChannel _channel = MethodChannel('volume_key_handler');
  static const EventChannel _eventChannel = EventChannel('volume_key_events');

  static Stream<String>? _volumeKeyStream;

  static Future<void> enableVolumeKeyInterception() {
    return _invoke('enableInterception');
  }

  static Future<void> disableVolumeKeyInterception() {
    return _invoke('disableInterception');
  }

  static Future<void> _invoke(String method) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  static Stream<String> get volumeKeyEvents {
    _volumeKeyStream ??= _eventChannel.receiveBroadcastStream().map(
      (event) => event.toString(),
    );
    return _volumeKeyStream!;
  }
}
