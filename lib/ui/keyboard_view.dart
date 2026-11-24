import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/editor_provider.dart';
import '../state/project_provider.dart';
import 'constants.dart';
import 'interaction.dart';

/// Piano keys on the left edge. Click a key to preview the pitch.
class KeyboardView extends ConsumerWidget {
  const KeyboardView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editor = ref.watch(editorProvider);
    final isDrum = ref.watch(
      projectProvider.select((s) => s.project.trackById(editor.activeTrackId)?.isDrum ?? false),
    );
    return WheelRegion(
      axis: WheelAxis.verticalOnly,
      child: Listener(
        onPointerDown: (e) {
          editorFocusNode.requestFocus();
          final pitch = editor.yToPitch(e.localPosition.dy + editor.scrollY);
          auditionNote(ref, pitch, drum: isDrum);
        },
        child: ClipRect(
          child: CustomPaint(
            painter: _KeyboardPainter(editor.scrollY, editor.zoomY),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _KeyboardPainter extends CustomPainter {
  _KeyboardPainter(this.scrollY, this.zoomY);

  final double scrollY;
  final double zoomY;

  @override
  void paint(Canvas canvas, Size size) {
    final topPitch = (pitchCount - 1 - (scrollY / zoomY).floor()).clamp(0, pitchCount - 1);
    final bottomPitch = (pitchCount - 1 - ((scrollY + size.height) / zoomY).floor()).clamp(0, pitchCount - 1);
    final whitePaint = Paint()..color = const Color(0xFFEDEDED);
    final blackPaint = Paint()..color = const Color(0xFF222222);
    final border = Paint()
      ..color = const Color(0xFF888888)
      ..strokeWidth = 1;

    for (var pitch = bottomPitch; pitch <= topPitch; pitch++) {
      final y = (pitchCount - 1 - pitch) * zoomY - scrollY;
      final black = isBlackKey(pitch);
      final rect = Rect.fromLTWH(0, y, black ? size.width * 0.62 : size.width, zoomY);
      if (black) {
        canvas.drawRect(Rect.fromLTWH(0, y, size.width, zoomY), whitePaint);
      }
      canvas.drawRect(rect, black ? blackPaint : whitePaint);
      canvas.drawLine(Offset(0, y + zoomY), Offset(size.width, y + zoomY), border);
      if (pitch % 12 == 0 && zoomY >= 10) {
        final tp = TextPainter(
          text: TextSpan(
            text: pitchName(pitch),
            style: const TextStyle(color: Color(0xFF333333), fontSize: 10),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(size.width - tp.width - 4, y + (zoomY - tp.height) / 2));
      }
    }
  }

  @override
  bool shouldRepaint(_KeyboardPainter old) => old.scrollY != scrollY || old.zoomY != zoomY;
}
