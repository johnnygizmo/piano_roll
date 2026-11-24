import '../midi/midi_events.dart';
import 'track.dart';

class TempoChange {
  const TempoChange(this.tick, this.microsPerQuarter);
  final int tick;
  final int microsPerQuarter;

  double get bpm => 60000000 / microsPerQuarter;
}

class TimeSignatureChange {
  const TimeSignatureChange(this.tick, this.numerator, this.denominatorPower);

  final int tick;
  final int numerator;

  /// Denominator is 2^denominatorPower (2 -> quarter, 3 -> eighth).
  final int denominatorPower;

  int get denominator => 1 << denominatorPower;
}

/// The whole document: timing, tempo/time-signature maps and tracks.
class Project {
  const Project({
    required this.name,
    required this.ppq,
    required this.tempos,
    required this.timeSignatures,
    required this.tracks,
    this.conductorExtras = const [],
  });

  factory Project.empty() => Project(
    name: 'Untitled',
    ppq: 480,
    tempos: const [TempoChange(0, 500000)],
    timeSignatures: const [TimeSignatureChange(0, 4, 2)],
    tracks: [Track.create(name: 'Track 1')],
  );

  final String name;

  /// Ticks per quarter note.
  final int ppq;

  /// Sorted by tick; always has an entry at tick 0.
  final List<TempoChange> tempos;

  /// Sorted by tick; always has an entry at tick 0.
  final List<TimeSignatureChange> timeSignatures;
  final List<Track> tracks;

  /// Meta events from tracks without notes (markers, key signature...).
  final List<MidiEvent> conductorExtras;

  Project copyWith({
    String? name,
    List<TempoChange>? tempos,
    List<TimeSignatureChange>? timeSignatures,
    List<Track>? tracks,
    List<MidiEvent>? conductorExtras,
  }) => Project(
    name: name ?? this.name,
    ppq: ppq,
    tempos: tempos ?? this.tempos,
    timeSignatures: timeSignatures ?? this.timeSignatures,
    tracks: tracks ?? this.tracks,
    conductorExtras: conductorExtras ?? this.conductorExtras,
  );

  Track? trackById(int? id) {
    for (final t in tracks) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Tick at which the last note ends.
  int get endTick {
    var end = 0;
    for (final t in tracks) {
      for (final n in t.notes) {
        if (n.end > end) end = n.end;
      }
    }
    return end;
  }

  int get ticksPerBar {
    final s = timeSignatures.first;
    return ppq * 4 ~/ s.denominator * s.numerator;
  }
}
