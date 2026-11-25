/// A chord candidate reported by a detector such as Tonal's `Chord.detect`.
class DetectedChord {
  const DetectedChord(this.tonic, this.suffix, [this.bass]);

  /// Root note name, e.g. `Bb` or `F#`.
  final String tonic;

  /// Chord symbol suffix, e.g. `m7`, `maj7`, `7`, `dim`; `M` or empty for a
  /// major triad.
  final String suffix;

  /// Bass note name for slash chords.
  final String? bass;
}

/// Names the chords that could be formed by [noteNames] (bass note first),
/// best match first.
typedef ChordDetector = List<DetectedChord> Function(List<String> noteNames);

/// A chord as MusicXML `<harmony>` needs it.
class ChordSymbol {
  const ChordSymbol({
    required this.rootStep,
    required this.rootAlter,
    required this.kind,
    this.bassStep,
    this.bassAlter = 0,
  });

  final String rootStep;
  final int rootAlter;

  /// MusicXML kind value, e.g. `minor-seventh`.
  final String kind;
  final String? bassStep;
  final int bassAlter;

  @override
  bool operator ==(Object other) =>
      other is ChordSymbol &&
      other.rootStep == rootStep &&
      other.rootAlter == rootAlter &&
      other.kind == kind &&
      other.bassStep == bassStep &&
      other.bassAlter == bassAlter;

  @override
  int get hashCode =>
      Object.hash(rootStep, rootAlter, kind, bassStep, bassAlter);
}

/// Chord suffixes (as used by Tonal) that MusicXML and the sheet music
/// renderer can express.
const _kinds = <String, String>{
  '': 'major',
  'M': 'major',
  'maj': 'major',
  'm': 'minor',
  'dim': 'diminished',
  'aug': 'augmented',
  '7': 'dominant',
  'maj7': 'major-seventh',
  'm7': 'minor-seventh',
  'dim7': 'diminished-seventh',
  'm7b5': 'half-diminished',
  '7#5': 'augmented-seventh',
  'm/ma7': 'major-minor',
  '6': 'major-sixth',
  'm6': 'minor-sixth',
  '9': 'dominant-ninth',
  'maj9': 'major-ninth',
  'm9': 'minor-ninth',
  '11': 'dominant-11th',
  'm11': 'minor-11th',
  '13': 'dominant-13th',
  'maj13': 'major-13th',
  'm13': 'minor-13th',
  'sus2': 'suspended-second',
  'sus4': 'suspended-fourth',
  '5': 'power',
};

(String, int)? _parseNote(String name) {
  final m = RegExp(r'^([A-G])(#*|b*)$').firstMatch(name);
  if (m == null) return null;
  final accidental = m.group(2)!;
  return (
    m.group(1)!,
    accidental.startsWith('#') ? accidental.length : -accidental.length,
  );
}

/// The first of [candidates] that can be written as a chord symbol.
ChordSymbol? firstChordSymbol(Iterable<DetectedChord> candidates) {
  for (final c in candidates) {
    final kind = _kinds[c.suffix];
    final root = _parseNote(c.tonic);
    if (kind == null || root == null) continue;
    final bass = c.bass == null ? null : _parseNote(c.bass!);
    if (c.bass != null && bass == null) continue;
    return ChordSymbol(
      rootStep: root.$1,
      rootAlter: root.$2,
      kind: kind,
      bassStep: bass?.$1,
      bassAlter: bass?.$2 ?? 0,
    );
  }
  return null;
}
