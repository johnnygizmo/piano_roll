import 'package:flutter_test/flutter_test.dart';
import 'package:piano_roll/model/chord_symbol.dart';
import 'package:piano_roll/model/musicxml.dart';
import 'package:piano_roll/model/note.dart';
import 'package:piano_roll/model/project.dart';
import 'package:piano_roll/model/sheet_options.dart';
import 'package:piano_roll/model/track.dart';

Project _project(List<Note> notes, {int ppq = 480, int program = 0}) => Project(
  name: 'A & B',
  ppq: ppq,
  tempos: const [TempoChange(0, 500000)],
  timeSignatures: const [TimeSignatureChange(0, 4, 2)],
  tracks: [Track.create(name: 'Lead', program: program, notes: notes)],
);

List<String> _matches(String xml, String pattern) =>
    RegExp(pattern).allMatches(xml).map((m) => m.group(1)!).toList();

void main() {
  test('returns null when nothing has notes', () {
    expect(projectToMusicXml(_project(const [])), isNull);
  });

  test('every measure of every staff adds up to the bar length', () {
    final xml = projectToMusicXml(
      _project([
        Note.create(pitch: 72, start: 0, duration: 480),
        Note.create(pitch: 76, start: 0, duration: 480),
        // Crosses the barline (bar = 1920 ticks) and has an odd length.
        Note.create(pitch: 40, start: 1700, duration: 700),
        Note.create(pitch: 64, start: 3900, duration: 120),
      ]),
    )!;
    expect(xml, contains('<staves>2</staves>'));
    expect(xml, contains('<chord/>'));
    expect(xml, contains('<tie type="start"/>'));
    expect(xml, contains('<tie type="stop"/>'));
    expect(xml, contains('A &amp; B'));

    final measures = xml.split('<measure ').skip(1);
    expect(measures, hasLength(3));
    for (final m in measures) {
      final staff1 = <int>[];
      final staff2 = <int>[];
      for (final note in m.split('<note>').skip(1)) {
        if (note.contains('<chord/>')) continue;
        final d = int.parse(
          RegExp(r'<duration>(\d+)</duration>').firstMatch(note)!.group(1)!,
        );
        (note.contains('<staff>2</staff>') ? staff2 : staff1).add(d);
      }
      expect(staff1.fold(0, (a, b) => a + b), 32);
      expect(staff2.fold(0, (a, b) => a + b), 32);
    }
  });

  test('empty bars become whole-measure rests; overlaps are cut', () {
    final xml = projectToMusicXml(
      _project([
        Note.create(pitch: 60, start: 1920, duration: 4000),
        Note.create(pitch: 62, start: 2400, duration: 480),
      ], program: 40),
    )!;
    expect(_matches(xml, r'(<rest measure="yes"/>)'), hasLength(1));
    // The long C is cut at the D (a quarter) and then D is notated.
    expect(xml, contains('<step>D</step>'));
  });

  test('staff type follows the General MIDI instrument', () {
    String xmlFor(int program, int pitch) => projectToMusicXml(
      Project(
        name: 'x',
        ppq: 480,
        tempos: const [TempoChange(0, 500000)],
        timeSignatures: const [TimeSignatureChange(0, 4, 2)],
        tracks: [
          Track.create(
            name: 't',
            program: program,
            notes: [Note.create(pitch: pitch, start: 0, duration: 480)],
          ),
        ],
      ),
    )!;

    // A single high note on a piano still gets a grand staff.
    final piano = xmlFor(0, 72);
    expect(piano, contains('<staves>2</staves>'));
    expect(piano, contains('<sign>F</sign>'));
    // Tuba is bass clef even for a note the heuristic would put in treble.
    final tuba = xmlFor(58, 72);
    expect(tuba, contains('<sign>F</sign>'));
    expect(tuba, isNot(contains('<sign>G</sign>')));
    expect(xmlFor(40, 48), contains('<sign>G</sign>')); // violin
    expect(xmlFor(41, 60), contains('<sign>C</sign>')); // viola
  });

  test('chords are detected per beat and written as harmony', () {
    // C major for the first bar, then G7 (G B D F) over the second.
    final notes = [
      for (final p in [48, 52, 55])
        Note.create(pitch: p, start: 0, duration: 1920),
      for (final p in [43, 47, 50, 53])
        Note.create(pitch: p, start: 1920, duration: 1920),
    ];
    final asked = <List<String>>[];
    final xml = projectToMusicXml(
      _project(notes, program: 24),
      chordDetector: (names) {
        asked.add(names);
        return names.first == 'C'
            ? const [DetectedChord('C', 'M')]
            : const [DetectedChord('G', '7')];
      },
    )!;
    expect(asked.first, ['C', 'E', 'G']); // bass first
    expect(asked.last, ['G', 'B', 'D', 'F']);
    expect(_matches(xml, r'(<harmony>.*?</harmony>)'), [
      '<harmony><root><root-step>C</root-step></root>'
          '<kind>major</kind></harmony>',
      '<harmony><root><root-step>G</root-step></root>'
          '<kind>dominant</kind></harmony>',
    ]);
  });

  test('sheet options hide the title, tempo and chords', () {
    final notes = [
      for (final p in [48, 52, 55])
        Note.create(pitch: p, start: 0, duration: 480),
    ];
    final project = _project(notes, program: 24);
    List<DetectedChord> detect(List<String> _) => const [
      DetectedChord('C', 'M'),
    ];
    final on = projectToMusicXml(project, chordDetector: detect)!;
    expect(on, contains('<work-title>'));
    expect(on, contains('<metronome>'));
    expect(on, contains('<harmony>'));

    final off = projectToMusicXml(
      project,
      chordDetector: detect,
      options: const SheetOptions(title: false, chords: false, tempo: false),
    )!;
    expect(off, isNot(contains('<work-title>')));
    expect(off, isNot(contains('<metronome>')));
    expect(off, isNot(contains('<harmony>')));
  });

  test('chord candidates are mapped to MusicXML kinds', () {
    expect(
      firstChordSymbol(const [
        DetectedChord('D', 'madd4'), // not expressible, skipped
        DetectedChord('Bb', 'm7', 'F'),
      ]),
      const ChordSymbol(
        rootStep: 'B',
        rootAlter: -1,
        kind: 'minor-seventh',
        bassStep: 'F',
      ),
    );
    expect(firstChordSymbol(const [DetectedChord('C', '13b9')]), isNull);
  });

  test('key signature is written and used to spell notes', () {
    final notes = [Note.create(pitch: 70, start: 0, duration: 480)]; // B♭/A♯
    final flat = projectToMusicXml(
      _project(notes)
          .copyWith(keySignatures: const [KeySignatureChange(0, -2, true)]),
    )!;
    expect(flat, contains('<key><fifths>-2</fifths><mode>minor</mode></key>'));
    expect(flat, contains('<step>B</step><alter>-1</alter>'));

    final sharp = projectToMusicXml(
      _project(notes)
          .copyWith(keySignatures: const [KeySignatureChange(0, 5, false)]),
    )!;
    expect(sharp, contains('<step>A</step><alter>1</alter>'));
  });
}
