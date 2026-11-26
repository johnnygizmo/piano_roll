import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/editing.dart';
import '../model/note.dart';
import '../model/project.dart';
import '../model/snap_and_grid.dart';
import '../model/track.dart';
import '../state/editor_provider.dart';
import '../state/project_provider.dart';
import 'constants.dart';
import 'generate_menu.dart';
import 'interaction.dart';
import 'playhead.dart';

enum _Mode { move, resize, marquee, erase, pan }

class _Drag {
  _Drag(
    this.mode,
    this.start, {
    this.anchor,
    this.originals = const {},
    this.baseSelection = const {},
  }) : startScroll = Offset.zero;

  final _Mode mode;
  Offset start;
  Note? anchor;
  Map<int, Note> originals;
  final Set<int> baseSelection;
  Offset startScroll;
  bool moved = false;

  /// Alt was held when the drag began, or a second finger was down.
  bool copyRequested = false;

  /// The selection has been duplicated and the copies are being dragged.
  bool copied = false;
  int lastDTick = 0;
  int lastDPitch = 0;
  int lastDDuration = 0;
}

/// The scrollable note canvas: grid, notes, and all mouse editing gestures.
class NoteGrid extends ConsumerStatefulWidget {
  const NoteGrid({super.key});

  @override
  ConsumerState<NoteGrid> createState() => _NoteGridState();
}

class _NoteGridState extends ConsumerState<NoteGrid> {
  _Drag? _drag;
  Rect? _marquee;
  Timer? _longPress;
  Offset _longPressStart = Offset.zero;
  int _dragPointer = -1;
  final _touchPointers = <int>{};
  final _touchPositions = <int, Offset>{};
  Offset? _pinchStart;
  Offset? _pinchStartSecond;
  bool? _pinchIsVertical;
  double? _pinchStartDistance;
  double? _pinchStartZoom;
  MouseCursor _cursor = SystemMouseCursors.basic;

  @override
  void dispose() {
    _longPress?.cancel();
    super.dispose();
  }

  Project get _project => ref.read(projectProvider).project;
  EditorState get _editor => ref.read(editorProvider);
  ProjectNotifier get _doc => ref.read(projectProvider.notifier);
  EditorNotifier get _view => ref.read(editorProvider.notifier);

  Track? get _track => _project.trackById(_editor.activeTrackId);

  Offset _toContent(Offset local) =>
      local + Offset(_editor.scrollX, _editor.scrollY);

  Rect _noteRect(Note n, EditorState e, int ppq) {
    final x0 = e.tickToX(n.start, ppq);
    final x1 = math.max(e.tickToX(n.end, ppq), x0 + 3);
    final y = e.pitchToY(n.pitch);
    return Rect.fromLTRB(x0, y, x1, y + e.zoomY);
  }

  Note? _noteAt(Offset content) {
    final track = _track;
    if (track == null) return null;
    final e = _editor;
    final ppq = _project.ppq;
    for (final n in track.notes.reversed) {
      if (_noteRect(n, e, ppq).contains(content)) return n;
    }
    return null;
  }

  bool _inResizeZone(Note n, Offset content) {
    final rect = _noteRect(n, _editor, _project.ppq);
    final zone = math.min(resizeHandleWidth, rect.width * 0.4);
    return content.dx >= rect.right - zone;
  }

  int get _minDuration {
    final e = _editor;
    return e.snap == Snap.off ? _project.ppq ~/ 32 : e.snap.ticks(_project.ppq);
  }

  void _openGenerateMenu(Offset globalPosition, Note note) {
    _cancelLongPress();
    showGenerateMenu(context, ref, position: globalPosition, note: note);
  }

  void _cancelLongPress() {
    _longPress?.cancel();
    _longPress = null;
  }

  // Touch has no right button: a long press on a note opens the same menu.
  void _startLongPress(PointerDownEvent event, Note note) {
    _cancelLongPress();
    _longPressStart = event.localPosition;
    _longPress = Timer(const Duration(milliseconds: 500), () {
      _longPress = null;
      if (!mounted || _drag?.moved == true) return;
      _drag = null;
      _doc.endGesture();
      _openGenerateMenu(event.position, note);
    });
  }

