import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_roll/main.dart';
import 'package:piano_roll/model/chords.dart';
import 'package:piano_roll/model/editing.dart';
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
      final root = Note.create(pitch: 120, start: 96, duration: 48, velocity: 77);
      final chord = buildChord(root, ChordQuality.major, ChordExtension.dominant7);
      expect(chord.map((n) => n.pitch), [124, 127]);
      expect(chord.every((n) => n.start == 96 && n.duration == 48 && n.velocity == 77), isTrue);
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

  Future<(ProviderContainer, Offset Function())> setup(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const ProviderScope(child: PianoRollApp()));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(PianoRollApp)));
    final trackId = container.read(projectProvider).project.tracks.first.id;
    final note = Note.create(pitch: 60, start: 480, duration: 480, velocity: 90);
    container.read(projectProvider.notifier).apply((p) => Edits.addNotes(p, trackId, [note]));
    container.read(editorProvider.notifier).setTool(EditTool.select);
    await tester.pump();
    Offset notePos() {
      final e = container.read(editorProvider);
      return tester.getTopLeft(find.byType(NoteGrid)) +
          Offset(e.tickToX(480, 480) - e.scrollX + 20, e.pitchToY(60) - e.scrollY + e.zoomY / 2);
    }

    return (container, notePos);
  }

  Future<void> pickChord(WidgetTester tester, Offset menuAt, int quality, int extension) async {
    final center = PieLayout.clampCenter(menuAt, const Size(1600, 900));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tapAt(PieLayout.sliceCenter(center, 3, 0)); // Chord
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(PieLayout.sliceCenter(center, 4, quality));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(PieLayout.sliceCenter(center, ChordExtension.values.length, extension));
    await tester.pumpAndSettle();
  }

  testWidgets('right-click a note, choose Minor then 7: builds a minor 7th chord', (tester) async {
    final (container, notePos) = await setup(tester);
    final at = notePos();
    final g = await tester.startGesture(at, kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await g.up();
    await pickChord(tester, at, ChordQuality.minor.index, ChordExtension.dominant7.index);

    final notes = container.read(projectProvider).project.tracks.first.notes;
    expect(notes.map((n) => n.pitch).toList()..sort(), [60, 63, 67, 70]);
    expect(notes.every((n) => n.start == 480 && n.duration == 480 && n.velocity == 90), isTrue);
    expect(container.read(editorProvider).selection, isEmpty);

    // One undo step removes the whole chord.
    container.read(projectProvider.notifier).undo();
    expect(container.read(projectProvider).project.tracks.first.notes.length, 1);
  });

  testWidgets('long-press with touch opens the menu; centre goes back, outside cancels', (tester) async {
    final (container, notePos) = await setup(tester);
    final at = notePos();
    final g = await tester.startGesture(at); // touch
    await tester.pump(const Duration(milliseconds: 700));
    await g.up();
    final center = PieLayout.clampCenter(at, const Size(1600, 900));

    await tester.pump(const Duration(milliseconds: 300));
    await tester.tapAt(PieLayout.sliceCenter(center, 3, 0)); // Chord ring
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(center); // hub: back to root ring
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(PieLayout.sliceCenter(center, 3, 0)); // Chord again
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(PieLayout.sliceCenter(center, 4, 0)); // Major
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(PieLayout.sliceCenter(center, 13, 0)); // Triad
    await tester.pumpAndSettle();

    final pitches = container.read(projectProvider).project.tracks.first.notes.map((n) => n.pitch).toList()..sort();
    expect(pitches, [60, 64, 67]);

    // Opening and clicking far outside dismisses without changes.
    final g2 = await tester.startGesture(at, kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await g2.up();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(container.read(projectProvider).project.tracks.first.notes.length, 3);
  });
}
