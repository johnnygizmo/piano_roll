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

int _byStartThenPitch((int, int) a, (int, int) b) =>
    a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2);

void main() {
  group('editing & history', () {
    test('apply/undo/redo and gesture produce single undo steps', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final doc = container.read(projectProvider.notifier);
      final trackId = container.read(projectProvider).project.tracks.first.id;

      doc.apply(
        (p) => Edits.addNotes(p, trackId, [
          Note.create(pitch: 60, start: 0, duration: 96),
        ]),
      );
      expect(container.read(projectProvider).dirty, isTrue);

      doc.beginGesture();
      for (var i = 1; i <= 5; i++) {
        doc.updateGesture(
          (p) => Edits.replaceNotes(p, trackId, {
            p.tracks.first.notes.first.id: p.tracks.first.notes.first.copyWith(
              start: i * 10,
            ),
          }),
        );
      }
      doc.endGesture();
      expect(
        container.read(projectProvider).project.tracks.first.notes.first.start,
        50,
      );

      doc.undo();
      expect(
        container.read(projectProvider).project.tracks.first.notes.first.start,
        0,
      );
      doc.undo();
      expect(
        container.read(projectProvider).project.tracks.first.notes,
        isEmpty,
      );
      expect(container.read(projectProvider).canUndo, isFalse);
      doc.redo();
      expect(
        container.read(projectProvider).project.tracks.first.notes.length,
        1,
      );
    });

    test('new edits clear redo history', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final doc = container.read(projectProvider.notifier);
      final id = container.read(projectProvider).project.tracks.first.id;
      doc.apply(
        (p) => Edits.addNotes(p, id, [
          Note.create(pitch: 60, start: 0, duration: 96),
        ]),
      );
      doc.undo();
      doc.apply((p) => Edits.setTempo(p, 90));
      expect(container.read(projectProvider).canRedo, isFalse);
    });

    test('setTempo and setTimeSignature replace the initial entries', () {
      final p = Edits.setTimeSignature(
        Edits.setTempo(Project.empty(), 150),
        3,
        2,
      );
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
        timeSignatures: const [
          TimeSignatureChange(0, 4, 2),
          TimeSignatureChange(1920, 3, 2),
        ],
      );
      final bars = gridLines(p, 0, 1920 + 1440).where((l) => l.isBar).toList();
      expect(bars.map((l) => l.tick), [0, 1920, 3360]);
      expect(bars.map((l) => l.barNumber), [1, 2, 3]);
    });

    test('tempo map converts ticks and time across tempo changes', () {
      final map = TempoMap(480, const [
        TempoChange(0, 500000),
        TempoChange(480, 250000),
      ]);
      expect(map.microsAtTick(480), 500000);
      expect(map.microsAtTick(960), 750000);
      expect(map.tickAtMicros(750000), 960);
    });
  });

  testWidgets(
    'select tool: drag moves a note, right edge resizes, erase deletes',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const ProviderScope(child: PianoRollApp()));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PianoRollApp)),
      );
      final trackId = container.read(projectProvider).project.tracks.first.id;
      final note = Note.create(pitch: 60, start: 0, duration: 480);
      container
          .read(projectProvider.notifier)
          .apply((p) => Edits.addNotes(p, trackId, [note]));
      container.read(editorProvider.notifier).setTool(EditTool.select);
      await tester.pump();

      Note current() =>
          container.read(projectProvider).project.tracks.first.notes.single;
      Offset screenPos(double dxFromStart, double dyRows) {
        final e = container.read(editorProvider);
        final origin = tester.getTopLeft(find.byType(NoteGrid));
        return origin +
            Offset(
              e.tickToX(current().start, 480) - e.scrollX + dxFromStart,
              e.pitchToY(current().pitch) -
                  e.scrollY +
                  e.zoomY * (0.5 + dyRows),
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
      expect(
        container.read(projectProvider).project.tracks.first.notes,
        isEmpty,
      );
    },
  );

  testWidgets(
    'Alt+drag copies the selection and moves the copy; plain click never copies',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const ProviderScope(child: PianoRollApp()));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PianoRollApp)),
      );
      final trackId = container.read(projectProvider).project.tracks.first.id;
      final a = Note.create(pitch: 60, start: 0, duration: 480);
      final b = Note.create(pitch: 64, start: 480, duration: 480);
      container
          .read(projectProvider.notifier)
          .apply((p) => Edits.addNotes(p, trackId, [a, b]));
      container.read(editorProvider.notifier)
        ..setTool(EditTool.select)
        ..setSelection({a.id, b.id});
      await tester.pump();

      List<(int, int)> notes() => [
        for (final n
            in container.read(projectProvider).project.tracks.first.notes)
          (n.start, n.pitch),
      ]..sort(_byStartThenPitch);
      Offset onA(double dx) {
        final e = container.read(editorProvider);
        return tester.getTopLeft(find.byType(NoteGrid)) +
            Offset(
              e.tickToX(0, 480) - e.scrollX + dx,
              e.pitchToY(60) - e.scrollY + e.zoomY / 2,
            );
      }

      // Plain click without moving: nothing is duplicated.
      await tester.tapAt(onA(20));
      await tester.pump();
      expect(notes().length, 2);

      // Alt+drag one beat to the right: originals stay, two moved copies appear.
      container.read(editorProvider.notifier).setSelection({a.id, b.id});
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      final g = await tester.startGesture(onA(20));
      await g.moveBy(const Offset(40, 0));
      await g.moveBy(const Offset(40, 0));
      await g.up();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();

      expect(notes(), [(0, 60), (480, 60), (480, 64), (960, 64)]);
      final selected = container.read(editorProvider).selection;
      final copies = container
          .read(projectProvider)
          .project
          .tracks
          .first
          .notes
          .where((n) => selected.contains(n.id));
      expect(copies.map((n) => (n.start, n.pitch)).toSet(), {
        (480, 60),
        (960, 64),
      });
      expect(selected.contains(a.id) || selected.contains(b.id), isFalse);

      // The whole copy-and-move is a single undo step.
      container.read(projectProvider.notifier).undo();
      expect(notes(), [(0, 60), (480, 64)]);
    },
  );

  testWidgets(
    'two-finger drag on a note copies it; lifting the extra finger keeps dragging',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const ProviderScope(child: PianoRollApp()));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PianoRollApp)),
      );
      final trackId = container.read(projectProvider).project.tracks.first.id;
      final a = Note.create(pitch: 60, start: 0, duration: 480);
      container
          .read(projectProvider.notifier)
          .apply((p) => Edits.addNotes(p, trackId, [a]));
      container.read(editorProvider.notifier).setTool(EditTool.select);
      await tester.pump();

      final e = container.read(editorProvider);
      final origin = tester.getTopLeft(find.byType(NoteGrid));
      final onNote =
          origin +
          Offset(
            e.tickToX(0, 480) - e.scrollX + 20,
            e.pitchToY(60) - e.scrollY + e.zoomY / 2,
          );

      final first = await tester.startGesture(onNote, pointer: 1);
      final second = await tester.startGesture(
        onNote + const Offset(300, 200),
        pointer: 2,
      );
      await first.moveBy(const Offset(40, 0));
      await second.up(); // extra finger lifted mid-drag: the drag must continue
      await first.moveBy(const Offset(40, -16));
      await first.up();
      await tester.pump();

      final notes = container.read(projectProvider).project.tracks.first.notes;
      expect(
        notes.map((n) => (n.start, n.pitch)).toList()..sort(_byStartThenPitch),
        [(0, 60), (480, 61)],
      );

      // A single finger drag still just moves.
      final copy = notes.firstWhere((n) => n.start == 480);
      container.read(editorProvider.notifier).setSelection({copy.id});
      await tester.pump();
      final pos =
          origin +
          Offset(
            e.tickToX(480, 480) - e.scrollX + 20,
            e.pitchToY(61) - e.scrollY + e.zoomY / 2,
          );
      final single = await tester.startGesture(pos, pointer: 3);
      await single.moveBy(const Offset(40, 0));
      await single.moveBy(const Offset(40, 0));
      await single.up();
      await tester.pump();
      expect(
        container.read(projectProvider).project.tracks.first.notes.length,
        2,
      );
    },
  );

  testWidgets(
    'song drawer: title, tempo and time signature edit the project; New resets',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const ProviderScope(child: PianoRollApp()));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PianoRollApp)),
      );
      Project project() => container.read(projectProvider).project;

      // Toolbar no longer carries file/tempo controls.
      expect(find.text('BPM'), findsNothing);
      expect(find.byIcon(Icons.folder_open), findsNothing);

      await tester.tap(find.byIcon(Icons.tune));
      await tester.pumpAndSettle();
      expect(find.text('Song settings'), findsOneWidget);
      expect(find.text('File'), findsOneWidget);

      // Focusing and leaving a field without changing it is not an edit.
      await tester.tap(find.widgetWithText(TextField, 'Untitled'));
      await tester.pump();
      await tester.tap(find.widgetWithText(TextField, '120'));
      await tester.pump();
      expect(container.read(projectProvider).dirty, isFalse);
      expect(container.read(projectProvider).canUndo, isFalse);

      await tester.enterText(
        find.widgetWithText(TextField, 'Untitled'),
        'My Song',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(project().name, 'My Song');
      expect(container.read(projectProvider).dirty, isTrue);

      await tester.enterText(find.widgetWithText(TextField, '120'), '90');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(project().tempos.first.bpm, closeTo(90, 0.01));

      // Invalid tempo is rejected and the old value restored.
      await tester.enterText(find.widgetWithText(TextField, '90'), '0');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(project().tempos.first.bpm, closeTo(90, 0.01));
      expect(find.widgetWithText(TextField, '90'), findsOneWidget);

      await tester.tap(find.text('4/4'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3/4').last);
      await tester.pumpAndSettle();
      expect(project().timeSignatures.first.numerator, 3);

      // New asks before discarding, then resets the title; the drawer closes.
      await tester.tap(find.text('New'));
      await tester.pumpAndSettle();
      expect(find.text('Discard unsaved changes?'), findsOneWidget);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(project().name, 'Untitled');
      expect(project().tempos.first.bpm, closeTo(120, 0.01));
      expect(find.text('Song settings'), findsNothing);
    },
  );

  testWidgets('app builds with toolbar, tracks and grid', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ProviderScope(child: PianoRollApp()));
    await tester.pumpAndSettle();

    // The track list lives in a drawer: closed at start, opened from the toolbar.
    expect(find.text('Tracks'), findsNothing);
    expect(find.text('Track 1'), findsOneWidget); // active-track chip
    await tester.tap(find.byIcon(Icons.queue_music));
    await tester.pumpAndSettle();
    expect(find.text('Tracks'), findsOneWidget);
    expect(find.text('Track 1'), findsWidgets);

    // Add a second track from the drawer, then select the first again:
    // choosing a track closes the drawer.
    await tester.tap(find.byTooltip('Add track'));
    await tester.pumpAndSettle();
    expect(find.text('Track 2'), findsWidgets);
    final project = ProviderScope.containerOf(
      tester.element(find.byType(PianoRollApp)),
    );
    final first = project.read(projectProvider).project.tracks.first.id;
    await tester.tap(find.text('Track 1').last);
    await tester.pumpAndSettle();
    expect(find.text('Tracks'), findsNothing);
    expect(project.read(editorProvider).activeTrackId, first);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);

    // Drawing a note by clicking in the grid.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PianoRollApp)),
    );
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
