import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/editing.dart';
import '../model/snap_and_grid.dart';
import '../model/tempo_map.dart';
import '../state/editor_provider.dart';
import '../state/project_provider.dart';
import '../state/transport_provider.dart';
import 'editor_actions.dart';
import 'interaction.dart';

const _timeSignatures = <(int, int)>[(4, 2), (3, 2), (2, 2), (5, 2), (6, 3), (7, 3), (9, 3), (12, 3)];

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
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            _Btn(Icons.note_add_outlined, 'New (blank project)', actions.newProject),
            _Btn(Icons.folder_open, 'Open MIDI file (Ctrl+O)', actions.openFile),
            _Btn(Icons.download, 'Export .mid (Ctrl+S)', actions.exportFile),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                '${project.name}${state.dirty ? ' •' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const _Sep(),
            _Btn(Icons.undo, 'Undo (Ctrl+Z)', state.canUndo ? actions.undo : null),
            _Btn(Icons.redo, 'Redo (Ctrl+Y)', state.canRedo ? actions.redo : null),
            const _Sep(),
            SegmentedButton<EditTool>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: EditTool.select, icon: Icon(Icons.near_me, size: 18), tooltip: 'Select (V)'),
                ButtonSegment(value: EditTool.draw, icon: Icon(Icons.edit, size: 18), tooltip: 'Draw (D)'),
                ButtonSegment(value: EditTool.erase, icon: Icon(Icons.cleaning_services, size: 18), tooltip: 'Erase (E)'),
              ],
              selected: {editor.tool},
              onSelectionChanged: (s) => view.setTool(s.first),
            ),
            const SizedBox(width: 12),
            const Text('Snap '),
            DropdownButton<Snap>(
              value: editor.snap,
              underline: const SizedBox.shrink(),
              items: [for (final s in Snap.values) DropdownMenuItem(value: s, child: Text(s.label))],
              onChanged: (s) {
                if (s != null) view.setSnap(s);
                editorFocusNode.requestFocus();
              },
            ),
            const _Sep(),
            _Btn(Icons.zoom_out, 'Zoom out time (Ctrl+wheel)', () => view.zoomXBy(1 / 1.3)),
            _Btn(Icons.zoom_in, 'Zoom in time (Ctrl+wheel)', () => view.zoomXBy(1.3)),
            _Btn(Icons.unfold_less, 'Shrink rows (Alt+wheel)', () => view.zoomYBy(1 / 1.2)),
            _Btn(Icons.unfold_more, 'Enlarge rows (Alt+wheel)', () => view.zoomYBy(1.2)),
            const _Sep(),
            _Btn(Icons.stop, 'Stop', actions.stop),
            _Btn(
              transport.playing ? Icons.pause : Icons.play_arrow,
              'Play / Pause (Space)',
              actions.togglePlay,
            ),
            const _PositionLabel(),
            const _Sep(),
            const Text('BPM '),
            _BpmField(bpm: project.tempos.first.bpm),
            const SizedBox(width: 12),
            DropdownButton<(int, int)>(
              value: _timeSignatures.contains((project.timeSignatures.first.numerator, project.timeSignatures.first.denominatorPower))
                  ? (project.timeSignatures.first.numerator, project.timeSignatures.first.denominatorPower)
                  : null,
              hint: Text('${project.timeSignatures.first.numerator}/${project.timeSignatures.first.denominator}'),
              underline: const SizedBox.shrink(),
              items: [
                for (final s in _timeSignatures) DropdownMenuItem(value: s, child: Text('${s.$1}/${1 << s.$2}')),
              ],
              onChanged: (s) {
                if (s != null) {
                  ref.read(projectProvider.notifier).apply((p) => Edits.setTimeSignature(p, s.$1, s.$2));
                }
                editorFocusNode.requestFocus();
              },
            ),
            const _Sep(),
            _Btn(Icons.help_outline, 'Keyboard shortcuts', () => _showHelp(context)),
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
            'Drag a note body to move, its right edge to resize.\n'
            'Right-click (or long-press) a note: pie menu to generate a chord from it.\n'
            'Middle-drag pans.\n'
            'Wheel scrolls; Shift+wheel scrolls sideways; Ctrl+wheel zooms time; Alt+wheel zooms rows.\n'
            'Drag velocity bars at the bottom to change velocity.\n'
            'Click the ruler to move the playhead.\n\n'
            'V / D / E: select / draw / erase tool\n'
            'Space: play/pause     Ctrl+O: open     Ctrl+S: export\n'
            'Ctrl+Z / Ctrl+Y: undo / redo\n'
            'Ctrl+A: select all     Delete: delete selection\n'
            'Ctrl+C / X / V: copy / cut / paste at playhead\n'
            'Ctrl+D: duplicate     Q: quantize selection\n'
            'Arrows: move selection (←/→ by snap, ↑/↓ by semitone)\n'
            'Shift+↑/↓: move by octave',
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
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
  Widget build(BuildContext context) => const SizedBox(height: 24, child: VerticalDivider(width: 20));
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
    final seconds = TempoMap(project.ppq, project.tempos).microsAtTick(tick) / 1e6;
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

class _BpmField extends ConsumerStatefulWidget {
  const _BpmField({required this.bpm});

  final double bpm;

  @override
  ConsumerState<_BpmField> createState() => _BpmFieldState();
}

class _BpmFieldState extends ConsumerState<_BpmField> {
  late final TextEditingController _controller = TextEditingController(text: _format(widget.bpm));
  late final FocusNode _focus = FocusNode()..addListener(_onFocus);

  static String _format(double bpm) =>
      bpm == bpm.roundToDouble() ? bpm.round().toString() : bpm.toStringAsFixed(1);

  void _onFocus() {
    if (!_focus.hasFocus) _commit();
  }

  void _commit() {
    final value = double.tryParse(_controller.text.trim());
    if (value == null || value <= 0) {
      _controller.text = _format(widget.bpm);
      return;
    }
    ref.read(projectProvider.notifier).apply((p) => Edits.setTempo(p, value));
  }

  @override
  void didUpdateWidget(_BpmField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && old.bpm != widget.bpm) {
      _controller.text = _format(widget.bpm);
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
        onSubmitted: (_) => editorFocusNode.requestFocus(),
      ),
    );
  }
}
