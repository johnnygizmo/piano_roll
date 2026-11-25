import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_roll/main.dart';
import 'package:piano_roll/model/chords.dart';
import 'package:piano_roll/model/editing.dart';
import 'package:piano_roll/model/intervals.dart';
import 'package:piano_roll/model/note.dart';
import 'package:piano_roll/state/editor_provider.dart';
import 'package:piano_roll/state/project_provider.dart';
import 'package:piano_roll/ui/note_grid.dart';
import 'package:piano_roll/ui/pie_menu.dart';

void main() {
  group('chordIntervals', () {
    List<int> i(ChordQuality q, ChordExtension e) => chordIntervals(q, e);

    test('triads', () {
      expect(i(ChordQuality.major, ChordExtension.triad), [4, 7]);
      expect(i(ChordQuality.minor, ChordExtension.triad), [3, 7]);
      expect(i(ChordQuality.augmented, ChordExtension.triad), [4, 8]);
      expect(i(ChordQuality.diminished, ChordExtension.triad), [3, 6]);
    });

    test('seventh flavours', () {
      expect(i(ChordQuality.major, ChordExtension.major7), [4, 7, 11]);
      expect(i(ChordQuality.major, ChordExtension.dominant7), [4, 7, 10]);
      expect(i(ChordQuality.minor, ChordExtension.minor7), [3, 7, 10]);
      expect(i(ChordQuality.diminished, ChordExtension.dominant7), [3, 6, 9]);
      expect(i(ChordQuality.diminished, ChordExtension.minor7), [3, 6, 10]);
    });

    test('extensions stack; 13 omits the 11th', () {
      expect(i(ChordQuality.major, ChordExtension.dominant9), [4, 7, 10, 14]);
      expect(i(ChordQuality.minor, ChordExtension.minor11), [3, 7, 10, 14, 17]);
      expect(i(ChordQuality.major, ChordExtension.major13), [4, 7, 11, 14, 21]);
    });

    test('buildChord copies timing/velocity, excludes root and drops notes above 127', () {
      final root = Note.create(
        pitch: 120,
        start: 96,
        duration: 48,
        velocity: 77,
      );
      final chord = buildChord(
        root,
        ChordQuality.major,
        ChordExtension.dominant7,
      );
      expect(chord.map((n) => n.pitch), [124, 127]);
      expect(
        chord.every(
          (n) => n.start == 96 && n.duration == 48 && n.velocity == 77,
        ),
        isTrue,
      );
      expect(chord.map((n) => n.id).toSet().length, 2);
    });
  });

  group('pie layout', () {
    test('hit testing maps angles to slices and hub/outside', () {
      expect(PieLayout.hitTest(Offset.zero, 4), -1);
      expect(PieLayout.hitTest(const Offset(0, -80), 4), 0); // top
      expect(PieLayout.hitTest(const Offset(80, 0), 4), 1); // right
      expect(PieLayout.hitTest(const Offset(0, 80), 4), 2); // bottom
      expect(PieLayout.hitTest(const Offset(-80, 0), 4), 3); // left
      expect(PieLayout.hitTest(const Offset(0, -200), 4), -2);
      for (var n = 0; n < 13; n++) {
        final c = PieLayout.sliceCenter(Offset.zero, 13, n);
        expect(PieLayout.hitTest(c, 13), n);
      }
    });
  });

  Future<(ProviderContainer, Offset Function())> setup(
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const ProviderScope(child: PianoRollApp()));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PianoRollApp)),
    );
    final trackId = container.read(projectProvider).project.tracks.first.id;
    final note = Note.create(
      pitch: 60,
      start: 480,
      duration: 480,
      velocity: 90,
    );
    container
        .read(projectProvider.notifier)
        .apply((p) => Edits.addNotes(p, trackId, [note]));
    container.read(editorProvider.notifier).setTool(EditTool.select);
    await tester.pump();
    Offset notePos() {
      final e = container.read(editorProvider);
      return tester.getTopLeft(find.byType(NoteGrid)) +
          Offset(
            e.tickToX(480, 480) - e.scrollX + 20,
            e.pitchToY(60) - e.scrollY + e.zoomY / 2,
          );
    }

    return (container, notePos);
  }

  Future<void> pickChord(
    WidgetTester tester,
    Offset menuAt,
    int quality,
    int extension,
  ) async {
    final center = PieLayout.clampCenter(menuAt, const Size(1600, 900));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tapAt(PieLayout.sliceCenter(center, 3, 0)); // Chord
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(PieLayout.sliceCenter(center, 4, quality));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(
      PieLayout.sliceCenter(center, ChordExtension.values.length, extension),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'right-click a note, choose Minor then 7: builds a minor 7th chord',
    (tester) async {
      final (container, notePos) = await setup(tester);
      final at = notePos();
      final g = await tester.startGesture(
        at,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await g.up();
      await pickChord(
        tester,
        at,
        ChordQuality.minor.index,
        ChordExtension.dominant7.index,
      );

      final notes = container.read(projectProvider).project.tracks.first.notes;
      expect(notes.map((n) => n.pitch).toList()..sort(), [60, 63, 67, 70]);
      expect(
        notes.every(
          (n) => n.start == 480 && n.duration == 480 && n.velocity == 90,
        ),
        isTrue,
      );
      expect(container.read(editorProvider).selection, isEmpty);

      // One undo step removes the whole chord.
      container.read(projectProvider.notifier).undo();
      expect(
        container.read(projectProvider).project.tracks.first.notes.length,
        1,
      );
    },
  );

  testWidgets('Edit menu: Lengthen, Shorten (never erases) and Set Size', (
    tester,
  ) async {
    final (container, notePos) = await setup(tester);
    Note note() =>
        container.read(projectProvider).project.tracks.first.notes.single;

    // Resize -> [path...]; ring sizes: top 3, Edit 5, Resize 3, Set Size 8.
    Future<void> resize(List<(int, int)> path) async {
      final at = notePos();
      final g = await tester.startGesture(
        at,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await g.up();
      final center = PieLayout.clampCenter(at, const Size(1600, 900));
      await tester.pump(const Duration(milliseconds: 300));
      for (final (count, index) in [(3, 1), (5, 4), ...path]) {
        await tester.tapAt(PieLayout.sliceCenter(center, count, index));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
    }

    expect(note().duration, 480);
    await resize([(3, 0)]); // Lengthen by the 1/16 snap
    expect(note().duration, 600);
    await resize([(3, 1)]); // Shorten
    expect(note().duration, 480);
    await resize([(3, 2), (8, 1)]); // Set Size 1/2
    expect(note().duration, 960);
    await resize([(3, 2), (8, 5)]); // Set Size 1/32
    expect(note().duration, 60);
    await resize([(3, 1)]); // 60 - 120 would erase it: unchanged
    expect(note().duration, 60);
  });

  testWidgets(
    'Transpose acts on the selection, refuses out-of-range, targets the clicked note otherwise',
    (tester) async {
      final (container, _) = await setup(tester);
      final trackId = container.read(projectProvider).project.tracks.first.id;
      final b = Note.create(pitch: 72, start: 960, duration: 240);
      final c = Note.create(pitch: 3, start: 1920, duration: 240);
      container
          .read(projectProvider.notifier)
          .apply((p) => Edits.addNotes(p, trackId, [b, c]));
      final editor = container.read(editorProvider.notifier);

      Note byStart(int start) => container
          .read(projectProvider)
          .project
          .tracks
          .first
          .notes
          .firstWhere((n) => n.start == start);
      List<int> pitches() => [
        for (final s in [480, 960, 1920]) byStart(s).pitch,
      ];

      Future<void> transpose(Note clicked, int direction, int interval) async {
        final e = container.read(editorProvider);
        final at =
            tester.getTopLeft(find.byType(NoteGrid)) +
            Offset(
              e.tickToX(clicked.start, 480) - e.scrollX + 20,
              e.pitchToY(clicked.pitch) - e.scrollY + e.zoomY / 2,
            );
        final g = await tester.startGesture(
          at,
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await g.up();
        final center = PieLayout.clampCenter(at, const Size(1600, 900));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tapAt(PieLayout.sliceCenter(center, 3, 2)); // Transpose
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tapAt(
          PieLayout.sliceCenter(center, 4, direction),
        ); // 0 Up, 1 Down, 2 Copy Up, 3 Copy Down
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tapAt(
          PieLayout.sliceCenter(center, transposeIntervals.length, interval),
        );
        await tester.pumpAndSettle();
      }

      // Both selected notes move down a perfect fifth; selection is kept.
      final a = byStart(480);
      editor.setSelection({a.id, b.id});
      await tester.pump();
      await transpose(a, 1, 6);
      expect(pitches(), [53, 65, 3]);
      expect(container.read(editorProvider).selection, {a.id, b.id});

      // Pitch 3 would go below 0: nothing changes at all.
      editor.setSelection({a.id, c.id});
      await tester.pump();
      await transpose(byStart(480), 1, 6);
      expect(pitches(), [53, 65, 3]);

      // Clicking a note outside the selection makes it the only target.
      editor.setSelection({b.id});
      await tester.pump();
      await transpose(byStart(480), 0, 0); // Up m2
      expect(pitches(), [54, 65, 3]);
      expect(container.read(editorProvider).selection, {a.id});

      // One undo step per transposition.
      container.read(projectProvider.notifier).undo();
      expect(pitches(), [53, 65, 3]);

      // Copy Up (P5): originals stay, copies are added and selected.
      Note noteAt(int start, int pitch) => container
          .read(projectProvider)
          .project
          .tracks
          .first
          .notes
          .firstWhere((n) => n.start == start && n.pitch == pitch);
      List<(int, int)> all() =>
          [
            for (final n
                in container.read(projectProvider).project.tracks.first.notes)
              (n.start, n.pitch),
          ]..sort(
            (x, y) =>
                x.$1 != y.$1 ? x.$1.compareTo(y.$1) : x.$2.compareTo(y.$2),
          );

      editor.setSelection({a.id, b.id});
      await tester.pump();
      await transpose(noteAt(480, 53), 2, 6);
      expect(all(), [(480, 53), (480, 60), (960, 65), (960, 72), (1920, 3)]);
      final copies = container.read(editorProvider).selection;
      expect(copies, {noteAt(480, 60).id, noteAt(960, 72).id});

      // Copy Down (octave) from the selected copies; a copy landing on an
      // existing note (65 -> 53 is not there, but 72 -> 60 at 960 is new) is added once.
      await transpose(noteAt(480, 60), 3, 11);
      expect(all(), [
        (480, 48),
        (480, 53),
        (480, 60),
        (960, 60),
        (960, 65),
        (960, 72),
        (1920, 3),
      ]);

      // Copying onto notes that already exist adds nothing and keeps the selection.
      editor.setSelection({noteAt(960, 72).id});
      await tester.pump();
      await transpose(
        noteAt(960, 72),
        3,
        5,
      ); // tritone down: 72 - 6 = 66, a new note
      await transpose(
        noteAt(960, 66),
        2,
        5,
      ); // tritone up: 66 + 6 = 72 already exists
      expect(all().where((n) => n.$1 == 960).map((n) => n.$2).toList(), [
        60,
        65,
        66,
        72,
      ]);
    },
  );

  testWidgets(
    'long-press with touch opens the menu; centre goes back, outside cancels',
    (tester) async {
      final (container, notePos) = await setup(tester);
      final at = notePos();
      final g = await tester.startGesture(at); // touch
      await tester.pump(const Duration(milliseconds: 700));
      await g.up();
      final center = PieLayout.clampCenter(at, const Size(1600, 900));

      await tester.pump(const Duration(milliseconds: 300));
      await tester.tapAt(PieLayout.sliceCenter(center, 4, 0)); // Chord ring
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(center); // hub: back to root ring
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(PieLayout.sliceCenter(center, 4, 0)); // Chord again
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(PieLayout.sliceCenter(center, 4, 0)); // Major
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(PieLayout.sliceCenter(center, 13, 0)); // Triad
      await tester.pumpAndSettle();

      final pitches =
          container
              .read(projectProvider)
              .project
              .tracks
              .first
              .notes
              .map((n) => n.pitch)
              .toList()
            ..sort();
      expect(pitches, [60, 64, 67]);

      // Opening and clicking far outside dismisses without changes.
      final g2 = await tester.startGesture(
        at,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await g2.up();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(
        container.read(projectProvider).project.tracks.first.notes.length,
        3,
      );
    },
  );
}
