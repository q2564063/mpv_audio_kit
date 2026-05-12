import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'mpv_audio_kit_platform_interface.dart';

/// An implementation of [MpvAudioKitPlatform] that uses method channels.
class MethodChannelMpvAudioKit extends MpvAudioKitPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('mpv_audio_kit');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
