import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/snap_and_grid.dart';
import '../model/tempo_map.dart';
import '../state/editor_provider.dart';
import '../state/project_provider.dart';
import '../state/transport_provider.dart';
import 'constants.dart';
import 'editor_actions.dart';
import 'interaction.dart';
import 'song_drawer.dart';

/// Shows which track is being edited (the drawer lists all tracks).
class _ActiveTrackChip extends StatelessWidget {
  const _ActiveTrackChip({required this.name, required this.color});

  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 160),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              name.isEmpty ? '(unnamed)' : name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class Toolbar extends ConsumerWidget {
  const Toolbar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = EditorActions(context, ref);
    final state = ref.watch(projectProvider);
    final editor = ref.watch(editorProvider);
    final view = ref.read(editorProvider.notifier);
    final transport = ref.watch(transportProvider);
    final project = state.project;

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _Btn(
                      Icons.queue_music,
                      'Tracks (T)',
                      () => scaffoldKey.currentState?.openDrawer(),
                    ),
                    _ActiveTrackChip(
                      name: project.trackById(editor.activeTrackId)?.name ?? '',
                      color: trackColor(
                        project.tracks.indexWhere(
                          (t) => t.id == editor.activeTrackId,
                        ),
                      ),
                    ),
                    const _Sep(),
                    _Btn(
                      Icons.undo,
                      'Undo (Ctrl+Z)',
                      state.canUndo ? actions.undo : null,
                    ),
                    _Btn(
                      Icons.redo,
                      'Redo (Ctrl+Y)',
                      state.canRedo ? actions.redo : null,
                    ),
                    const _Sep(),
                    SegmentedButton<EditTool>(
                      showSelectedIcon: false,
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                      ),
                      segments: const [
                        ButtonSegment(
                          value: EditTool.select,
                          icon: Icon(Icons.near_me, size: 18),
                          tooltip: 'Select (V)',
                        ),
                        ButtonSegment(
                          value: EditTool.draw,
                          icon: Icon(Icons.edit, size: 18),
                          tooltip: 'Draw (D)',
                        ),
                        ButtonSegment(
                          value: EditTool.erase,
                          icon: Icon(Icons.cleaning_services, size: 18),
                          tooltip: 'Erase (E)',
                        ),
                      ],
                      selected: {editor.tool},
                      onSelectionChanged: (s) => view.setTool(s.first),
                    ),
                    const SizedBox(width: 12),
                    const Text('Snap '),
                    DropdownButton<Snap>(
                      value: editor.snap,
                      underline: const SizedBox.shrink(),
                      items: [
                        for (final s in Snap.values)
                          DropdownMenuItem(value: s, child: Text(s.label)),
                      ],
                      onChanged: (s) {
                        if (s != null) view.setSnap(s);
                        editorFocusNode.requestFocus();
                      },
                    ),
                    const _Sep(),
                    _Btn(
                      Icons.zoom_out,
                      'Zoom out time (Ctrl+wheel)',
                      () => view.zoomXBy(1 / 1.3),
                    ),
                    _Btn(
                      Icons.zoom_in,
                      'Zoom in time (Ctrl+wheel)',
                      () => view.zoomXBy(1.3),
                    ),
                    _Btn(
                      Icons.unfold_less,
                      'Shrink rows (Alt+wheel)',
                      () => view.zoomYBy(1 / 1.2),
                    ),
                    _Btn(
                      Icons.unfold_more,
                      'Enlarge rows (Alt+wheel)',
                      () => view.zoomYBy(1.2),
                    ),
                    const _Sep(),
                    _Btn(Icons.stop, 'Stop', actions.stop),
                    _Btn(
                      transport.playing ? Icons.pause : Icons.play_arrow,
                      'Play / Pause (Space)',
                      actions.togglePlay,
                    ),
                    const _PositionLabel(),
                  ],
                ),
              ),
            ),
            const _Sep(),
            const SongDrawerButton(),
            _Btn(
              Icons.help_outline,
              'Keyboard shortcuts',
              () => _showHelp(context),
            ),
          ],
        ),
      ),
    );
  }

  void _showHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Shortcuts & mouse'),
        content: const SingleChildScrollView(
          child: Text(
            'Draw tool: click empty grid to add a note (drag to set length).\n'
            'Select tool: click/drag notes; drag empty space to marquee select.\n'
            'Drag a note body to move, its right edge to resize. Alt+drag (or two-finger drag) copies and moves.\n'
            'Right-click (or long-press) a note: pie menu to generate a chord, or transpose / copy-transpose the selection.\n'
            'Middle-drag pans.\n'
            'Wheel scrolls; Shift+wheel scrolls sideways; Ctrl+wheel zooms time; Alt+wheel zooms rows.\n'
            'Drag velocity bars at the bottom to change velocity.\n'
            'Click the ruler to move the playhead.\n\n'
            'V / D / E: select / draw / erase tool     T: tracks drawer\n'
            'Space: play/pause     Ctrl+O: open     Ctrl+S: export\n'
            'Ctrl+Z / Ctrl+Y: undo / redo\n'
            'Ctrl+A: select all     Delete: delete selection\n'
            'Ctrl+C / X / V: copy / cut / paste at playhead\n'
            'Ctrl+D: duplicate     Q: quantize selection\n'
            'Arrows: move selection (←/→ by snap, ↑/↓ by semitone)\n'
            'Shift+↑/↓: move by octave',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  const _Btn(this.icon, this.tooltip, this.onPressed);

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    icon: Icon(icon),
    tooltip: tooltip,
    visualDensity: VisualDensity.compact,
    onPressed: onPressed,
  );
}

class _Sep extends StatelessWidget {
  const _Sep();

  @override
  Widget build(BuildContext context) =>
      const SizedBox(height: 24, child: VerticalDivider(width: 20));
}

class _PositionLabel extends ConsumerWidget {
  const _PositionLabel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tick = ref.watch(transportProvider.select((s) => s.tick));
    final project = ref.watch(projectProvider.select((s) => s.project));

    var bar = 1;
    var beat = 1;
    for (final line in gridLines(project, 0, tick)) {
      if (line.tick > tick) break;
      bar = line.barNumber;
      beat = line.isBar ? 1 : beat + 1;
    }
    final seconds =
        TempoMap(project.ppq, project.tempos).microsAtTick(tick) / 1e6;
    final mm = (seconds ~/ 60).toString().padLeft(2, '0');
    final ss = (seconds % 60).toStringAsFixed(1).padLeft(4, '0');
    return SizedBox(
      width: 130,
      child: Text(
        '  $bar.$beat   $mm:$ss',
        style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
      ),
    );
  }
}
