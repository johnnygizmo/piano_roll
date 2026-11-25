import 'dart:math' as math;

import 'chord_symbol.dart';
import 'note.dart';
import 'project.dart';
import 'sheet_options.dart';
import 'staff_types.dart';
import 'track.dart';

/// Converts a [Project] to uncompressed MusicXML (partwise) for rendering
/// with OpenSheetMusicDisplay.
///
/// Notation is an approximation of the performance:
/// * times are quantised to 32nd notes (triplets are not detected);
/// * each staff is one voice - overlapping notes are cut at the next onset;
/// * notes crossing a barline are split and tied;
/// * pitches are spelled to suit the key signature;
/// * the staff type (grand, treble, bass, alto) follows the track's General
///   MIDI instrument, see [staffLayoutForProgram];
/// * chord symbols (when [SheetOptions.chords] is on and a [chordDetector] is
///   given) are guessed per beat from the notes of all pitched tracks and
///   shown above the first track.
///
/// Tracks without notes are skipped. Returns null if no track has notes.
String? projectToMusicXml(
  Project project, {
  Set<int>? trackIds,
  SheetOptions options = const SheetOptions(),
  ChordDetector? chordDetector,
}) {
  final tracks = [
    for (final t in project.tracks)
      if (t.notes.isNotEmpty && (trackIds == null || trackIds.contains(t.id)))
        t,
  ];
  if (tracks.isEmpty) return null;
  return _Writer(project, tracks, options, chordDetector).write();
}

/// Quantisation unit: 8 divisions per quarter note (a 32nd note).
const _unitsPerQuarter = 8;

/// Note lengths in units that have a single (possibly dotted) notehead,
/// largest first, with their MusicXML type and dot count.
const _lengths = <(int, String, int)>[
  (32, 'whole', 0),
  (24, 'half', 1),
  (16, 'half', 0),
  (12, 'quarter', 1),
  (8, 'quarter', 0),
  (6, 'eighth', 1),
  (4, 'eighth', 0),
  (3, '16th', 1),
  (2, '16th', 0),
  (1, '32nd', 0),
];

const _letters = 'FCGDAEB';

/// Spells [pitch] (MIDI note) for a key with [fifths] sharps (negative for
/// flats). Pitch classes sit on the line of fifths (F=-1, C=0, G=1, ...);
/// of the possible spellings the one nearest the key's own notes wins.
(String, int, int) _spell(int pitch, int fifths) {
  final base = (pitch % 12 * 7) % 12;
  final center = fifths + 2;
  var best = base;
  var bestDistance = 1 << 30;
  for (var k = base - 24; k <= base + 24; k += 12) {
    final d = (k - center).abs();
    if (d < bestDistance || (d == bestDistance && k > best)) {
      best = k;
      bestDistance = d;
    }
  }
  final alter = ((best + 1) / 7).floor();
  final step = _letters[(best + 1) % 7];
  return (step, alter, (pitch - alter) ~/ 12 - 1);
}

/// Pitch at or above which notes go to the upper (treble) staff.
const _splitPitch = 60;

/// Range (semitones) from which a pitched track is written on a grand staff.
const _grandStaffRange = 17;

class _Measure {
  _Measure(this.start, this.length, this.sig, this.newSig, this.key);

  final int start;
  final int length;
  final TimeSignatureChange sig;
  final bool newSig;
  final KeySignatureChange key;
  bool keyChanged = false;

  int get end => start + length;
}

/// A chord (or rest when [pitches] is empty) spanning [start]..[end] units.
class _Event {
  _Event(this.start, this.end, this.pitches);

  final int start;
  final int end;
  final List<int> pitches;
}

enum _Clef { treble, bass, alto, percussion }

class _Staff {
  _Staff(this.clef, this.notes);

  final _Clef clef;
  final List<Note> notes;
}

class _Writer {
  _Writer(this.project, this.tracks, this.options, this.chordDetector);

  final Project project;
  final List<Track> tracks;
  final SheetOptions options;
  final ChordDetector? chordDetector;
  final _out = StringBuffer();

  /// Chord changes per measure index: (offset in units, symbol).
  var _chords = <int, List<(int, ChordSymbol)>>{};

  int _unit(int tick) => (tick * _unitsPerQuarter / project.ppq).round();

  int _noteEnd(Note n) => math.max(_unit(n.end), _unit(n.start) + 1);

  /// End of the last onset's chord in one voice. Longer notes that overlap a
  /// later onset are cut there, so only the last chord can extend the piece.
  int _contentEnd(List<Note> notes) {
    if (notes.isEmpty) return 0;
    final lastStart = notes.map((n) => _unit(n.start)).reduce(math.max);
    return notes
        .where((n) => _unit(n.start) == lastStart)
        .map(_noteEnd)
        .reduce(math.max);
  }

