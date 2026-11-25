import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../io/local_store.dart';
import '../io/local_store_stub.dart'
    if (dart.library.js_interop) '../io/local_store_web.dart'
    as impl;
import 'project_provider.dart';

const _key = 'piano_roll.autosave.v1';
const _delay = Duration(milliseconds: 500);

final localStoreProvider = Provider<LocalStore>((ref) {
  return impl.createLocalStoreImpl();
});

/// Unsaved work found in the local store.
class AutosaveEntry {
  const AutosaveEntry(this.name, this.savedAt, this.bytes);

  final String name;
  final DateTime savedAt;

  /// Standard MIDI file bytes.
  final Uint8List bytes;
}

/// Keeps a copy of the unsaved project as MIDI data in the [LocalStore], so
/// it can be offered back after a reload or crash. The copy is removed once
/// the project is saved, replaced by a new/opened file, or discarded.
class Autosave {
  Autosave(this._ref) {
    _store.onPageHide(flush);
  }

  final Ref _ref;
  Timer? _timer;

  LocalStore get _store => _ref.read(localStoreProvider);

  void _onProjectChanged(ProjectState next) {
    if (next.dirty) {
      _timer ??= Timer(_delay, flush);
    } else {
      _timer?.cancel();
      _timer = null;
      clear();
    }
  }

  /// Writes the current project now if a save is pending.
  void flush() {
    if (_timer == null) return;
    _timer!.cancel();
    _timer = null;
    final doc = _ref.read(projectProvider);
    if (!doc.dirty) return;
    final bytes = _ref.read(projectProvider.notifier).exportBytes();
    _store.write(
      _key,
      jsonEncode({
        'name': doc.project.name,
        'savedAt': DateTime.now().toIso8601String(),
        'data': base64Encode(bytes),
      }),
    );
  }

  AutosaveEntry? read() {
    final raw = _store.read(_key);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return AutosaveEntry(
        json['name'] as String,
        DateTime.parse(json['savedAt'] as String),
        base64Decode(json['data'] as String),
      );
    } catch (_) {
      clear();
      return null;
    }
  }

  void clear() => _store.remove(_key);

  void dispose() => _timer?.cancel();
}

final autosaveProvider = Provider<Autosave>((ref) {
  final autosave = Autosave(ref);
  ref.listen(projectProvider, (_, next) => autosave._onProjectChanged(next));
  ref.onDispose(autosave.dispose);
  return autosave;
});
