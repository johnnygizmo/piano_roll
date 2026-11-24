/// A named musical interval used for transposing.
class Interval {
  const Interval(this.label, this.semitones);

  final String label;
  final int semitones;
}

/// Minor 2nd up to the octave (the tritone is labelled TT).
const transposeIntervals = <Interval>[
  Interval('m2', 1),
  Interval('M2', 2),
  Interval('m3', 3),
  Interval('M3', 4),
  Interval('P4', 5),
  Interval('TT', 6),
  Interval('P5', 7),
  Interval('m6', 8),
  Interval('M6', 9),
  Interval('m7', 10),
  Interval('M7', 11),
  Interval('Octave', 12),
];