  String write() {
    final total = tracks
        .expand(_staffs)
        .map((s) => _contentEnd(s.notes))
        .reduce(math.max);
    final measures = _measures(total);
    _chords = _detectChords(measures);

    _out.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    _out.writeln('<score-partwise version="3.1">');
    if (options.title) {
      _out.writeln(
        '<work><work-title>${_esc(project.name)}</work-title></work>',
      );
    }
    _out.writeln('<part-list>');
    for (var i = 0; i < tracks.length; i++) {
      final name = tracks[i].name.trim().isEmpty
          ? 'Track ${i + 1}'
          : tracks[i].name;
      _out.writeln(
        '<score-part id="P${i + 1}"><part-name>${_esc(name)}</part-name>'
        '</score-part>',
      );
    }
    _out.writeln('</part-list>');

    for (var i = 0; i < tracks.length; i++) {
      _writePart(i, tracks[i], measures);
    }
    _out.writeln('</score-partwise>');
    return _out.toString();
  }

  List<_Measure> _measures(int total) {
    final sigs = project.timeSignatures;
    final measures = <_Measure>[];
    var pos = 0;
    for (var i = 0; i < sigs.length; i++) {
      final sig = sigs[i];
      final length = math.max(
        1,
        sig.numerator * _unitsPerQuarter * 4 ~/ sig.denominator,
      );
      final segEnd = i + 1 < sigs.length ? _unit(sigs[i + 1].tick) : null;
      var first = true;
      while (segEnd == null
          ? (pos < total || measures.isEmpty)
          : pos < segEnd) {
        measures.add(_Measure(pos, length, sig, first, _keyAt(pos)));
        first = false;
        pos += length;
      }
    }
    for (var i = 1; i < measures.length; i++) {
      measures[i].keyChanged = measures[i].key != measures[i - 1].key;
    }
    return measures;
  }

  KeySignatureChange _keyAt(int unit) {
    var key = project.keySignatures.first;
    for (final k in project.keySignatures) {
      if (_unit(k.tick) <= unit) key = k;
    }
    return key;
  }

  List<_Staff> _staffs(Track track) {
    if (track.isDrum) return [_Staff(_Clef.percussion, track.notes)];
    final layout = staffLayoutForProgram(track.program);
    List<Note> where(bool Function(Note) test) => [
      for (final n in track.notes)
        if (test(n)) n,
    ];
    switch (layout) {
      case StaffLayout.grand:
        return [
          _Staff(_Clef.treble, where((n) => n.pitch >= _splitPitch)),
          _Staff(_Clef.bass, where((n) => n.pitch < _splitPitch)),
        ];
      case StaffLayout.treble:
        return [_Staff(_Clef.treble, track.notes)];
      case StaffLayout.bass:
        return [_Staff(_Clef.bass, track.notes)];
      case StaffLayout.alto:
        return [_Staff(_Clef.alto, track.notes)];
      case StaffLayout.auto:
        break;
    }
    final pitches = track.notes.map((n) => n.pitch).toList()..sort();
    final low = pitches.first;
    final high = pitches.last;
    if (low < _splitPitch &&
        high >= _splitPitch &&
        high - low >= _grandStaffRange) {
      return [
        _Staff(_Clef.treble, where((n) => n.pitch >= _splitPitch)),
        _Staff(_Clef.bass, where((n) => n.pitch < _splitPitch)),
      ];
    }
    final median = pitches[pitches.length ~/ 2];
    return [
      _Staff(median >= _splitPitch ? _Clef.treble : _Clef.bass, track.notes),
    ];
  }

  /// One voice: chords at each onset, cut at the next onset, with rests in
  /// the gaps, covering 0..[total].
  List<_Event> _timeline(List<Note> notes, int total) {
    final byStart = <int, List<Note>>{};
    for (final n in notes) {
      byStart.putIfAbsent(_unit(n.start), () => []).add(n);
    }
    final starts = byStart.keys.toList()..sort();
    final events = <_Event>[];
    var pos = 0;
    for (var i = 0; i < starts.length; i++) {
      final start = starts[i];
      final group = byStart[start]!;
      if (start > pos) events.add(_Event(pos, start, const []));
      var end = group.map(_noteEnd).reduce(math.max);
      if (i + 1 < starts.length) end = math.min(end, starts[i + 1]);
      events.add(
        _Event(start, end, ({for (final n in group) n.pitch}.toList()..sort())),
      );
      pos = end;
    }
    if (pos < total) events.add(_Event(pos, total, const []));
    return events;
  }

