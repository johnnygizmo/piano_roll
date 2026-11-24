import 'project.dart';

/// Converts between ticks and wall-clock time using the tempo map.
class TempoMap {
  TempoMap(this.ppq, List<TempoChange> tempos) {
    final sorted = [...tempos]..sort((a, b) => a.tick.compareTo(b.tick));
    if (sorted.isEmpty || sorted.first.tick != 0) {
      sorted.insert(0, const TempoChange(0, 500000));
    }
    var micros = 0.0;
    for (var i = 0; i < sorted.length; i++) {
      if (i > 0) {
        final prev = sorted[i - 1];
        micros += (sorted[i].tick - prev.tick) * prev.microsPerQuarter / ppq;
      }
      _ticks.add(sorted[i].tick);
      _micros.add(micros);
      _rates.add(sorted[i].microsPerQuarter);
    }
  }

  final int ppq;
  final _ticks = <int>[];
  final _micros = <double>[];
  final _rates = <int>[];

  double microsAtTick(int tick) {
    final i = _segmentForTick(tick);
    return _micros[i] + (tick - _ticks[i]) * _rates[i] / ppq;
  }

  int tickAtMicros(double micros) {
    var i = 0;
    for (var s = 0; s < _micros.length; s++) {
      if (_micros[s] <= micros) i = s;
    }
    return (_ticks[i] + (micros - _micros[i]) * ppq / _rates[i]).round();
  }

  int _segmentForTick(int tick) {
    var i = 0;
    for (var s = 0; s < _ticks.length; s++) {
      if (_ticks[s] <= tick) i = s;
    }
    return i;
  }
}
