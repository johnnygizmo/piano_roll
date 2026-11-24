import 'project.dart';

/// Grid resolution for snapping and note defaults.
enum Snap {
  quarter('1/4', 4, false),
  eighth('1/8', 8, false),
  sixteenth('1/16', 16, false),
  thirtySecond('1/32', 32, false),
  eighthTriplet('1/8T', 8, true),
  sixteenthTriplet('1/16T', 16, true),
  off('Off', 0, false);

  const Snap(this.label, this.division, this.triplet);

  final String label;

  /// Notes per whole note (0 = no snapping).
  final int division;
  final bool triplet;

  /// Snap interval in ticks; 1 when snapping is off.
  int ticks(int ppq) {
    if (division == 0) return 1;
    final base = ppq * 4 ~/ division;
    return triplet ? base * 2 ~/ 3 : base;
  }

  int round(int tick, int ppq) {
    final s = ticks(ppq);
    return (tick / s).round() * s;
  }

  int floor(int tick, int ppq) {
    final s = ticks(ppq);
    return (tick ~/ s) * s;
  }
}

class GridLine {
  const GridLine(this.tick, this.isBar, this.barNumber, this.beatTicks);

  final int tick;
  final bool isBar;

  /// 1-based bar number (only meaningful when [isBar]).
  final int barNumber;
  final int beatTicks;
}

/// Beat and bar lines between [from] and [to], honouring time-signature
/// changes (assumed to fall on bar boundaries).
Iterable<GridLine> gridLines(Project p, int from, int to) sync* {
  final sigs = p.timeSignatures;
  var barsBefore = 0;
  for (var i = 0; i < sigs.length; i++) {
    final sig = sigs[i];
    final beatTicks = p.ppq * 4 ~/ sig.denominator;
    final barTicks = beatTicks * sig.numerator;
    final segEnd = i + 1 < sigs.length ? sigs[i + 1].tick : null;

    if (segEnd == null || segEnd > from) {
      final lo = from > sig.tick ? from : sig.tick;
      var beat = (lo - sig.tick) ~/ beatTicks;
      while (true) {
        final tick = sig.tick + beat * beatTicks;
        if (tick > to || (segEnd != null && tick >= segEnd)) break;
        final isBar = beat % sig.numerator == 0;
        yield GridLine(
          tick,
          isBar,
          barsBefore + beat ~/ sig.numerator + 1,
          beatTicks,
        );
        beat++;
      }
    }
    if (segEnd != null) barsBefore += (segEnd - sig.tick) ~/ barTicks;
  }
}
