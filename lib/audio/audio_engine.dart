import 'audio_engine_stub.dart'
    if (dart.library.js_interop) 'audio_engine_web.dart'
    as impl;

/// Minimal synth interface so playback logic stays platform independent.
abstract class AudioEngine {
  /// Audio clock in seconds.
  double get currentTime;

  /// Must be called from a user gesture on the web before sound is produced.
  Future<void> resume();

  /// Schedules a note at audio-clock time [when] lasting [duration] seconds.
  void playNote({
    required int pitch,
    required int velocity,
    required double when,
    required double duration,
    bool drum = false,
  });

  /// Silences everything that is playing or scheduled.
  void stopAll();
}

AudioEngine createAudioEngine() => impl.createAudioEngineImpl();