  void _onDown(PointerDownEvent event) {
    editorFocusNode.requestFocus();
    final isTouch = event.kind == PointerDeviceKind.touch;
    if (isTouch) {
      _touchPointers.add(event.pointer);
      _touchPositions[event.pointer] = event.localPosition;
      if (_editor.tool == EditTool.pan && _touchPositions.length == 2) {
        _cancelLongPress();
        _pinchStart = _touchPositions.values.first;
        _pinchStartSecond = _touchPositions.values.last;
        _pinchIsVertical = null;
        _pinchStartDistance = null;
        _pinchStartZoom = null;
      }
    }
    // An extra finger (or button) during a drag only modifies it: with two
    // fingers a move drag copies. It never starts a second gesture.
    if (_drag != null && event.pointer != _dragPointer) {
      _cancelLongPress();
      return;
    }
    _dragPointer = event.pointer;

    final track = _track;
    if (track == null) return;
    final content = _toContent(event.localPosition);
    final hit = _noteAt(content);
    final keys = HardwareKeyboard.instance;
    final additive =
        keys.isShiftPressed || keys.isControlPressed || keys.isMetaPressed;

    if (event.buttons & kMiddleMouseButton != 0) {
      _drag = _Drag(_Mode.pan, event.localPosition)
        ..startScroll = Offset(_editor.scrollX, _editor.scrollY);
      return;
    }
    if (event.buttons & kSecondaryMouseButton != 0) {
      if (hit != null) _openGenerateMenu(event.position, hit);
      return;
    }

    final tool = _editor.tool;
    if (tool == EditTool.pan) {
      _drag = _Drag(_Mode.pan, event.localPosition)
        ..startScroll = Offset(_editor.scrollX, _editor.scrollY);
      return;
    }
    if (tool == EditTool.erase) {
      _doc.beginGesture();
      _drag = _Drag(_Mode.erase, event.localPosition);
      _eraseAt(content);
      return;
    }

    if (hit != null) {
      var selection = _editor.selection;
      if (!selection.contains(hit.id)) {
        selection = additive ? {...selection, hit.id} : {hit.id};
        _view.setSelection(selection);
      } else if (additive) {
        selection = selection.difference({hit.id});
        _view.setSelection(selection);
      }
      if (!selection.contains(hit.id)) return;
      final originals = {
        for (final n in track.notes)
          if (selection.contains(n.id)) n.id: n,
      };
      _doc.beginGesture();
      _drag = _Drag(
        _inResizeZone(hit, content) ? _Mode.resize : _Mode.move,
        event.localPosition,
        anchor: hit,
        originals: originals,
      )..copyRequested = keys.isAltPressed;
      auditionNote(ref, hit.pitch, velocity: hit.velocity, drum: track.isDrum);
      if (event.kind == PointerDeviceKind.touch) _startLongPress(event, hit);
      return;
    }

    if (tool == EditTool.draw) {
      final ppq = _project.ppq;
      final e = _editor;
      final start = math.max(0, e.snap.floor(e.xToTick(content.dx, ppq), ppq));
      final duration =
          e.lastDuration ?? (e.snap == Snap.off ? ppq ~/ 4 : e.snap.ticks(ppq));
      final note = Note.create(
        pitch: e.yToPitch(content.dy),
        start: start,
        duration: duration,
      );
      _doc.beginGesture();
      _doc.updateGesture((p) => Edits.addNotes(p, track.id, [note]));
      _view.setSelection({note.id});
      _drag = _Drag(
        _Mode.resize,
        event.localPosition,
        anchor: note,
        originals: {note.id: note},
      )..moved = true;
      auditionNote(ref, note.pitch, drum: track.isDrum);
      return;
    }

    _drag = _Drag(
      _Mode.marquee,
      event.localPosition,
      baseSelection: additive ? _editor.selection : const {},
    );
    if (!additive) _view.clearSelection();
  }

  void _eraseAt(Offset content) {
    final hit = _noteAt(content);
    final track = _track;
    if (hit == null || track == null) return;
    _doc.updateGesture((p) => Edits.removeNotes(p, track.id, {hit.id}));
    _view.setSelection(_editor.selection.difference({hit.id}));
  }

  void _onMove(PointerMoveEvent event) {
    if (_touchPositions.containsKey(event.pointer)) {
      _touchPositions[event.pointer] = event.localPosition;
    }
    if (_pinchStart != null &&
        _touchPositions.length >= 2 &&
        _touchPositions.containsKey(event.pointer) &&
        _editor.tool == EditTool.pan) {
      _applyPinch();
      return;
    }
    final drag = _drag;
    if (drag == null || event.pointer != _dragPointer) return;
    if (_longPress != null &&
        (event.localPosition - _longPressStart).distance > 8) {
      _cancelLongPress();
    }
    final e = _editor;
    final ppq = _project.ppq;

    switch (drag.mode) {
      case _Mode.pan:
        final d = event.localPosition - drag.start;
        _view.scrollTo(drag.startScroll.dx - d.dx, drag.startScroll.dy - d.dy);
      case _Mode.erase:
        _eraseAt(_toContent(event.localPosition));
      case _Mode.marquee:
        final rect = Rect.fromPoints(
          _toContent(drag.start),
          _toContent(event.localPosition),
        );
        final track = _track;
        if (track == null) return;
        final inside = <int>{
          for (final n in track.notes)
            if (_noteRect(n, e, ppq).overlaps(rect)) n.id,
        };
        _view.setSelection({...drag.baseSelection, ...inside});
        setState(() => _marquee = rect.shift(-Offset(e.scrollX, e.scrollY)));
      case _Mode.move:
        _applyMove(drag, event.localPosition);
      case _Mode.resize:
        _applyResize(drag, event.localPosition);
    }
  }

