import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../io/file_io.dart';
import '../state/editor_provider.dart';
import '../state/project_provider.dart';
import '../state/speed_dial_provider.dart';
import '../state/transport_provider.dart';
import 'constants.dart';
import 'editor_actions.dart';
import 'interaction.dart';
import 'keyboard_view.dart';
import 'note_grid.dart';
import 'ruler_view.dart';
import 'scrollbars.dart';
import 'song_drawer.dart';
import 'toolbar.dart';
import 'tool_speed_dial.dart';
import 'track_panel.dart';
import 'velocity_lane.dart';

class PianoRollPage extends ConsumerWidget {
  const PianoRollPage({super.key});

  KeyEventResult _onKey(BuildContext context, WidgetRef ref, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final actions = EditorActions(context, ref);
    final keys = HardwareKeyboard.instance;
    final ctrl = keys.isControlPressed || keys.isMetaPressed;
    final shift = keys.isShiftPressed;
    final key = event.logicalKey;
    final view = ref.read(editorProvider.notifier);

    if (ctrl) {
      if (key == LogicalKeyboardKey.keyZ) {
        shift ? actions.redo() : actions.undo();
      } else if (key == LogicalKeyboardKey.keyY) {
        actions.redo();
      } else if (key == LogicalKeyboardKey.keyA) {
        actions.selectAll();
      } else if (key == LogicalKeyboardKey.keyC) {
        actions.copy();
      } else if (key == LogicalKeyboardKey.keyX) {
        actions.cut();
      } else if (key == LogicalKeyboardKey.keyV) {
        actions.paste();
      } else if (key == LogicalKeyboardKey.keyD) {
        actions.duplicate();
      } else if (key == LogicalKeyboardKey.keyO) {
        actions.openFile();
      } else if (key == LogicalKeyboardKey.keyS) {
        actions.exportFile();
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      actions.deleteSelected();
    } else if (key == LogicalKeyboardKey.space) {
      actions.togglePlay();
    } else if (key == LogicalKeyboardKey.keyV) {
      view.setTool(EditTool.select);
    } else if (key == LogicalKeyboardKey.keyD) {
      view.setTool(EditTool.draw);
    } else if (key == LogicalKeyboardKey.keyE) {
      view.setTool(EditTool.erase);
    } else if (key == LogicalKeyboardKey.keyH) {
      view.setTool(EditTool.pan);
    } else if (key == LogicalKeyboardKey.keyT) {
      scaffoldKey.currentState?.openDrawer();
    } else if (key == LogicalKeyboardKey.keyQ) {
      actions.quantize();
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      actions.nudge(dTick: -actions.snapTicks);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      actions.nudge(dTick: actions.snapTicks);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      actions.nudge(dPitch: shift ? 12 : 1);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      actions.nudge(dPitch: shift ? -12 : -1);
    } else if (key == LogicalKeyboardKey.home) {
      ref.read(transportProvider.notifier).seek(0);
      view.scrollTo(0, ref.read(editorProvider).scrollY);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thickness = scrollbarThicknessFor(context);
    ref.listen<bool>(projectProvider.select((s) => s.dirty), (_, dirty) {
      setUnsavedChangesWarning(dirty);
    });

    // Follow the playhead while playing.
    ref.listen<TransportState>(transportProvider, (prev, next) {
      if (!next.playing) return;
      final editor = ref.read(editorProvider);
      final ppq = ref.read(projectProvider).project.ppq;
      final x = editor.tickToX(next.tick, ppq);
      if (x < editor.scrollX ||
          x > editor.scrollX + editor.viewport.width - 24) {
        ref.read(editorProvider.notifier).scrollTo(x - 48, editor.scrollY);
      }
    });

    return Scaffold(
      key: scaffoldKey,
      drawer: const Drawer(
        width: trackPanelWidth,
        child: SafeArea(child: TrackPanel()),
      ),
      endDrawer: const Drawer(width: songDrawerWidth, child: SongDrawer()),
      floatingActionButton: ref.watch(speedDialProvider)
          ? const ToolSpeedDial()
          : null,
      onDrawerChanged: (open) {
        if (!open) editorFocusNode.requestFocus();
      },
      onEndDrawerChanged: (open) {
        if (!open) editorFocusNode.requestFocus();
      },
      body: Focus(
        focusNode: editorFocusNode,
        autofocus: true,
        onKeyEvent: (node, event) => _onKey(context, ref, event),
        child: Column(
          children: [
            const Toolbar(),
            const Divider(height: 1),
            Expanded(
              child: Column(
                children: [
                  SizedBox(
                    height: rulerHeight,
                    child: Row(
                      children: [
                        const SizedBox(width: keyboardWidth),
                        const Expanded(child: RulerView()),
                        SizedBox(width: thickness),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        const SizedBox(
                          width: keyboardWidth,
                          child: KeyboardView(),
                        ),
                        const Expanded(child: NoteGrid()),
                        SizedBox(
                          width: thickness,
                          child: const AxisScrollbar(axis: Axis.vertical),
                        ),
                      ],
                    ),
                  ),
                  const VelocitySection(),
                  SizedBox(
                    height: thickness,
                    child: Row(
                      children: [
                        const SizedBox(width: keyboardWidth),
                        const Expanded(
                          child: AxisScrollbar(axis: Axis.horizontal),
                        ),
                        SizedBox(width: thickness),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
