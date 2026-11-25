import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/audio_engine.dart';
import '../model/tempo_map.dart';
import 'editor_provider.dart';
import 'project_provider.dart';

final audioProvider = Provider<AudioEngine>((ref) {
  final engine = createAudioEngine();
  ref.onDispose(engine.stopAll);
  return engine;
});

class TransportState {
  const TransportState({this.playing = false, this.tick = 0});

  final bool playing;

  /// Playhead position in ticks.
  final int tick;
}

class _ScheduledNote {
  const _ScheduledNote(
    this.startMicros,
    this.durationSeconds,
    this.pitch,
    this.velocity,
    this.drum,
    this.program,
    this.channel,
  );
  final double startMicros;
  final double durationSeconds;
  final int pitch;
  final int velocity;
  final bool drum;
  final int program;
  final int channel;
}

/// Plays the project through the [AudioEngine] with look-ahead scheduling and
/// drives the playhead.
class TransportNotifier extends Notifier<TransportState> {
  static const _pollInterval = Duration(milliseconds: 25);
  static const _lookaheadSeconds = 0.25;

  Timer? _timer;
  List<_ScheduledNote> _schedule = const [];
  int _next = 0;
  double _startAudioTime = 0;
  double _startMicros = 0;
  late TempoMap _tempoMap;
  int _endTick = 0;

  @override
  TransportState build() {
    ref.onDispose(() => _timer?.cancel());
    return const TransportState();
  }

  AudioEngine get _audio => ref.read(audioProvider);

  Future<void> toggle() => state.playing ? pause() : play();

  Future<void> play() async {
    if (state.playing) return;
    await _audio.resume();
    final project = ref.read(projectProvider).project;
    final editor = ref.read(editorProvider);
    final map = TempoMap(project.ppq, project.tempos);
    final from = state.tick;
    final fromMicros = map.microsAtTick(from);

    final anySolo = editor.solo.isNotEmpty;
    final scheduled = <_ScheduledNote>[];
    for (final track in project.tracks) {
      final audible = anySolo
          ? editor.solo.contains(track.id)
          : !editor.muted.contains(track.id);
      if (!audible) continue;
      for (final n in track.notes) {
        if (n.start < from) continue;
        final startMicros = map.microsAtTick(n.start);
        final endMicros = map.microsAtTick(n.end);
        scheduled.add(
          _ScheduledNote(
            startMicros,
            (endMicros - startMicros) / 1e6,
            n.pitch,
            n.velocity,
            track.isDrum,
            track.program,
            track.channel,
          ),
        );
      }
    }
    scheduled.sort((a, b) => a.startMicros.compareTo(b.startMicros));

    _tempoMap = map;
    _schedule = scheduled;
    _next = 0;
    _startMicros = fromMicros;
    _startAudioTime = _audio.currentTime + 0.05;
    _endTick = project.endTick;
    state = TransportState(playing: true, tick: from);
    _timer?.cancel();
    _timer = Timer.periodic(_pollInterval, (_) => _poll());
    _poll();
  }

  void _poll() {
    final elapsed = _audio.currentTime - _startAudioTime;
    final nowMicros = _startMicros + elapsed * 1e6;
    final horizon = nowMicros + _lookaheadSeconds * 1e6;

    while (_next < _schedule.length && _schedule[_next].startMicros < horizon) {
      final n = _schedule[_next++];
      _audio.playNote(
        pitch: n.pitch,
        velocity: n.velocity,
        when: _startAudioTime + (n.startMicros - _startMicros) / 1e6,
        duration: n.durationSeconds,
        drum: n.drum,
        program: n.program,
        channel: n.channel,
      );
    }

    final tick = elapsed < 0 ? state.tick : _tempoMap.tickAtMicros(nowMicros);
    if (tick > _endTick + _tempoMap.ppq) {
      stop();
      return;
    }
    if (tick != state.tick) state = TransportState(playing: true, tick: tick);
  }

  /// Stops sound and keeps the playhead where it is.
  Future<void> pause() async {
    _timer?.cancel();
    _timer = null;
    _audio.stopAll();
    state = TransportState(tick: state.tick);
  }

  /// Stops sound and returns the playhead to the start.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _audio.stopAll();
    state = const TransportState();
  }

  /// Moves the playhead; restarts playback from there if currently playing.
  Future<void> seek(int tick) async {
    final target = tick < 0 ? 0 : tick;
    if (state.playing) {
      await pause();
      state = TransportState(tick: target);
      await play();
    } else {
      state = TransportState(tick: target);
    }
  }
}

final transportProvider = NotifierProvider<TransportNotifier, TransportState>(
  TransportNotifier.new,
);
