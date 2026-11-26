import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'autosave.dart';

const _systemMidiKey = 'piano_roll.use_system_midi.v1';

class SystemMidiNotifier extends Notifier<bool> {
  @override
  bool build() => ref.read(localStoreProvider).read(_systemMidiKey) != 'false';

  /// Returns false if the preference could not be persisted.
  bool setUseSystemMidi(bool enabled) {
    if (state == enabled) return true;
    final stored = ref
        .read(localStoreProvider)
        .write(_systemMidiKey, enabled.toString());
    state = enabled;
    return stored;
  }
}

final systemMidiProvider = NotifierProvider<SystemMidiNotifier, bool>(
  SystemMidiNotifier.new,
);
