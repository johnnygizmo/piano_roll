import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/editor_provider.dart';
import 'interaction.dart';

class ToolSpeedDial extends ConsumerStatefulWidget {
  const ToolSpeedDial({super.key});

  @override
  ConsumerState<ToolSpeedDial> createState() => _ToolSpeedDialState();
}

class _ToolSpeedDialState extends ConsumerState<ToolSpeedDial> {
  bool _open = false;

  static const _tools = <(EditTool, IconData, String)>[
    (EditTool.select, Icons.near_me, 'Select (V)'),
    (EditTool.draw, Icons.edit, 'Draw (D)'),
    (EditTool.erase, Icons.cleaning_services, 'Erase (E)'),
    (EditTool.pan, Icons.pan_tool, 'Pan (H)'),
  ];

  @override
  Widget build(BuildContext context) {
    final tool = ref.watch(editorProvider.select((state) => state.tool));
    final current = _tools.firstWhere((entry) => entry.$1 == tool);
    final colors = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_open)
          for (final (mode, icon, label) in _tools)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FloatingActionButton.small(
                heroTag: null,
                tooltip: label,
                backgroundColor: mode == tool
                    ? colors.primaryContainer
                    : colors.secondaryContainer,
                onPressed: () {
                  ref.read(editorProvider.notifier).setTool(mode);
                  setState(() => _open = false);
                  editorFocusNode.requestFocus();
                },
                child: Icon(icon),
              ),
            ),
        FloatingActionButton(
          heroTag: null,
          tooltip: _open ? 'Close mode selector' : 'Choose editing mode',
          onPressed: () => setState(() => _open = !_open),
          child: Icon(_open ? Icons.close : current.$2),
        ),
      ],
    );
  }
}
