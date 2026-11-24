import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/editor_provider.dart';
import '../state/project_provider.dart';
import '../state/transport_provider.dart';

/// Vertical playhead line drawn over the grid. Isolated in its own widget so
/// playback only repaints this layer.
class PlayheadOverlay extends ConsumerWidget {
  const PlayheadOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tick = ref.watch(transportProvider.select((s) => s.tick));
    final scrollX = ref.watch(editorProvider.select((s) => s.scrollX));
    final zoomX = ref.watch(editorProvider.select((s) => s.zoomX));
    final ppq = ref.watch(projectProvider.select((s) => s.project.ppq));
    final x = tick / ppq * zoomX - scrollX;
    return IgnorePointer(
      child: CustomPaint(
        painter: _PlayheadPainter(x, Theme.of(context).colorScheme.secondary),
      ),
    );
  }
}

class _PlayheadPainter extends CustomPainter {
  _PlayheadPainter(this.x, this.color);

  final double x;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (x < 0 || x > size.width) return;
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = color
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_PlayheadPainter old) => old.x != x || old.color != color;
}
