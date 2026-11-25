/// How a General MIDI instrument is notated.
enum StaffLayout {
  /// Treble and bass staves joined (keyboards, harp).
  grand,
  treble,
  bass,
  alto,

  /// Chosen from the track's note range (ensembles, pads, effects).
  auto,
}

/// General MIDI program ranges (inclusive, 0-based) and their staff layout.
/// Programs not listed fall back to [StaffLayout.auto].
const _layoutTable = <(int, int, StaffLayout)>[
  (0, 7, StaffLayout.grand), // pianos
  (8, 15, StaffLayout.treble), // chromatic percussion
  (16, 23, StaffLayout.grand), // organs, accordion, harmonica
  (24, 31, StaffLayout.treble), // guitars
  (32, 39, StaffLayout.bass), // basses
  (40, 40, StaffLayout.treble), // violin
  (41, 41, StaffLayout.alto), // viola
  (42, 43, StaffLayout.bass), // cello, contrabass
  (44, 45, StaffLayout.treble), // tremolo strings, pizzicato
  (46, 46, StaffLayout.grand), // harp
  (47, 47, StaffLayout.bass), // timpani
  (52, 54, StaffLayout.treble), // choir, voice
  (56, 56, StaffLayout.treble), // trumpet
  (57, 58, StaffLayout.bass), // trombone, tuba
  (59, 60, StaffLayout.treble), // muted trumpet, French horn
  (64, 69, StaffLayout.treble), // saxophones, oboe, English horn
  (70, 70, StaffLayout.bass), // bassoon
  (71, 79, StaffLayout.treble), // clarinet, pipes
  (80, 87, StaffLayout.treble), // synth leads
  (104, 111, StaffLayout.treble), // ethnic
];

StaffLayout staffLayoutForProgram(int program) {
  for (final (from, to, layout) in _layoutTable) {
    if (program >= from && program <= to) return layout;
  }
  return StaffLayout.auto;
}
