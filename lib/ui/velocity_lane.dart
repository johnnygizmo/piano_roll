import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/editing.dart';
import '../model/note.dart';
import '../model/project.dart';
import '../state/editor_provider.dart';
import '../state/project_provider.dart';
import 'constants.dart';
import 'interaction.dart';
import 'playhead.dart';

/// Velocity bars for the active track. Drag a bar to change velocity; if the
/// note is selected the whole selection moves by the same amount.
class VelocityLane extends ConsumerStatefulWidget {
  const VelocityLane({super.key});

  @override
  ConsumerState<VelocityLane> createState() => _VelocityLaneState();
}

class _VelocityLaneState extends ConsumerState<VelocityLane> {
  static const _hitRadius = 6.0;

  Map<int, Note> _originals = const {};
  Note? _anchor;
  double _height = velocityHeight;

  void _down(PointerDownEvent event) {
    editorFocusNode.requestFocus();
    final editor = ref.read(editorProvider);
    final project = ref.read(projectProvider).project;
    final track = project.trackById(editor.activeTrackId);
    if (track == null) return;

    Note? best;
    var bestDistance = _hitRadius + 1;
    for (final n in track.notes) {
      final x = editor.tickToX(n.start, project.ppq) - editor.scrollX;
      final d = (x - event.localPosition.dx).abs();
      if (d < bestDistance) {
        best = n;
        bestDistance = d;
      }
    }
    if (best == null) return;

    final inSelection = editor.selection.contains(best.id);
    _anchor = best;
    _originals = {
      for (final n in track.notes)
        if (n.id == best.id || (inSelection && editor.selection.contains(n.id))) n.id: n,
    };
    if (!inSelection) ref.read(editorProvider.notifier).setSelection({best.id});
    ref.read(projectProvider.notifier).beginGesture();
    _apply(event.localPosition.dy);
  }

  void _apply(double y) {
    final anchor = _anchor;
    final trackId = ref.read(editorProvider).activeTrackId;
    if (anchor == null || trackId == null) return;
    final target = ((1 - y / _height) * 127).round().clamp(1, 127);
    final delta = target - anchor.velocity;
    ref.read(projectProvider.notifier).updateGesture(
      (p) => Edits.replaceNotes(p, trackId, {
        for (final n in _originals.values)
          n.id: n.copyWith(velocity: (n.velocity + delta).clamp(1, 127)),
      }),
    );
  }

  void _up(PointerEvent event) {
    if (_anchor == null) return;
    _anchor = null;
    _originals = const {};
    ref.read(projectProvider.notifier).endGesture();
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(projectProvider.select((s) => s.project));
    final editor = ref.watch(editorProvider);
    final trackIndex = project.tracks.indexWhere((t) => t.id == editor.activeTrackId);
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        _height = constraints.maxHeight;
        return WheelRegion(
          child: Listener(
            onPointerDown: _down,
            onPointerMove: (e) => _apply(e.localPosition.dy),
            onPointerUp: _up,
            onPointerCancel: _up,
            child: ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(
                    painter: _VelocityPainter(
                      project: project,
                      trackIndex: trackIndex,
                      editor: editor,
                      background: scheme.surfaceContainerLow,
                    ),
                  ),
                  const PlayheadOverlay(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _VelocityPainter extends CustomPainter {
  _VelocityPainter({
    required this.project,
    required this.trackIndex,
    required this.editor,
    required this.background,
  });

  final Project project;
  final int trackIndex;
  final EditorState editor;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    if (trackIndex < 0) return;
    final ppq = project.ppq;
    final color = trackColor(trackIndex);
    final guide = Paint()
      ..color = const Color(0x22FFFFFF)
      ..strokeWidth = 1;
    for (final f in [0.25, 0.5, 0.75]) {
      final y = size.height * (1 - f);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), guide);
    }

    for (final n in project.tracks[trackIndex].notes) {
      final x = editor.tickToX(n.start, ppq) - editor.scrollX;
      if (x < -6 || x > size.width + 6) continue;
      final h = size.height * n.velocity / 127;
      final selected = editor.selection.contains(n.id);
      final fill = Paint()..color = selected ? Colors.white : color;
      canvas.drawRect(Rect.fromLTWH(x - 1.5, size.height - h, 3, h), fill);
      canvas.drawCircle(Offset(x, size.height - h), selected ? 4 : 3, fill);
    }
    canvas.drawLine(
      Offset(0, 0.5),
      Offset(size.width, 0.5),
      Paint()..color = Colors.white24,
    );
  }

  @override
  bool shouldRepaint(_VelocityPainter old) =>
      old.project != project ||
      old.trackIndex != trackIndex ||
      old.editor.scrollX != editor.scrollX ||
      old.editor.zoomX != editor.zoomX ||
      old.editor.selection != editor.selection;
}
