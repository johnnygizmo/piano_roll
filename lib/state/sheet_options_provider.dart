import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/sheet_options.dart';

/// Which optional items the sheet music shows (all on by default).
class SheetOptionsNotifier extends Notifier<SheetOptions> {
  @override
  SheetOptions build() => const SheetOptions();

  void update(SheetOptions Function(SheetOptions) change) =>
      state = change(state);
}

final sheetOptionsProvider =
    NotifierProvider<SheetOptionsNotifier, SheetOptions>(
      SheetOptionsNotifier.new,
    );
