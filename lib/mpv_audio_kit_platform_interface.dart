import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'mpv_audio_kit_method_channel.dart';

abstract class MpvAudioKitPlatform extends PlatformInterface {
  /// Constructs a MpvAudioKitPlatform.
  MpvAudioKitPlatform() : super(token: _token);

  static final Object _token = Object();

  static MpvAudioKitPlatform _instance = MethodChannelMpvAudioKit();

  /// The default instance of [MpvAudioKitPlatform] to use.
  ///
  /// Defaults to [MethodChannelMpvAudioKit].
  static MpvAudioKitPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [MpvAudioKitPlatform] when
  /// they register themselves.
  static set instance(MpvAudioKitPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
