import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/editor_provider.dart';
import '../state/project_provider.dart';
import 'constants.dart';

/// Thin scrollbar bound to the editor's shared scroll offsets.
class AxisScrollbar extends ConsumerWidget {
  const AxisScrollbar({super.key, required this.axis});

  final Axis axis;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editor = ref.watch(editorProvider);
    final project = ref.watch(projectProvider.select((s) => s.project));
    final horizontal = axis == Axis.horizontal;
    final viewport = horizontal ? editor.viewport.width : editor.viewport.height;
    final content = horizontal ? editor.contentWidth(project) : editor.contentHeight;
    final offset = horizontal ? editor.scrollX : editor.scrollY;
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final track = horizontal ? constraints.maxWidth : constraints.maxHeight;
        final ratio = content <= 0 ? 1.0 : math.min(1.0, viewport / content);
        final thumb = math.max(28.0, track * ratio);
        final range = math.max(1.0, content - viewport);
        final travel = math.max(0.0, track - thumb);
        final thumbPos = (offset / range * travel).clamp(0.0, travel);

        return GestureDetector(
          onPanUpdate: (d) {
            if (travel <= 0) return;
            final delta = (horizontal ? d.delta.dx : d.delta.dy) / travel * range;
            final view = ref.read(editorProvider.notifier);
            horizontal ? view.scrollBy(delta, 0) : view.scrollBy(0, delta);
          },
          child: Container(
            color: scheme.surfaceContainerLowest,
            child: Stack(
              children: [
                Positioned(
                  left: horizontal ? thumbPos : 2,
                  top: horizontal ? 2 : thumbPos,
                  width: horizontal ? thumb : scrollbarThickness - 4,
                  height: horizontal ? scrollbarThickness - 4 : thumb,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.onSurface.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
