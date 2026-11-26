import 'audio_engine.dart';

/// Silent engine with a wall-clock timer; used on non-web targets and tests.
class _SilentAudioEngine implements AudioEngine {
  final Stopwatch _clock = Stopwatch()..start();

  @override
  double get currentTime => _clock.elapsedMicroseconds / 1e6;

  @override
  Future<void> resume() async {}

  @override
  void setUseSystemMidi(bool enabled) {}

  @override
  void playNote({
    required int pitch,
    required int velocity,
    required double when,
    required double duration,
    bool drum = false,
    int program = 0,
    int channel = 0,
  }) {}

  @override
  void stopAll() {}
}

AudioEngine createAudioEngineImpl() => _SilentAudioEngine();
