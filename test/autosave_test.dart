import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piano_roll/io/local_store.dart';
import 'package:piano_roll/main.dart';
import 'package:piano_roll/model/editing.dart';
import 'package:piano_roll/model/note.dart';
import 'package:piano_roll/state/autosave.dart';
import 'package:piano_roll/state/project_provider.dart';

class _FakeStore implements LocalStore {
  final values = <String, String>{};

  @override
  String? read(String key) => values[key];

  @override
  bool write(String key, String value) {
    values[key] = value;
    return true;
  }

  @override
  void remove(String key) => values.remove(key);

  @override
  void onPageHide(void Function() callback) {}
}

void main() {
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
