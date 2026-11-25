import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/editor_provider.dart';
import '../state/project_provider.dart';
import 'constants.dart';
import 'interaction.dart';

/// Piano keys on the left edge. Tap a key to preview the pitch; drag up or
/// down to scroll the note grid vertically.
class KeyboardView extends ConsumerStatefulWidget {
  const KeyboardView({super.key});

  @override
  ConsumerState<KeyboardView> createState() => _KeyboardViewState();
}

class _KeyboardViewState extends ConsumerState<KeyboardView> {
  static const _dragSlop = 6.0;

  int _pointer = -1;
  Offset _downAt = Offset.zero;
  double _lastY = 0;
  bool _dragged = false;

  void _down(PointerDownEvent e) {
    editorFocusNode.requestFocus();
    if (_pointer != -1) return;
    _pointer = e.pointer;
    _downAt = e.localPosition;
    _lastY = e.localPosition.dy;
    _dragged = false;
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    if (!_dragged && (e.localPosition - _downAt).distance < _dragSlop) return;
    _dragged = true;
    ref.read(editorProvider.notifier).scrollBy(0, _lastY - e.localPosition.dy);
    _lastY = e.localPosition.dy;
  }

  void _up(PointerEvent e, {required bool isTap}) {
    if (e.pointer != _pointer) return;
    _pointer = -1;
    if (!isTap || _dragged) return;
    final editor = ref.read(editorProvider);
    final isDrum =
        ref
            .read(projectProvider)
            .project
            .trackById(editor.activeTrackId)
            ?.isDrum ??
        false;
    final pitch = editor.yToPitch(_downAt.dy + editor.scrollY);
    auditionNote(ref, pitch, drum: isDrum);
  }

  @override
  Widget build(BuildContext context) {
    final editor = ref.watch(editorProvider);
    return WheelRegion(
      axis: WheelAxis.verticalOnly,
      child: Listener(
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: (e) => _up(e, isTap: true),
        onPointerCancel: (e) => _up(e, isTap: false),
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
    final topPitch = (pitchCount - 1 - (scrollY / zoomY).floor()).clamp(
      0,
      pitchCount - 1,
    );
    final bottomPitch =
        (pitchCount - 1 - ((scrollY + size.height) / zoomY).floor()).clamp(
          0,
          pitchCount - 1,
        );
    final whitePaint = Paint()..color = const Color(0xFFEDEDED);
    final blackPaint = Paint()..color = const Color(0xFF222222);
    final border = Paint()
      ..color = const Color(0xFF888888)
      ..strokeWidth = 1;

    for (var pitch = bottomPitch; pitch <= topPitch; pitch++) {
      final y = (pitchCount - 1 - pitch) * zoomY - scrollY;
      final black = isBlackKey(pitch);
      final rect = Rect.fromLTWH(
        0,
        y,
        black ? size.width * 0.62 : size.width,
        zoomY,
      );
      if (black) {
        canvas.drawRect(Rect.fromLTWH(0, y, size.width, zoomY), whitePaint);
      }
      canvas.drawRect(rect, black ? blackPaint : whitePaint);
      canvas.drawLine(
        Offset(0, y + zoomY),
        Offset(size.width, y + zoomY),
        border,
      );
      if (pitch % 12 == 0 && zoomY >= 10) {
        final tp = TextPainter(
          text: TextSpan(
            text: pitchName(pitch),
            style: const TextStyle(color: Color(0xFF333333), fontSize: 10),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(size.width - tp.width - 4, y + (zoomY - tp.height) / 2),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_KeyboardPainter old) =>
      old.scrollY != scrollY || old.zoomY != zoomY;
}
