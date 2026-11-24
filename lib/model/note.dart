/// A single note. Immutable; edits produce new instances with the same [id].
class Note {
  const Note({
    required this.id,
    required this.pitch,
    required this.start,
    required this.duration,
    this.velocity = 100,
  });

  /// Creates a note with a fresh unique id.
  factory Note.create({
    required int pitch,
    required int start,
    required int duration,
    int velocity = 100,
  }) => Note(
    id: _nextId++,
    pitch: pitch,
    start: start,
    duration: duration,
    velocity: velocity,
  );

  static int _nextId = 1;

  final int id;

  /// MIDI note number, 0-127 (60 = middle C).
  final int pitch;

  /// Start position in ticks.
  final int start;

  /// Length in ticks (always >= 1).
  final int duration;

  /// 1-127.
  final int velocity;

  int get end => start + duration;

  Note copyWith({int? pitch, int? start, int? duration, int? velocity}) => Note(
    id: id,
    pitch: pitch ?? this.pitch,
    start: start ?? this.start,
    duration: duration ?? this.duration,
    velocity: velocity ?? this.velocity,
  );

  /// Same note data under a new id (used by duplicate/paste).
  Note clone({int? start, int? pitch}) => Note.create(
    pitch: pitch ?? this.pitch,
    start: start ?? this.start,
    duration: duration,
    velocity: velocity,
  );
}
