import '../midi/midi_events.dart';
import 'note.dart';

/// One editable track: notes on a single MIDI channel.
class Track {
  const Track({
    required this.id,
    required this.name,
    this.channel = 0,
    this.program = 0,
    this.notes = const [],
    this.extras = const [],
  });

  factory Track.create({
    required String name,
    int channel = 0,
    int program = 0,
    List<Note> notes = const [],
    List<MidiEvent> extras = const [],
  }) => Track(
    id: _nextId++,
    name: name,
    channel: channel,
    program: program,
    notes: notes,
    extras: extras,
  );

  static int _nextId = 1;

  final int id;
  final String name;

  /// 0-15 (displayed as 1-16). Channel 9 is General MIDI percussion.
  final int channel;

  /// General MIDI program 0-127.
  final int program;
  final List<Note> notes;

  /// Events the editor does not model (controllers, pitch bend, key
  /// signature, sysex...). Kept so import -> export does not lose them.
  final List<MidiEvent> extras;

  bool get isDrum => channel == 9;

  Track copyWith({
    String? name,
    int? channel,
    int? program,
    List<Note>? notes,
    List<MidiEvent>? extras,
  }) => Track(
    id: id,
    name: name ?? this.name,
    channel: channel ?? this.channel,
    program: program ?? this.program,
    notes: notes ?? this.notes,
    extras: extras ?? this.extras,
  );
}
