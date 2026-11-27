import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'autosave.dart';

const _speedDialKey = 'piano_roll.show_tool_speed_dial.v1';

class SpeedDialNotifier extends Notifier<bool> {
  @override
  bool build() => ref.read(localStoreProvider).read(_speedDialKey) != 'false';

  bool setEnabled(bool enabled) {
    if (state == enabled) return true;
    final stored = ref
        .read(localStoreProvider)
        .write(_speedDialKey, enabled.toString());
    state = enabled;
    return stored;
  }
}

final speedDialProvider = NotifierProvider<SpeedDialNotifier, bool>(
  SpeedDialNotifier.new,
);