  void _applyPinch() {
    final start = _pinchStart;
    final startSecond = _pinchStartSecond;
    if (start == null || startSecond == null) return;
    final positions = _touchPositions.values.take(2).toList();
    if (positions.length < 2) return;
    final first = positions[0];
    final second = positions[1];
    final horizontalDistance = (second.dx - first.dx).abs();
    final verticalDistance = (second.dy - first.dy).abs();
    final startHorizontalDistance = (startSecond.dx - start.dx).abs();
    final startVerticalDistance = (startSecond.dy - start.dy).abs();

    if (_pinchIsVertical == null) {
      final horizontalChange = (horizontalDistance - startHorizontalDistance)
          .abs();
      final verticalChange = (verticalDistance - startVerticalDistance).abs();
      if (math.max(horizontalChange, verticalChange) < 4) return;
      _pinchIsVertical = verticalChange > horizontalChange;
      final vertical = _pinchIsVertical!;
      _pinchStartDistance = vertical ? verticalDistance : horizontalDistance;
      final editor = _editor;
      _pinchStartZoom = vertical ? editor.zoomY : editor.zoomX;
      return;
    }

    final vertical = _pinchIsVertical!;
    final distance = vertical ? verticalDistance : horizontalDistance;
    var startDistance = _pinchStartDistance!;
    if (startDistance <= 1) {
      if (distance <= 1) return;
      _pinchStartDistance = distance;
      _pinchStartZoom = vertical ? _editor.zoomY : _editor.zoomX;
      return;
    }
    final startZoom = _pinchStartZoom!;
    final factor = distance / startDistance;
    final focus = vertical
        ? (first.dy + second.dy) / 2
        : (first.dx + second.dx) / 2;
    if (vertical) {
      _view.zoomYBy(startZoom * factor / _editor.zoomY, focus);
    } else {
      _view.zoomXBy(startZoom * factor / _editor.zoomX, focus);
    }
  }

  void _applyMove(_Drag drag, Offset pos) {
    final track = _track;
    final anchor = drag.anchor;
    if (track == null || anchor == null) return;
    final delta = pos - drag.start;
    if (!drag.moved && delta.distance < 3) return;
    drag.moved = true;

    final e = _editor;
    final ppq = _project.ppq;
    final rawTicks = delta.dx / e.zoomX * ppq;
    var dTick =
        e.snap.round((anchor.start + rawTicks).round(), ppq) - anchor.start;
    var dPitch = -(delta.dy / e.zoomY).round();

    final notes = drag.originals.values;
    dTick = math.max(dTick, -notes.map((n) => n.start).reduce(math.min));
    dPitch = dPitch.clamp(
      -notes.map((n) => n.pitch).reduce(math.min),
      127 - notes.map((n) => n.pitch).reduce(math.max),
    );
    if (dTick == drag.lastDTick && dPitch == drag.lastDPitch) return;
    final pitchChanged = dPitch != drag.lastDPitch;
    drag.lastDTick = dTick;
    drag.lastDPitch = dPitch;

    // Decided on the first real movement so a plain click never duplicates.
    if (!drag.copied &&
        (drag.copyRequested ||
            _touchPointers.length >= 2 ||
            HardwareKeyboard.instance.isAltPressed)) {
      _beginCopy(drag, track.id);
    }
    final targets = drag.originals.values;

    _doc.updateGesture(
      (p) => Edits.replaceNotes(p, track.id, {
        for (final n in targets)
          n.id: n.copyWith(start: n.start + dTick, pitch: n.pitch + dPitch),
      }),
    );
    if (pitchChanged) {
      auditionNote(
        ref,
        anchor.pitch + dPitch,
        velocity: anchor.velocity,
        drum: track.isDrum,
      );
    }
  }

