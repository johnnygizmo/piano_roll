import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One slice of a pie menu. A slice with [children] opens a sub-ring;
/// otherwise selecting it closes the menu and calls [onSelected].
class PieItem {
  const PieItem(
    this.label, {
    this.children = const [],
    this.onSelected,
    this.enabled = true,
  });

  final String label;
  final List<PieItem> children;
  final VoidCallback? onSelected;
  final bool enabled;
}

/// Geometry shared by the painter, hit testing and tests.
class PieLayout {
  const PieLayout._();

  static const double innerRadius = 40;
  static const double smallOuter = 110;
  static const double largeOuter = 170;

  /// Rings with more slices than this use the larger radius.
  static const int largeRingThreshold = 6;

  static double outerRadiusFor(int count) =>
      count > largeRingThreshold ? largeOuter : smallOuter;

  /// Keeps the largest ring fully on screen; the centre stays fixed while
  /// the user moves between rings.
  static Offset clampCenter(Offset center, Size screen) {
    const margin = largeOuter + 8;
    return Offset(
      center.dx.clamp(
        math.min(margin, screen.width / 2),
        math.max(screen.width - margin, screen.width / 2),
      ),
      center.dy.clamp(
        math.min(margin, screen.height / 2),
        math.max(screen.height - margin, screen.height / 2),
      ),
    );
  }

  /// Slice 0 is centred at the top; slices continue clockwise.
  static double midAngle(int index, int count) =>
      -math.pi / 2 + index * 2 * math.pi / count;

  /// Position of the label (and the middle of the slice) for [index].
  static Offset sliceCenter(Offset center, int count, int index) {
    final radius = (innerRadius + outerRadiusFor(count)) / 2;
    final a = midAngle(index, count);
    return center + Offset(math.cos(a), math.sin(a)) * radius;
  }

  /// Slice under [local] (relative to the ring centre), -1 for the hub or
  /// -2 when outside the ring.
  static int hitTest(Offset local, int count) {
    final d = local.distance;
    if (d < innerRadius) return -1;
    if (d > outerRadiusFor(count)) return -2;
    final sweep = 2 * math.pi / count;
    var a = math.atan2(local.dy, local.dx) + math.pi / 2 + sweep / 2;
    a = a % (2 * math.pi);
    if (a < 0) a += 2 * math.pi;
    return (a / sweep).floor() % count;
  }
}

/// Shows a pie menu centred near [center] (global coordinates).
Future<void> showPieMenu(
  BuildContext context, {
  required Offset center,
  required List<PieItem> items,
  String title = '',
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close menu',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (context, _, _) =>
        _PieMenuLayer(center: center, items: items, title: title),
    transitionBuilder: (context, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

class _PieMenuLayer extends StatefulWidget {
  const _PieMenuLayer({
    required this.center,
    required this.items,
    required this.title,
  });

  final Offset center;
  final List<PieItem> items;
  final String title;

  @override
  State<_PieMenuLayer> createState() => _PieMenuLayerState();
}

class _PieMenuLayerState extends State<_PieMenuLayer> {
  final _path = <PieItem>[];
  int _hover = -2;

  List<PieItem> get _items =>
      _path.isEmpty ? widget.items : _path.last.children;

  void _back() {
    if (_path.isEmpty) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _path.removeLast();
        _hover = -2;
      });
    }
  }

  void _tap(Offset local) {
    final index = PieLayout.hitTest(local, _items.length);
    if (index == -2) {
      Navigator.of(context).pop();
    } else if (index == -1) {
      _back();
    } else {
      final item = _items[index];
      if (!item.enabled) return;
      if (item.children.isNotEmpty) {
        setState(() {
          _path.add(item);
          _hover = -2;
        });
      } else {
        Navigator.of(context).pop();
        item.onSelected?.call();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final center = PieLayout.clampCenter(widget.center, size);
    const box = PieLayout.largeOuter;
    final scheme = Theme.of(context).colorScheme;
    final centerLabel = _path.isEmpty
        ? widget.title
        : _path.map((p) => p.label).join(' ');

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.of(context).pop();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.backspace) {
            _back();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Stack(
        children: [
          Positioned(
            left: center.dx - box,
            top: center.dy - box,
            width: box * 2,
            height: box * 2,
            child: MouseRegion(
              onHover: (e) {
                final h = PieLayout.hitTest(
                  e.localPosition - const Offset(box, box),
                  _items.length,
                );
                if (h != _hover) setState(() => _hover = h);
              },
              onExit: (_) => setState(() => _hover = -2),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) => _tap(d.localPosition - const Offset(box, box)),
                child: CustomPaint(
                  painter: _PiePainter(
                    items: _items,
                    hover: _hover,
                    centerLabel: centerLabel,
                    hasParent: _path.isNotEmpty,
                    scheme: scheme,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PiePainter extends CustomPainter {
  _PiePainter({
    required this.items,
    required this.hover,
    required this.centerLabel,
    required this.hasParent,
    required this.scheme,
  });

  final List<PieItem> items;
  final int hover;
  final String centerLabel;
  final bool hasParent;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final count = items.length;
    final outer = PieLayout.outerRadiusFor(count);
    final sweep = 2 * math.pi / count;
    final outerRect = Rect.fromCircle(center: c, radius: outer);
    final innerRect = Rect.fromCircle(center: c, radius: PieLayout.innerRadius);

    canvas.drawCircle(
      c,
      outer + 3,
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );

    for (var i = 0; i < count; i++) {
      final start = PieLayout.midAngle(i, count) - sweep / 2;
      final path = Path()
        ..arcTo(outerRect, start, sweep, true)
        ..arcTo(innerRect, start + sweep, -sweep, false)
        ..close();
      final item = items[i];
      final fill = !item.enabled
          ? scheme.surfaceContainerHighest.withValues(alpha: 0.6)
          : i == hover
          ? scheme.primary
          : scheme.surfaceContainerHigh;
      canvas.drawPath(path, Paint()..color = fill);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = scheme.surface,
      );
      _text(
        canvas,
        item.label + (item.children.isNotEmpty ? ' ›' : ''),
        PieLayout.sliceCenter(c, count, i),
        !item.enabled
            ? scheme.onSurface.withValues(alpha: 0.35)
            : i == hover
            ? scheme.onPrimary
            : scheme.onSurface,
        bold: i == hover,
      );
    }

    canvas.drawCircle(
      c,
      PieLayout.innerRadius,
      Paint()..color = hover == -1 ? scheme.secondary : scheme.surface,
    );
    _text(
      canvas,
      hasParent ? '‹ $centerLabel' : centerLabel,
      c,
      hover == -1 ? scheme.onSecondary : scheme.onSurface,
      maxWidth: PieLayout.innerRadius * 1.7,
      fontSize: 11,
    );
  }

  void _text(
    Canvas canvas,
    String text,
    Offset at,
    Color color, {
    bool bold = false,
    double maxWidth = 70,
    double fontSize = 13,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.bold : FontWeight.w500,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_PiePainter old) =>
      old.items != items ||
      old.hover != hover ||
      old.centerLabel != centerLabel ||
      old.scheme != scheme;
}
