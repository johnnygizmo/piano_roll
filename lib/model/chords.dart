import 'note.dart';

/// Quality of the triad: fixes the 3rd and 5th.
enum ChordQuality {
  major('Major', [4, 7]),
  minor('Minor', [3, 7]),
  augmented('Aug', [4, 8]),
  diminished('Dim', [3, 6]);

  const ChordQuality(this.label, this.triad);

  final String label;

  /// Semitones above the root for the 3rd and 5th.
  final List<int> triad;
}

enum _Flavor { minor, major, dominant }

/// How far the chord stacks above the triad, and the flavour of its 7th.
enum ChordExtension {
  triad('Triad', 0, null),
  minor7('m7', 7, _Flavor.minor),
  major7('M7', 7, _Flavor.major),
  dominant7('7', 7, _Flavor.dominant),
  minor9('m9', 9, _Flavor.minor),
  major9('M9', 9, _Flavor.major),
  dominant9('9', 9, _Flavor.dominant),
  minor11('m11', 11, _Flavor.minor),
  major11('M11', 11, _Flavor.major),
  dominant11('11', 11, _Flavor.dominant),
  minor13('m13', 13, _Flavor.minor),
  major13('M13', 13, _Flavor.major),
  dominant13('13', 13, _Flavor.dominant);

  const ChordExtension(this.label, this.extent, this._flavor);

  final String label;

  /// Highest chord degree included: 0 (triad), 7, 9, 11 or 13.
  final int extent;
  final _Flavor? _flavor;
}

/// Semitone offsets above the root (excluding the root itself), ascending.
///
/// The prefix of the extension only chooses the 7th: `m` = minor 7th,
/// `M` = major 7th, none = dominant 7th (a diminished 7th for diminished
/// chords). 9th, 11th and 13th are always natural. A 13th chord omits the 11th.
List<int> chordIntervals(ChordQuality quality, ChordExtension extension) {
  final intervals = [...quality.triad];
  final flavor = extension._flavor;
  if (flavor == null) return intervals;

  intervals.add(switch (flavor) {
    _Flavor.minor => 10,
    _Flavor.major => 11,
    _Flavor.dominant => quality == ChordQuality.diminished ? 9 : 10,
  });
  if (extension.extent >= 9) intervals.add(14);
  if (extension.extent == 11) intervals.add(17);
  if (extension.extent == 13) intervals.add(21);
  return intervals;
}

/// New notes of a root-position chord built on [root], sharing its start,
/// duration and velocity. The root itself is not included; tones above
/// MIDI note 127 are dropped.
List<Note> buildChord(
  Note root,
  ChordQuality quality,
  ChordExtension extension,
) => [
  for (final interval in chordIntervals(quality, extension))
    if (root.pitch + interval <= 127)
      Note.create(
        pitch: root.pitch + interval,
        start: root.start,
        duration: root.duration,
        velocity: root.velocity,
      ),
];
