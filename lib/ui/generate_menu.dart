import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/chords.dart';
import '../model/editing.dart';
import '../model/intervals.dart';
import '../model/note.dart';
import '../state/editor_provider.dart';
import '../state/project_provider.dart';
import 'constants.dart';
import 'editor_actions.dart';
import 'interaction.dart';
import 'pie_menu.dart';

/// Pie menu opened on a note: Chord, Edit (cut/copy/paste/delete/resize) and
/// Transpose.
///
/// Edit and Transpose act on the whole selection; if the clicked note is not
/// part of it, the selection becomes just that note first.
Future<void> showGenerateMenu(
  BuildContext context,
  WidgetRef ref, {
  required Offset position,
  required Note note,
}) async {
  final actions = EditorActions(context, ref);
  final editor = ref.read(editorProvider.notifier);
  if (!ref.read(editorProvider).selection.contains(note.id)) {
    editor.setSelection({note.id});
  }

  await showPieMenu(
    context,
    center: position,
    title: pitchName(note.pitch),
    accessory: const _VelocityFader(),
    items: [
      PieItem(
        'Chord',
        children: [
          for (final quality in ChordQuality.values)
            PieItem(
              quality.label,
              children: [
                for (final extension in ChordExtension.values)
                  PieItem(
                    extension.label,
                    onSelected: () =>
                        actions.generateChord(note, quality, extension),
                  ),
              ],
            ),
        ],
      ),
      PieItem(
        'Edit',
        children: [
          PieItem('Cut', onSelected: actions.cut),
          PieItem('Copy', onSelected: actions.copy),
          PieItem(
            'Paste',
            enabled: actions.canPaste,
            onSelected: actions.paste,
          ),
          PieItem('Delete', onSelected: actions.deleteSelected),
          PieItem(
            'Resize',
            children: [
              PieItem('Lengthen', onSelected: actions.lengthenSelected),
              PieItem('Shorten', onSelected: actions.shortenSelected),
              PieItem(
                'Set Size',
                children: [
                  for (final choice in actions.lengthChoices)
                    PieItem(
                      choice.label,
                      onSelected: () => actions.setSelectedLength(choice.ticks),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
      PieItem(
        'Transpose',
        children: [
          for (final (label, direction, copy) in const [
            ('Up', 1, false),
            ('Down', -1, false),
            ('Copy Up', 1, true),
            ('Copy Down', -1, true),
          ])
            PieItem(
              label,
              children: [
                for (final interval in transposeIntervals)
                  PieItem(
                    interval.label,
                    onSelected: () => actions.transposeSelection(
                      direction * interval.semitones,
                      copy: copy,
                    ),
                  ),
              ],
            ),
        ],
      ),
    ],
  );
  editorFocusNode.requestFocus();
}

class _VelocityFader extends ConsumerStatefulWidget {
  const _VelocityFader();

  @override
  ConsumerState<_VelocityFader> createState() => _VelocityFaderState();
}

class _VelocityFaderState extends ConsumerState<_VelocityFader> {
  late final _doc = ref.read(projectProvider.notifier);
  bool _adjusting = false;

  @override
  void dispose() {
    if (_adjusting) _doc.endGesture();
    super.dispose();
  }

  void _start(double _) {
    _doc.beginGesture();
    _adjusting = true;
  }

  void _change(double value) {
    final editor = ref.read(editorProvider);
    final trackId = editor.activeTrackId;
    final track = ref.read(projectProvider).project.trackById(trackId);
    if (trackId == null || track == null) return;
    final velocity = value.round().clamp(1, 127);
    final replacements = {
      for (final note in track.notes)
        if (editor.selection.contains(note.id) && note.velocity != velocity)
          note.id: note.copyWith(velocity: velocity),
    };
    if (replacements.isEmpty) return;
    if (_adjusting) {
      _doc.updateGesture((p) => Edits.replaceNotes(p, trackId, replacements));
    } else {
      _doc.apply((p) => Edits.replaceNotes(p, trackId, replacements));
    }
  }

  void _end(double _) {
    if (!_adjusting) return;
    _adjusting = false;
    _doc.endGesture();
  }

  @override
  Widget build(BuildContext context) {
    final editor = ref.watch(editorProvider);
    final project = ref.watch(projectProvider.select((state) => state.project));
    final notes =
        project
            .trackById(editor.activeTrackId)
            ?.notes
            .where((note) => editor.selection.contains(note.id))
            .toList() ??
        [];
    final value = notes.isEmpty
        ? 1
        : (notes.fold<int>(0, (sum, note) => sum + note.velocity) /
                  notes.length)
              .round();
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surfaceContainerHigh.withValues(alpha: 0.96),
      elevation: 8,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Text(
              'VEL',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            Expanded(
              child: RotatedBox(
                quarterTurns: 3,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 6,
                    activeTrackColor: scheme.primary,
                    inactiveTrackColor: scheme.surfaceContainerHighest,
                    overlayColor: scheme.primary.withValues(alpha: 0.15),
                    thumbShape: _VelocityThumb(value, scheme),
                    tickMarkShape: SliderTickMarkShape.noTickMark,
                  ),
                  child: Semantics(
                    label: 'Selected notes velocity',
                    child: Slider(
                      value: value.toDouble(),
                      min: 1,
                      max: 127,
                      divisions: 126,
                      semanticFormatterCallback: (v) => '${v.round()}',
                      onChangeStart: notes.isEmpty ? null : _start,
                      onChanged: notes.isEmpty ? null : _change,
                      onChangeEnd: notes.isEmpty ? null : _end,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VelocityThumb extends SliderComponentShape {
  const _VelocityThumb(this.value, this.scheme);

  final int value;
  final ColorScheme scheme;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(26, 48);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    bool isDiscrete = false,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    double textScaleFactor = 1,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(math.pi / 2);
    final rect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-24, -13, 48, 26),
      const Radius.circular(7),
    );
    canvas.drawRRect(rect, Paint()..color = scheme.surfaceContainerHighest);
    canvas.drawRRect(
      rect,
      Paint()
        ..color = scheme.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final text = TextPainter(
      text: TextSpan(
        text: '${this.value}',
        style: TextStyle(
          color: scheme.onSurface,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: textDirection,
    )..layout();
    text.paint(canvas, Offset(-text.width / 2, -text.height / 2));
    canvas.restore();
  }
}