  /// Leaves the original notes in place and continues the drag with fresh
  /// copies (selected), all within the same undoable gesture.
  void _beginCopy(_Drag drag, int trackId) {
    final anchor = drag.anchor!;
    final clones = {for (final n in drag.originals.values) n.id: n.clone()};
    _doc.updateGesture((p) => Edits.addNotes(p, trackId, clones.values));
    drag.anchor = clones[anchor.id];
    drag.originals = {for (final c in clones.values) c.id: c};
    drag.copied = true;
    _view.setSelection(drag.originals.keys.toSet());
  }

  void _applyResize(_Drag drag, Offset pos) {
    final track = _track;
    final anchor = drag.anchor;
    if (track == null || anchor == null) return;
    final delta = pos - drag.start;
    if (!drag.moved && delta.distance < 3) return;
    drag.moved = true;

    final e = _editor;
    final ppq = _project.ppq;
    final newEnd = e.snap.round(
      (anchor.end + delta.dx / e.zoomX * ppq).round(),
      ppq,
    );
    final newDuration = math.max(_minDuration, newEnd - anchor.start);
    final dDuration = newDuration - anchor.duration;
    if (dDuration == drag.lastDDuration) return;
    drag.lastDDuration = dDuration;

    _doc.updateGesture(
      (p) => Edits.replaceNotes(p, track.id, {
        for (final n in drag.originals.values)
          n.id: n.copyWith(
            duration: math.max(_minDuration, n.duration + dDuration),
          ),
      }),
    );
  }

  void _onUp(PointerEvent event) {
    _touchPointers.remove(event.pointer);
    _touchPositions.remove(event.pointer);
    if (_pinchStart != null && _touchPositions.length < 2) {
      _pinchStart = null;
      _pinchStartSecond = null;
      _pinchIsVertical = null;
      _pinchStartDistance = null;
      _pinchStartZoom = null;
      final remaining = _touchPositions.values.firstOrNull;
      final drag = _drag;
      if (remaining != null && drag?.mode == _Mode.pan) {
        drag!
          ..startScroll = Offset(_editor.scrollX, _editor.scrollY)
          ..start = remaining;
      }
    }
    // Lifting an extra finger must not end the drag of the primary pointer.
    if (event.pointer != _dragPointer) return;
    _cancelLongPress();
    final drag = _drag;
    _drag = null;
    if (drag == null) return;
    final e = _editor;

    if (drag.mode == _Mode.marquee) {
      setState(() => _marquee = null);
      return;
    }
    if (drag.mode == _Mode.pan) return;
    _doc.endGesture();

    final anchor = drag.anchor;
    if (anchor == null) return;
    if (drag.mode == _Mode.resize) {
      final updated = _track?.notes.where((n) => n.id == anchor.id).firstOrNull;
      if (updated != null) _view.setLastDuration(updated.duration);
    }
    // A plain click on one of several selected notes narrows the selection.
    final keys = HardwareKeyboard.instance;
    final additive =
        keys.isShiftPressed || keys.isControlPressed || keys.isMetaPressed;
    if (!drag.moved &&
        !additive &&
        e.selection.length > 1 &&
        drag.mode == _Mode.move) {
      _view.setSelection({anchor.id});
    }
  }

