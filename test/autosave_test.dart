import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_roll/io/local_store.dart';
import 'package:piano_roll/main.dart';
import 'package:piano_roll/model/editing.dart';
import 'package:piano_roll/model/note.dart';
import 'package:piano_roll/state/autosave.dart';
import 'package:piano_roll/state/editor_provider.dart';
import 'package:piano_roll/state/project_provider.dart';
import 'package:piano_roll/state/speed_dial_provider.dart';
import 'package:piano_roll/ui/tool_speed_dial.dart';

class _FakeStore implements LocalStore {
  final values = <String, String>{};
  bool failWrites = false;

  @override
  String? read(String key) => values[key];

  @override
  bool write(String key, String value) {
    if (failWrites) return false;
    values[key] = value;
    return true;
  }

  @override
  void remove(String key) => values.remove(key);

  @override
  void onPageHide(void Function() callback) {}
}

void main() {
  testWidgets(
    'floating mode selector switches tools and persists its setting',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = _FakeStore();

      Future<ProviderContainer> start() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [localStoreProvider.overrideWithValue(store)],
            child: const PianoRollApp(),
          ),
        );
        await tester.pumpAndSettle();
        return ProviderScope.containerOf(
          tester.element(find.byType(PianoRollApp)),
        );
      }

      var container = await start();
      expect(container.read(speedDialProvider), isTrue);
      expect(find.byType(ToolSpeedDial), findsOneWidget);
      expect(find.byType(SegmentedButton<EditTool>), findsNothing);
      for (final (label, tool) in [
        ('Select (V)', EditTool.select),
        ('Draw (D)', EditTool.draw),
        ('Erase (E)', EditTool.erase),
        ('Pan (H)', EditTool.pan),
      ]) {
        await tester.tap(find.byTooltip('Choose editing mode'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(ToolSpeedDial),
            matching: find.byTooltip(label),
          ),
        );
        await tester.pumpAndSettle();
        expect(container.read(editorProvider).tool, tool);
        expect(find.byTooltip('Close mode selector'), findsNothing);
      }
      container.read(editorProvider.notifier).setTool(EditTool.select);
      await tester.pump();
      expect(
        find.descendant(
          of: find.byTooltip('Choose editing mode'),
          matching: find.byIcon(Icons.near_me),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byIcon(Icons.tune));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Floating mode selector'));
      await tester.pumpAndSettle();
      expect(find.byType(ToolSpeedDial), findsNothing);
      expect(store.values['piano_roll.show_tool_speed_dial.v1'], 'false');
      await tester.tapAt(const Offset(20, 300));
      await tester.pumpAndSettle();
      expect(find.byType(SegmentedButton<EditTool>), findsOneWidget);
      expect(
        tester
            .widget<SegmentedButton<EditTool>>(
              find.byType(SegmentedButton<EditTool>),
            )
            .selected,
        {EditTool.select},
      );
      await tester.tap(find.byTooltip('Pan (H) - drag to scroll'));
      await tester.pumpAndSettle();
      expect(container.read(editorProvider).tool, EditTool.pan);
      await tester.tap(find.byIcon(Icons.tune));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Floating mode selector'));
      await tester.pumpAndSettle();
      expect(find.byType(SegmentedButton<EditTool>), findsNothing);
      expect(container.read(editorProvider).tool, EditTool.pan);
      expect(
        find.descendant(
          of: find.byTooltip('Choose editing mode'),
          matching: find.byIcon(Icons.pan_tool),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Floating mode selector'));
      await tester.pumpAndSettle();
      expect(find.byType(SegmentedButton<EditTool>), findsOneWidget);

      container = await start();
      expect(container.read(speedDialProvider), isFalse);
      expect(find.byType(ToolSpeedDial), findsNothing);
      expect(find.byType(SegmentedButton<EditTool>), findsOneWidget);
      await tester.tap(find.byIcon(Icons.tune));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Floating mode selector'));
      await tester.pumpAndSettle();
      expect(find.byType(ToolSpeedDial), findsOneWidget);
      expect(find.byType(SegmentedButton<EditTool>), findsNothing);
      expect(store.values['piano_roll.show_tool_speed_dial.v1'], 'true');

      container = await start();
      expect(container.read(speedDialProvider), isTrue);
      expect(find.byType(ToolSpeedDial), findsOneWidget);
      expect(find.byType(SegmentedButton<EditTool>), findsNothing);
    },
  );

  testWidgets('floating mode selector reports a failed save', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = _FakeStore()..failWrites = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [localStoreProvider.overrideWithValue(store)],
        child: const PianoRollApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Floating mode selector'));
    await tester.pump(const Duration(milliseconds: 300));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PianoRollApp)),
    );
    expect(container.read(speedDialProvider), isFalse);
    expect(
      find.text('Could not save the mode selector preference.'),
      findsOneWidget,
    );
  });

  testWidgets('edits are autosaved, restored after a reload, then cleared '
      'when saved', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = _FakeStore();

    Future<ProviderContainer> start() async {
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [localStoreProvider.overrideWithValue(store)],
          child: const PianoRollApp(),
        ),
      );
      await tester.pumpAndSettle();
      return ProviderScope.containerOf(
        tester.element(find.byType(PianoRollApp)),
      );
    }

    // First session: edit, wait for the debounce.
    var container = await start();
    expect(find.text('Restore unsaved work?'), findsNothing);
    final doc = container.read(projectProvider.notifier);
    final id = container.read(projectProvider).project.tracks.first.id;
    doc.apply(
      (p) => Edits.setName(
        Edits.addNotes(p, id, [Note.create(pitch: 64, start: 0, duration: 96)]),
        'My song',
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(store.values, hasLength(1));
    expect(jsonDecode(store.values.values.single)['name'], 'My song');

    // "Reload": a new session offers the copy; discarding clears it.
    container = await start();
    expect(find.text('Restore unsaved work?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(store.values, isEmpty);
    expect(container.read(projectProvider).project.name, 'Untitled');

    // Edit again, reload, and restore this time.
    container
        .read(projectProvider.notifier)
        .apply((p) => Edits.setName(p, 'Again'));
    await tester.pump(const Duration(seconds: 1));
    container = await start();
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    final restored = container.read(projectProvider);
    expect(restored.project.name, 'Again');
    expect(restored.dirty, isTrue);

    // Saving removes the stored copy.
    container.read(projectProvider.notifier).markSaved();
    await tester.pump();
    expect(store.values, isEmpty);
  });
}
