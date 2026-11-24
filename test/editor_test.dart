import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_roll/main.dart';
import 'package:piano_roll/model/editing.dart';
import 'package:piano_roll/model/note.dart';
import 'package:piano_roll/model/project.dart';
import 'package:piano_roll/model/snap_and_grid.dart';
import 'package:piano_roll/model/tempo_map.dart';
import 'package:piano_roll/state/editor_provider.dart';
import 'package:piano_roll/state/project_provider.dart';
import 'package:piano_roll/state/transport_provider.dart';
import 'package:piano_roll/ui/note_grid.dart';

void main() {
  group('editing & history', () {
    test('apply/undo/redo and gesture produce single undo steps', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final doc = container.read(projectProvider.notifier);
      final trackId = container.read(projectProvider).project.tracks.first.id;

      doc.apply((p) => Edits.addNotes(p, trackId, [Note.create(pitch: 60, start: 0, duration: 96)]));
      expect(container.read(projectProvider).dirty, isTrue);

      doc.beginGesture();
      for (var i = 1; i <= 5; i++) {
        doc.updateGesture((p) => Edits.replaceNotes(p, trackId, {
              p.tracks.first.notes.first.id: p.tracks.first.notes.first.copyWith(start: i * 10),
            }));
      }
      doc.endGesture();
      expect(container.read(projectProvider).project.tracks.first.notes.first.start, 50);

      doc.undo();
      expect(container.read(projectProvider).project.tracks.first.notes.first.start, 0);
      doc.undo();
      expect(container.read(projectProvider).project.tracks.first.notes, isEmpty);
      expect(container.read(projectProvider).canUndo, isFalse);
      doc.redo();
      expect(container.read(projectProvider).project.tracks.first.notes.length, 1);
    });

    test('new edits clear redo history', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final doc = container.read(projectProvider.notifier);
      final id = container.read(projectProvider).project.tracks.first.id;
      doc.apply((p) => Edits.addNotes(p, id, [Note.create(pitch: 60, start: 0, duration: 96)]));
      doc.undo();
      doc.apply((p) => Edits.setTempo(p, 90));
      expect(container.read(projectProvider).canRedo, isFalse);
    });

    test('setTempo and setTimeSignature replace the initial entries', () {
      final p = Edits.setTimeSignature(Edits.setTempo(Project.empty(), 150), 3, 2);
      expect(p.tempos.single.bpm, closeTo(150, 0.01));
      expect(p.timeSignatures.single.numerator, 3);
    });
  });

  group('timing', () {
    test('snap rounds to grid, including triplets', () {
      expect(Snap.sixteenth.round(130, 480), 120);
      expect(Snap.sixteenth.ticks(480), 120);
      expect(Snap.eighthTriplet.ticks(480), 160);
      expect(Snap.quarter.floor(959, 480), 480);
    });

    test('grid lines follow a time-signature change', () {
      final p = Project.empty().copyWith(
        timeSignatures: const [TimeSignatureChange(0, 4, 2), TimeSignatureChange(1920, 3, 2)],
      );
      final bars = gridLines(p, 0, 1920 + 1440).where((l) => l.isBar).toList();
      expect(bars.map((l) => l.tick), [0, 1920, 3360]);
      expect(bars.map((l) => l.barNumber), [1, 2, 3]);
    });

    test('tempo map converts ticks and time across tempo changes', () {
      final map = TempoMap(480, const [TempoChange(0, 500000), TempoChange(480, 250000)]);
      expect(map.microsAtTick(480), 500000);
      expect(map.microsAtTick(960), 750000);
      expect(map.tickAtMicros(750000), 960);
    });
  });

  testWidgets('select tool: drag moves a note, right edge resizes, erase deletes', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ProviderScope(child: PianoRollApp()));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(PianoRollApp)));
    final trackId = container.read(projectProvider).project.tracks.first.id;
    final note = Note.create(pitch: 60, start: 0, duration: 480);
    container.read(projectProvider.notifier).apply((p) => Edits.addNotes(p, trackId, [note]));
    container.read(editorProvider.notifier).setTool(EditTool.select);
    await tester.pump();

    Note current() => container.read(projectProvider).project.tracks.first.notes.single;
    Offset screenPos(double dxFromStart, double dyRows) {
      final e = container.read(editorProvider);
      final origin = tester.getTopLeft(find.byType(NoteGrid));
      return origin +
          Offset(
            e.tickToX(current().start, 480) - e.scrollX + dxFromStart,
            e.pitchToY(current().pitch) - e.scrollY + e.zoomY * (0.5 + dyRows),
          );
    }

    // Move one beat right (80px) and two semitones up.
    var g = await tester.startGesture(screenPos(20, 0));
    await g.moveBy(const Offset(40, -16));
    await g.moveBy(const Offset(40, -16));
    await g.up();
    await tester.pump();
    expect((current().start, current().pitch), (480, 62));

    // Grab the right edge and extend by one beat.
    g = await tester.startGesture(screenPos(80 - 3, 0));
    await g.moveBy(const Offset(40, 0));
    await g.moveBy(const Offset(40, 0));
    await g.up();
    await tester.pump();
    expect((current().start, current().duration), (480, 960));

    // Each drag was a single undo step.
    container.read(projectProvider.notifier).undo();
    expect(current().duration, 480);
    container.read(projectProvider.notifier).undo();
    expect((current().start, current().pitch), (0, 60));

    // Erase tool deletes by clicking.
    container.read(editorProvider.notifier).setTool(EditTool.erase);
    await tester.pump();
    await tester.tapAt(screenPos(10, 0));
    await tester.pump();
    expect(container.read(projectProvider).project.tracks.first.notes, isEmpty);
  });

  testWidgets('app builds with toolbar, tracks and grid', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ProviderScope(child: PianoRollApp()));
    await tester.pumpAndSettle();

    expect(find.text('Tracks'), findsOneWidget);
    expect(find.text('Track 1'), findsWidgets);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);

    // Drawing a note by clicking in the grid.
    final container = ProviderScope.containerOf(tester.element(find.byType(PianoRollApp)));
    expect(container.read(editorProvider).tool, EditTool.draw);
    await tester.tapAt(const Offset(600, 400));
    await tester.pump();
    final notes = container.read(projectProvider).project.tracks.first.notes;
    expect(notes.length, 1);

    // Pressing Space toggles playback through the (silent) test engine.
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump(const Duration(milliseconds: 100));
    expect(container.read(transportProvider).playing, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(container.read(transportProvider).playing, isFalse);
  });
}
