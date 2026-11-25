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
  ///
  /// [program] is the General MIDI instrument (0-127) and [channel] the MIDI
  /// channel (9 is drums). Engines that cannot render instruments may ignore
  /// them.
  void playNote({
    required int pitch,
    required int velocity,
    required double when,
    required double duration,
    bool drum = false,
    int program = 0,
    int channel = 0,
  });

  /// Silences everything that is playing or scheduled.
  void stopAll();
}

AudioEngine createAudioEngine() => impl.createAudioEngineImpl();
