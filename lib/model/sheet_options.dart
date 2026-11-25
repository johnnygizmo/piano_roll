/// Which optional items appear on the sheet music.
class SheetOptions {
  const SheetOptions({
    this.title = true,
    this.chords = true,
    this.staffLabels = true,
    this.tempo = true,
  });

  final bool title;

  /// Chord symbols detected from the notes.
  final bool chords;

  /// Instrument names at the start of each staff.
  final bool staffLabels;

  /// The tempo mark above the first bar.
  final bool tempo;

  SheetOptions copyWith({
    bool? title,
    bool? chords,
    bool? staffLabels,
    bool? tempo,
  }) => SheetOptions(
    title: title ?? this.title,
    chords: chords ?? this.chords,
    staffLabels: staffLabels ?? this.staffLabels,
    tempo: tempo ?? this.tempo,
  );
}
