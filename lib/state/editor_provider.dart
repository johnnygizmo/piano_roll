import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/note.dart';
import '../model/project.dart';
import '../model/snap_and_grid.dart';
import 'project_provider.dart';

enum EditTool { select, draw, erase }

const int pitchCount = 128;
const double minZoomX = 8; // pixels per quarter note
const double maxZoomX = 600;
const double minZoomY = 8; // pixels per semitone row
const double maxZoomY = 40;

/// View and selection state of the editor (not part of the document).
class EditorState {
  const EditorState({
    required this.activeTrackId,
    this.tool = EditTool.draw,
    this.snap = Snap.sixteenth,
    this.zoomX = 80,
    this.zoomY = 16,
    this.scrollX = 0,
    this.scrollY = 0,
    this.viewport = Size.zero,
    this.selection = const {},
    this.clipboard = const [],
    this.muted = const {},
    this.solo = const {},
    this.lastDuration,
  });

  final int? activeTrackId;
  final EditTool tool;
  final Snap snap;

  /// Horizontal zoom: pixels per quarter note.
  final double zoomX;

  /// Vertical zoom: pixels per semitone row.
  final double zoomY;
  final double scrollX;
  final double scrollY;

  /// Size of the note grid viewport.
  final Size viewport;

  /// Selected note ids (always within the active track).
  final Set<int> selection;

  /// Copied notes with starts relative to the earliest copied note.
  final List<Note> clipboard;
  final Set<int> muted;
  final Set<int> solo;

  /// Length of the most recently drawn note, reused for new notes.
  final int? lastDuration;

  EditorState copyWith({
    int? activeTrackId,
    EditTool? tool,
    Snap? snap,
    double? zoomX,
    double? zoomY,
    double? scrollX,
    double? scrollY,
    Size? viewport,
    Set<int>? selection,
    List<Note>? clipboard,
    Set<int>? muted,
    Set<int>? solo,
    int? lastDuration,
  }) => EditorState(
    activeTrackId: activeTrackId ?? this.activeTrackId,
    tool: tool ?? this.tool,
    snap: snap ?? this.snap,
    zoomX: zoomX ?? this.zoomX,
    zoomY: zoomY ?? this.zoomY,
    scrollX: scrollX ?? this.scrollX,
    scrollY: scrollY ?? this.scrollY,
    viewport: viewport ?? this.viewport,
    selection: selection ?? this.selection,
    clipboard: clipboard ?? this.clipboard,
    muted: muted ?? this.muted,
    solo: solo ?? this.solo,
    lastDuration: lastDuration ?? this.lastDuration,
  );

  double tickToX(int tick, int ppq) => tick / ppq * zoomX;
  int xToTick(double x, int ppq) => (x / zoomX * ppq).round();
  double pitchToY(int pitch) => (pitchCount - 1 - pitch) * zoomY;
  int yToPitch(double y) =>
      (pitchCount - 1 - (y / zoomY).floor()).clamp(0, pitchCount - 1);

  /// Total scrollable width in pixels for [project].
  double contentWidth(Project project) {
    final barTicks = project.ticksPerBar;
    final ticks = math.max(project.endTick + 8 * barTicks, 32 * barTicks);
    return ticks / project.ppq * zoomX;
  }

  double get contentHeight => pitchCount * zoomY;
}

class EditorNotifier extends Notifier<EditorState> {
  double? _pendingCenterPitch;

  @override
  EditorState build() {
    ref.listen<ProjectState>(projectProvider, (prev, next) {
      if (prev == null || prev.revision != next.revision) {
        _resetForDocument(next.project);
      } else if (next.project.trackById(state.activeTrackId) == null) {
        state = EditorState(
          activeTrackId: next.project.tracks.isEmpty ? null : next.project.tracks.first.id,
          tool: state.tool,
          snap: state.snap,
          zoomX: state.zoomX,
          zoomY: state.zoomY,
          scrollX: state.scrollX,
          scrollY: state.scrollY,
          viewport: state.viewport,
          clipboard: state.clipboard,
        );
      }
    });
    final project = ref.read(projectProvider).project;
    _pendingCenterPitch = _centerPitch(project);
    return EditorState(activeTrackId: project.tracks.first.id);
  }

