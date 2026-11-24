import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/project.dart';
import '../model/snap_and_grid.dart';
import '../state/editor_provider.dart';
import '../state/project_provider.dart';
import '../state/transport_provider.dart';
import 'interaction.dart';
import 'playhead.dart';

/// Bar/beat ruler. Click or drag to move the playhead.
class RulerView extends ConsumerWidget {
  const RulerView({super.key});

  void _seek(WidgetRef ref, double localX) {
    final editor = ref.read(editorProvider);
    final ppq = ref.read(projectProvider).project.ppq;
    final tick = editor.snap.round(
      editor.xToTick(localX + editor.scrollX, ppq),
      ppq,
    );
    ref.read(transportProvider.notifier).seek(tick);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(projectProvider.select((s) => s.project));
    final editor = ref.watch(editorProvider);
    return WheelRegion(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) {
          editorFocusNode.requestFocus();
          _seek(ref, d.localPosition.dx);
        },
        onHorizontalDragUpdate: (d) => _seek(ref, d.localPosition.dx),
        child: ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: _RulerPainter(
                  project: project,
                  scrollX: editor.scrollX,
                  zoomX: editor.zoomX,
                  background: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHigh,
                  textColor: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const PlayheadOverlay(),
            ],
          ),
        ),
      ),
    );
  }
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({
    required this.project,
    required this.scrollX,
    required this.zoomX,
    required this.background,
    required this.textColor,
  });

  final Project project;
  final double scrollX;
  final double zoomX;
  final Color background;
  final Color textColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final ppq = project.ppq;
    double toX(int tick) => tick / ppq * zoomX - scrollX;
    final t0 = (scrollX / zoomX * ppq).round();
    final t1 = ((scrollX + size.width) / zoomX * ppq).round();
    final line = Paint()
      ..color = textColor.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    final beatPx = zoomX;
    for (final g in gridLines(project, t0, t1)) {
      final x = toX(g.tick);
      if (g.isBar) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
        final tp = TextPainter(
          text: TextSpan(
            text: '${g.barNumber}',
            style: TextStyle(color: textColor, fontSize: 11),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x + 4, 4));
      } else if (beatPx >= 24) {
        canvas.drawLine(
          Offset(x, size.height * 0.6),
          Offset(x, size.height),
          line,
        );
      }
    }
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      line,
    );
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.project != project || old.scrollX != scrollX || old.zoomX != zoomX;
}
