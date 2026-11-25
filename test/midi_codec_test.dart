import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:piano_roll/midi/midi_events.dart';
import 'package:piano_roll/midi/midi_reader.dart';
import 'package:piano_roll/midi/midi_writer.dart';
import 'package:piano_roll/model/midi_converter.dart';
import 'package:piano_roll/model/note.dart';
import 'package:piano_roll/model/project.dart';
import 'package:piano_roll/model/track.dart';

Uint8List _smf({
  int format = 1,
  int division = 96,
  required List<List<int>> tracks,
}) {
  final out = <int>[
    ...'MThd'.codeUnits,
    0,
    0,
    0,
    6,
    0,
    format,
    0,
    tracks.length,
    division >> 8,
    division & 0xFF,
  ];
  for (final t in tracks) {
    out
      ..addAll('MTrk'.codeUnits)
      ..addAll([0, 0, t.length >> 8, t.length & 0xFF])
      ..addAll(t);
  }
  return Uint8List.fromList(out);
}

void main() {
  group('MidiReader', () {
    test('parses running status, note-on velocity 0 and VLQ deltas', () {
      final bytes = _smf(
        tracks: [
          [
            0x00, 0x90, 60, 100, // note on
            0x60, 62, 100, // running status note on, delta 96
            0x81, 0x00, 60, 0, // delta 128 (2-byte VLQ), vel 0 = off
            0x00, 62, 0,
            0x00, 0xFF, 0x2F, 0x00,
          ],
        ],
      );
      final file = MidiReader.parse(bytes);
      expect(file.division, 96);
      final events = file.tracks.single;
      expect(events.map((e) => e.tick), [0, 96, 224, 224, 224]);

      final project = MidiConverter.fromMidiFile(file);
      final notes = project.tracks.single.notes;
      expect(notes.length, 2);
      expect((notes[0].pitch, notes[0].start, notes[0].duration), (60, 0, 224));
      expect(
        (notes[1].pitch, notes[1].start, notes[1].duration),
        (62, 96, 128),
      );
    });

    test('rejects non-MIDI data and SMPTE timing', () {
      expect(
        () => MidiReader.parse(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<MidiFormatException>()),
      );
      final smpte = _smf(
        division: 0xE728,
        tracks: [
          [0x00, 0xFF, 0x2F, 0x00],
        ],
      );
      expect(
        () => MidiReader.parse(smpte),
        throwsA(isA<MidiFormatException>()),
      );
    });

    test('keeps events read before a truncated track and warns', () {
      final bytes = _smf(
        tracks: [
          [0x00, 0x90, 60, 100, 0x10, 0x80, 60], // off event missing data byte
        ],
      );
      final file = MidiReader.parse(bytes);
      expect(file.tracks.single.length, 1);
      expect(file.warnings, isNotEmpty);
    });

    test('unterminated notes run to the end of the track', () {
      final bytes = _smf(
        tracks: [
          [0x00, 0x90, 60, 100, 0x60, 0xFF, 0x2F, 0x00],
        ],
      );
      final project = MidiConverter.fromMidiFile(MidiReader.parse(bytes));
      expect(project.tracks.single.notes.single.duration, 96);
    });

    test(
      'splits a format 0 file by channel and reads tempo/time signature',
      () {
        final bytes = _smf(
          format: 0,
          tracks: [
            [
              0x00, 0xFF, 0x51, 0x03, 0x06, 0x1A, 0x80, // 400000 us -> 150 bpm
              0x00, 0xFF, 0x58, 0x04, 3, 2, 24, 8,
              0x00, 0x90, 60, 90,
              0x00, 0x91, 40, 80,
              0x30, 0x80, 60, 0,
              0x00, 0x81, 40, 0,
              0x00, 0xFF, 0x2F, 0x00,
            ],
          ],
        );
        final project = MidiConverter.fromMidiFile(MidiReader.parse(bytes));
        expect(project.tracks.length, 2);
        expect(project.tracks.map((t) => t.channel), [0, 1]);
        expect(project.tempos.single.microsPerQuarter, 400000);
        expect(project.timeSignatures.single.numerator, 3);
      },
    );
  });

  group('round trip', () {
    test('project -> bytes -> project preserves notes, tempo and extras', () {
      final extra = MidiEvent.channel(10, 0xB0, 7, 99); // volume controller
      final original = Project(
        name: 'song',
        ppq: 480,
        tempos: const [TempoChange(0, 500000), TempoChange(1920, 400000)],
        timeSignatures: const [TimeSignatureChange(0, 6, 3)],
        keySignatures: const [KeySignatureChange(0, -3, true)],
        tracks: [
          Track.create(
            name: 'Lead',
            channel: 2,
            program: 40,
            notes: [
              Note.create(pitch: 60, start: 0, duration: 480, velocity: 90),
              Note.create(pitch: 64, start: 0, duration: 240, velocity: 50),
              Note.create(pitch: 60, start: 480, duration: 480, velocity: 100),
            ],
            extras: [extra],
          ),
          Track.create(
            name: 'Drums',
            channel: 9,
            notes: [Note.create(pitch: 36, start: 960, duration: 120)],
          ),
        ],
      );

      final bytes = MidiWriter.write(MidiConverter.toMidiFile(original));
      final copy = MidiConverter.fromMidiFile(
        MidiReader.parse(bytes),
        name: 'song',
      );

      expect(copy.ppq, 480);
      expect(copy.tempos.map((t) => (t.tick, t.microsPerQuarter)), [
        (0, 500000),
        (1920, 400000),
      ]);
      expect(copy.timeSignatures.single.denominator, 8);
      expect(copy.keySignatures, const [KeySignatureChange(0, -3, true)]);
      expect(copy.tracks.length, 2);

      final lead = copy.tracks[0];
      expect(lead.name, 'Lead');
      expect(lead.channel, 2);
      expect(lead.program, 40);
      expect(
        lead.notes
            .map((n) => (n.pitch, n.start, n.duration, n.velocity))
            .toList(),
        [(60, 0, 480, 90), (64, 0, 240, 50), (60, 480, 480, 100)],
      );
      expect(lead.extras.single.data, extra.data);
      expect(lead.extras.single.tick, 10);
      expect(copy.tracks[1].isDrum, isTrue);
    });

    test(
      'repeated same-pitch notes retrigger (off precedes on at same tick)',
      () {
        final p = Project(
          name: 'x',
          ppq: 96,
          tempos: const [TempoChange(0, 500000)],
          timeSignatures: const [TimeSignatureChange(0, 4, 2)],
          tracks: [
            Track.create(
              name: 't',
              notes: [
                Note.create(pitch: 60, start: 0, duration: 96),
                Note.create(pitch: 60, start: 96, duration: 96),
              ],
            ),
          ],
        );
        final copy = MidiConverter.fromMidiFile(
          MidiReader.parse(MidiWriter.write(MidiConverter.toMidiFile(p))),
        );
        expect(copy.tracks.single.notes.map((n) => (n.start, n.duration)), [
          (0, 96),
          (96, 96),
        ]);
      },
    );
  });
}