  void _writePart(int index, Track track, List<_Measure> measures) {
    final staffs = _staffs(track);
    final total = measures.last.end;
    final timelines = [for (final s in staffs) _timeline(s.notes, total)];

    _out.writeln('<part id="P${index + 1}">');
    for (var m = 0; m < measures.length; m++) {
      final measure = measures[m];
      _out.writeln('<measure number="${m + 1}">');
      if (m == 0 || measure.newSig || measure.keyChanged) {
        _writeAttributes(staffs, measure, first: m == 0);
      }
      if (m == 0 && index == 0 && options.tempo) _writeTempo();
      if (index == 0) _writeHarmony(m);
      for (var s = 0; s < staffs.length; s++) {
        if (s > 0) {
          _out.writeln(
            '<backup><duration>${measure.length}</duration></backup>',
          );
        }
        _writeStaffMeasure(
          timelines[s],
          measure,
          s + 1,
          staffs.length > 1,
          track.isDrum,
        );
      }
      _out.writeln('</measure>');
    }
    _out.writeln('</part>');
  }

  void _writeAttributes(
    List<_Staff> staffs,
    _Measure measure, {
    required bool first,
  }) {
    _out.writeln('<attributes>');
    if (first) {
      _out.writeln('<divisions>$_unitsPerQuarter</divisions>');
    }
    if (first || measure.keyChanged) {
      _out.writeln(
        '<key><fifths>${measure.key.sharps}</fifths>'
        '<mode>${measure.key.minor ? 'minor' : 'major'}</mode></key>',
      );
    }
    if (first || measure.newSig) {
      _out.writeln(
        '<time><beats>${measure.sig.numerator}</beats>'
        '<beat-type>${measure.sig.denominator}</beat-type></time>',
      );
    }
    if (first) {
      if (staffs.length > 1) _out.writeln('<staves>${staffs.length}</staves>');
      for (var i = 0; i < staffs.length; i++) {
        final number = staffs.length > 1 ? ' number="${i + 1}"' : '';
        final clef = switch (staffs[i].clef) {
          _Clef.treble => '<sign>G</sign><line>2</line>',
          _Clef.bass => '<sign>F</sign><line>4</line>',
          _Clef.alto => '<sign>C</sign><line>3</line>',
          _Clef.percussion => '<sign>percussion</sign><line>2</line>',
        };
        _out.writeln('<clef$number>$clef</clef>');
      }
    }
    _out.writeln('</attributes>');
  }

  void _writeHarmony(int measure) {
    final changes = _chords[measure];
    if (changes == null) return;
    var pos = 0;
    for (final (offset, chord) in changes) {
      if (offset > pos) {
        _out.writeln('<forward><duration>${offset - pos}</duration></forward>');
        pos = offset;
      }
      final bass = chord.bassStep == null
          ? ''
          : '<bass><bass-step>${chord.bassStep}</bass-step>'
                '${chord.bassAlter != 0 ? '<bass-alter>${chord.bassAlter}</bass-alter>' : ''}'
                '</bass>';
      _out.writeln(
        '<harmony><root><root-step>${chord.rootStep}</root-step>'
        '${chord.rootAlter != 0 ? '<root-alter>${chord.rootAlter}</root-alter>' : ''}'
        '</root><kind>${chord.kind}</kind>$bass</harmony>',
      );
    }
    if (pos > 0) _out.writeln('<backup><duration>$pos</duration></backup>');
  }

  /// Guesses one chord per beat from the notes sounding for at least half of
  /// it, and keeps only the beats where the chord changes.
  Map<int, List<(int, ChordSymbol)>> _detectChords(List<_Measure> measures) {
    final detector = chordDetector;
    if (!options.chords || detector == null) return {};
    final notes = [
      for (final t in tracks)
        if (!t.isDrum) ...t.notes,
    ];
    final result = <int, List<(int, ChordSymbol)>>{};
    ChordSymbol? previous;
    for (var m = 0; m < measures.length; m++) {
      final measure = measures[m];
      final sig = measure.sig;
      var beat = _unitsPerQuarter * 4 ~/ sig.denominator;
      if (sig.denominator >= 8 && sig.numerator > 3 && sig.numerator % 3 == 0) {
        beat *= 3;
      }
      for (var offset = 0; offset < measure.length; offset += beat) {
        final from = measure.start + offset;
        final to = math.min(from + beat, measure.end);
        final pitches = <int>{};
        for (final n in notes) {
          final overlap =
              math.min(_noteEnd(n), to) - math.max(_unit(n.start), from);
          if (overlap * 2 >= to - from) pitches.add(n.pitch);
        }
        if (pitches.map((p) => p % 12).toSet().length < 3) continue;

        final sorted = pitches.toList()..sort();
        final seen = <int>{};
        final names = [
          for (final p in sorted)
            if (seen.add(p % 12)) _noteName(p, measure.key.sharps),
        ];
        final chord = firstChordSymbol(detector(names));
        if (chord == null || chord == previous) continue;
        previous = chord;
        (result[m] ??= []).add((offset, chord));
      }
    }
    return result;
  }