  void _onHover(PointerHoverEvent event) {
    final hit = _noteAt(_toContent(event.localPosition));
    final MouseCursor cursor;
    if (hit != null &&
        _editor.tool != EditTool.erase &&
        _editor.tool != EditTool.pan) {
      cursor = _inResizeZone(hit, _toContent(event.localPosition))
          ? SystemMouseCursors.resizeLeftRight
          : HardwareKeyboard.instance.isAltPressed
          ? SystemMouseCursors.copy
          : SystemMouseCursors.move;
    } else {
      cursor = switch (_editor.tool) {
        EditTool.draw => SystemMouseCursors.precise,
        EditTool.erase => SystemMouseCursors.disappearing,
        EditTool.select => SystemMouseCursors.basic,
        EditTool.pan => SystemMouseCursors.grab,
      };
    }
    if (cursor != _cursor) setState(() => _cursor = cursor);
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(projectProvider.select((s) => s.project));
    final editor = ref.watch(editorProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (size != editor.viewport) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _view.setViewport(size);
          });
        }
        return WheelRegion(
          child: MouseRegion(
            cursor: _cursor,
            onHover: _onHover,
            child: Listener(
              onPointerDown: _onDown,
              onPointerMove: _onMove,
              onPointerUp: _onUp,
              onPointerCancel: _onUp,
              child: ClipRect(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CustomPaint(
                      painter: _GridPainter(
                        project: project,
                        editor: editor,
                        marquee: _marquee,
                        scheme: Theme.of(context).colorScheme,
                      ),
                    ),
                    const PlayheadOverlay(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.project,
    required this.editor,
    required this.marquee,
    required this.scheme,
  });

  final Project project;
  final EditorState editor;
  final Rect? marquee;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final e = editor;
    final ppq = project.ppq;
    final offX = e.scrollX;
    final offY = e.scrollY;

    // Pitch rows.
    final topPitch = (pitchCount - 1 - (offY / e.zoomY).floor()).clamp(
      0,
      pitchCount - 1,
    );
    final bottomPitch =
        (pitchCount - 1 - ((offY + size.height) / e.zoomY).floor()).clamp(
          0,
          pitchCount - 1,
        );
    final white = Paint()..color = const Color(0xFF26262B);
    final black = Paint()..color = const Color(0xFF1C1C20);
    final rowLine = Paint()
      ..color = const Color(0x22FFFFFF)
      ..strokeWidth = 1;
    final octaveLine = Paint()
      ..color = const Color(0x55FFFFFF)
      ..strokeWidth = 1;
    for (var pitch = bottomPitch; pitch <= topPitch; pitch++) {
      final y = e.pitchToY(pitch) - offY;
      canvas.drawRect(
        Rect.fromLTWH(0, y, size.width, e.zoomY),
        isBlackKey(pitch) ? black : white,
      );
      final bottom = y + e.zoomY;
      canvas.drawLine(
        Offset(0, bottom),
        Offset(size.width, bottom),
        pitch % 12 == 0 ? octaveLine : rowLine,
      );
    }

    // Time grid.
    final t0 = e.xToTick(offX, ppq);
    final t1 = e.xToTick(offX + size.width, ppq);
    final barPaint = Paint()
      ..color = const Color(0x99FFFFFF)
      ..strokeWidth = 1;
    final beatPaint = Paint()
      ..color = const Color(0x44FFFFFF)
      ..strokeWidth = 1;
    final subPaint = Paint()
      ..color = const Color(0x18FFFFFF)
      ..strokeWidth = 1;
    final showSub = e.zoomX >= 64;
    for (final line in gridLines(project, t0, t1)) {
      final x = e.tickToX(line.tick, ppq) - offX;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        line.isBar ? barPaint : beatPaint,
      );
      if (showSub) {
        for (var k = 1; k < 4; k++) {
          final sx = e.tickToX(line.tick + line.beatTicks * k ~/ 4, ppq) - offX;
          canvas.drawLine(Offset(sx, 0), Offset(sx, size.height), subPaint);
        }
      }
    }

    // Notes: other tracks ghosted, active track on top.
    final visible = Rect.fromLTWH(0, 0, size.width, size.height);
    for (var i = 0; i < project.tracks.length; i++) {
      final track = project.tracks[i];
      final active = track.id == e.activeTrackId;
      final color = trackColor(i);
      final paint = Paint();
      for (final n in track.notes) {
        if (n.end < t0 || n.start > t1) continue;
        final x0 = e.tickToX(n.start, ppq) - offX;
        final x1 = math.max(e.tickToX(n.end, ppq) - offX, x0 + 3);
        final y = e.pitchToY(n.pitch) - offY;
        final rect = Rect.fromLTRB(x0, y, x1, y + e.zoomY);
        if (!rect.overlaps(visible)) continue;
        if (!active) {
          paint.color = color.withValues(alpha: 0.22);
          canvas.drawRect(rect.deflate(0.5), paint);
          continue;
        }
        final selected = e.selection.contains(n.id);
        paint.color = selected
            ? Color.lerp(color, Colors.white, 0.45)!
            : Color.lerp(
                color.withValues(alpha: 0.55),
                color,
                n.velocity / 127,
              )!;
        final r = RRect.fromRectAndRadius(
          rect.deflate(0.75),
          const Radius.circular(2),
        );
        canvas.drawRRect(r, paint);
        canvas.drawRRect(
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = selected ? 1.5 : 1
            ..color = selected ? Colors.white : Colors.black54,
        );
      }
    }

    final m = marquee;
    if (m != null) {
      canvas.drawRect(
        m,
        Paint()..color = scheme.primary.withValues(alpha: 0.18),
      );
      canvas.drawRect(
        m,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = scheme.primary,
      );
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.project != project ||
      old.marquee != marquee ||
      old.editor.scrollX != editor.scrollX ||
      old.editor.scrollY != editor.scrollY ||
      old.editor.zoomX != editor.zoomX ||
      old.editor.zoomY != editor.zoomY ||
      old.editor.selection != editor.selection ||
      old.editor.activeTrackId != editor.activeTrackId;
}