  double _centerPitch(Project project) {
    var lo = 127, hi = 0;
    for (final n in project.tracks.expand((t) => t.notes)) {
      lo = math.min(lo, n.pitch);
      hi = math.max(hi, n.pitch);
    }
    return lo > hi ? 66 : (lo + hi) / 2;
  }

  void _resetForDocument(Project project) {
    _pendingCenterPitch = _centerPitch(project);
    state = EditorState(
      activeTrackId: project.tracks.first.id,
      tool: state.tool,
      snap: state.snap,
      zoomX: state.zoomX,
      zoomY: state.zoomY,
      viewport: state.viewport,
      clipboard: state.clipboard,
    );
    _applyPendingCenter();
  }

  void _applyPendingCenter() {
    final pitch = _pendingCenterPitch;
    if (pitch == null || state.viewport.height <= 0) return;
    _pendingCenterPitch = null;
    final y = (pitchCount - 1 - pitch) * state.zoomY + state.zoomY / 2;
    state = state.copyWith(
      scrollY: _clampY(y - state.viewport.height / 2, state.zoomY, state.viewport),
    );
  }

  double _clampY(double y, double zoomY, Size viewport) =>
      y.clamp(0, math.max(0, pitchCount * zoomY - viewport.height)).toDouble();

  double _clampX(double x, double zoomX, Size viewport) {
    final project = ref.read(projectProvider).project;
    final width = state.copyWith(zoomX: zoomX).contentWidth(project);
    return x.clamp(0, math.max(0, width - viewport.width)).toDouble();
  }

  void setViewport(Size size) {
    if (size == state.viewport) return;
    state = state.copyWith(viewport: size);
    _applyPendingCenter();
    state = state.copyWith(
      scrollX: _clampX(state.scrollX, state.zoomX, size),
      scrollY: _clampY(state.scrollY, state.zoomY, size),
    );
  }

  void setTool(EditTool tool) => state = state.copyWith(tool: tool);
  void setSnap(Snap snap) => state = state.copyWith(snap: snap);

  void selectTrack(int id) =>
      state = state.copyWith(activeTrackId: id, selection: const {});

  void setSelection(Set<int> ids) => state = state.copyWith(selection: ids);
  void clearSelection() => state = state.copyWith(selection: const {});
  void setClipboard(List<Note> notes) => state = state.copyWith(clipboard: notes);
  void setLastDuration(int ticks) => state = state.copyWith(lastDuration: ticks);

  void scrollBy(double dx, double dy) => scrollTo(state.scrollX + dx, state.scrollY + dy);

  void scrollTo(double x, double y) {
    state = state.copyWith(
      scrollX: _clampX(x, state.zoomX, state.viewport),
      scrollY: _clampY(y, state.zoomY, state.viewport),
    );
  }

  /// Zooms horizontally keeping the content under [focusX] (viewport pixels).
  void zoomXBy(double factor, [double? focusX]) {
    final fx = focusX ?? state.viewport.width / 2;
    final zoom = (state.zoomX * factor).clamp(minZoomX, maxZoomX).toDouble();
    final scale = zoom / state.zoomX;
    state = state.copyWith(
      zoomX: zoom,
      scrollX: _clampX((state.scrollX + fx) * scale - fx, zoom, state.viewport),
    );
  }

  void zoomYBy(double factor, [double? focusY]) {
    final fy = focusY ?? state.viewport.height / 2;
    final zoom = (state.zoomY * factor).clamp(minZoomY, maxZoomY).toDouble();
    final scale = zoom / state.zoomY;
    state = state.copyWith(
      zoomY: zoom,
      scrollY: _clampY((state.scrollY + fy) * scale - fy, zoom, state.viewport),
    );
  }

  void toggleMute(int trackId) => state = state.copyWith(
    muted: {...state.muted}..toggle(trackId),
  );

  void toggleSolo(int trackId) => state = state.copyWith(
    solo: {...state.solo}..toggle(trackId),
  );
}

extension on Set<int> {
  void toggle(int v) {
    if (!remove(v)) add(v);
  }
}

final editorProvider = NotifierProvider<EditorNotifier, EditorState>(
  EditorNotifier.new,
);