  static String _noteName(int pitch, int fifths) {
    final (step, alter, _) = _spell(pitch, fifths);
    return step + (alter >= 0 ? '#' * alter : 'b' * -alter);
  }

  void _writeTempo() {
    final bpm = project.tempos.first.bpm.round();
    _out.writeln(
      '<direction placement="above"><direction-type><metronome>'
      '<beat-unit>quarter</beat-unit><per-minute>$bpm</per-minute>'
      '</metronome></direction-type><sound tempo="$bpm"/></direction>',
    );
  }

  void _writeStaffMeasure(
    List<_Event> timeline,
    _Measure measure,
    int staff,
    bool multiStaff,
    bool drum,
  ) {
    final voice = staff;
    for (final event in timeline) {
      if (event.end <= measure.start || event.start >= measure.end) continue;
      var pos = math.max(event.start, measure.start);
      final end = math.min(event.end, measure.end);

      if (event.pitches.isEmpty && pos == measure.start && end == measure.end) {
        _writeNote(
          const [],
          measure.length,
          '',
          0,
          voice: voice,
          drum: drum,
          fifths: measure.key.sharps,
          staff: multiStaff ? staff : null,
          wholeMeasure: true,
        );
        continue;
      }
      while (pos < end) {
        final (length, type, dots) = _lengths.firstWhere(
          (l) => l.$1 <= end - pos,
        );
        _writeNote(
          event.pitches,
          length,
          type,
          dots,
          voice: voice,
          drum: drum,
          fifths: measure.key.sharps,
          staff: multiStaff ? staff : null,
          tieStop: pos > event.start,
          tieStart: pos + length < event.end,
        );
        pos += length;
      }
    }
  }

  void _writeNote(
    List<int> pitches,
    int length,
    String type,
    int dots, {
    required int voice,
    required bool drum,
    required int fifths,
    int? staff,
    bool tieStop = false,
    bool tieStart = false,
    bool wholeMeasure = false,
  }) {
    final ties = pitches.isNotEmpty;
    final head = StringBuffer()
      ..write('<duration>$length</duration>')
      ..write(ties && tieStop ? '<tie type="stop"/>' : '')
      ..write(ties && tieStart ? '<tie type="start"/>' : '')
      ..write('<voice>$voice</voice>');
    if (!wholeMeasure) {
      head.write('<type>$type</type>${'<dot/>' * dots}');
    }
    final tail = StringBuffer();
    if (staff != null) tail.write('<staff>$staff</staff>');
    if (ties && (tieStop || tieStart)) {
      tail
        ..write('<notations>')
        ..write(tieStop ? '<tied type="stop"/>' : '')
        ..write(tieStart ? '<tied type="start"/>' : '')
        ..write('</notations>');
    }

    if (pitches.isEmpty) {
      _out.writeln(
        '<note><rest${wholeMeasure ? ' measure="yes"' : ''}/>$head$tail</note>',
      );
      return;
    }

    if (drum) {
      final seen = <(String, int, bool)>{};
      for (final pitch in pitches) {
        final pos = _drumPosition(pitch);
        if (!seen.add(pos)) continue;
        final (step, octave, cross) = pos;
        _out.writeln(
          '<note>${seen.length > 1 ? '<chord/>' : ''}<unpitched>'
          '<display-step>$step</display-step>'
          '<display-octave>$octave</display-octave></unpitched>$head'
          '${cross ? '<notehead>x</notehead>' : ''}$tail</note>',
        );
      }
      return;
    }
    for (var i = 0; i < pitches.length; i++) {
      final (step, alter, octave) = _spell(pitches[i], fifths);
      _out.writeln(
        '<note>${i > 0 ? '<chord/>' : ''}<pitch><step>$step</step>'
        '${alter != 0 ? '<alter>$alter</alter>' : ''}'
        '<octave>$octave</octave></pitch>$head$tail</note>',
      );
    }
  }
}

/// Staff position (step, octave, x notehead) of a General MIDI drum note.
(String, int, bool) _drumPosition(int pitch) => switch (pitch) {
  35 || 36 => ('F', 4, false),
  37 || 38 || 39 || 40 => ('C', 5, false),
  41 || 43 => ('A', 4, false),
  45 || 47 => ('D', 5, false),
  48 || 50 => ('E', 5, false),
  42 || 44 || 46 => ('G', 5, true),
  49 || 51 || 52 || 53 || 55 || 57 || 59 => ('A', 5, true),
  _ => ('B', 4, false),
};
String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
