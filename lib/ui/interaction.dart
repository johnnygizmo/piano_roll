import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/editor_provider.dart';
import '../state/transport_provider.dart';

/// Shared focus node so that clicking in the editor returns keyboard focus
/// from text fields (tempo, dialogs) to the shortcut handler.
final FocusNode editorFocusNode = FocusNode(debugLabel: 'editor');

/// Key of the page's Scaffold so the toolbar and the T shortcut can open the
/// tracks drawer.
final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>(
  debugLabel: 'scaffold',
);

/// Plays a short preview of [pitch] (used when clicking keys or editing notes).
void auditionNote(
  WidgetRef ref,
  int pitch, {
  int velocity = 100,
  bool drum = false,
}) {
  final audio = ref.read(audioProvider);
  audio.resume();
  audio.playNote(
    pitch: pitch,
    velocity: velocity,
    when: audio.currentTime,
    duration: 0.3,
    drum: drum,
  );
}

enum WheelAxis { both, verticalOnly }

/// Mouse-wheel scrolling and zoom for the editor viewport.
///
/// Wheel scrolls, Shift+wheel scrolls horizontally, Ctrl+wheel zooms time and
/// Alt+wheel zooms pitch rows.
class WheelRegion extends ConsumerWidget {
  const WheelRegion({
    super.key,
    required this.child,
    this.axis = WheelAxis.both,
  });

  final Widget child;
  final WheelAxis axis;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Listener(
      onPointerSignal: (event) {
        if (event is! PointerScrollEvent) return;
        // Registering claims the event so the browser does not zoom the page.
        GestureBinding.instance.pointerSignalResolver.register(event, (e) {
          final scroll = e as PointerScrollEvent;
          final editor = ref.read(editorProvider.notifier);
          final keys = HardwareKeyboard.instance;
          final dx = scroll.scrollDelta.dx;
          final dy = scroll.scrollDelta.dy;
          if (keys.isControlPressed || keys.isMetaPressed) {
            if (axis == WheelAxis.verticalOnly) {
              editor.zoomYBy(_factor(dy), scroll.localPosition.dy);
            } else {
              editor.zoomXBy(_factor(dy), scroll.localPosition.dx);
            }
          } else if (keys.isAltPressed) {
            editor.zoomYBy(_factor(dy), scroll.localPosition.dy);
          } else if (axis == WheelAxis.verticalOnly) {
            editor.scrollBy(0, dy);
          } else if (keys.isShiftPressed) {
            editor.scrollBy(dx != 0 ? dx : dy, 0);
          } else {
            editor.scrollBy(dx, dy);
          }
        });
      },
      child: child,
    );
  }

  double _factor(double dy) => dy < 0 ? 1.15 : 1 / 1.15;
}
