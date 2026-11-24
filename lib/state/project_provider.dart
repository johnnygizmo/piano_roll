import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../midi/midi_reader.dart';
import '../midi/midi_writer.dart';
import '../model/midi_converter.dart';
import '../model/project.dart';

/// Document state: the project plus undo/redo bookkeeping.
class ProjectState {
  const ProjectState({
    required this.project,
    this.dirty = false,
    this.canUndo = false,
    this.canRedo = false,
    this.warnings = const [],
    this.revision = 0,
  });

  final Project project;

  /// True when there are edits since the last load/export.
  final bool dirty;
  final bool canUndo;
  final bool canRedo;

  /// Non-fatal issues from the last import.
  final List<String> warnings;

  /// Incremented whenever a whole new document is loaded (used by the UI to
  /// reset selection and scroll).
  final int revision;
}

class ProjectNotifier extends Notifier<ProjectState> {
  static const _maxHistory = 200;

  final _undo = <Project>[];
  final _redo = <Project>[];
  Project? _gestureBase;

  @override
  ProjectState build() => ProjectState(project: Project.empty());

  ProjectState _next(
    Project project, {
    bool? dirty,
    List<String>? warnings,
    bool newDocument = false,
  }) => ProjectState(
    project: project,
    dirty: dirty ?? state.dirty,
    canUndo: _undo.isNotEmpty,
    canRedo: _redo.isNotEmpty,
    warnings: warnings ?? state.warnings,
    revision: newDocument ? state.revision + 1 : state.revision,
  );

  void newProject() {
    _resetHistory();
    state = _next(
      Project.empty(),
      dirty: false,
      warnings: const [],
      newDocument: true,
    );
  }

  /// Parses [bytes]; throws a MidiFormatException for unusable files.
  void loadBytes(Uint8List bytes, String fileName) {
    final file = MidiReader.parse(bytes);
    final base = fileName.replaceFirst(
      RegExp(r'\.midi?$', caseSensitive: false),
      '',
    );
    final project = MidiConverter.fromMidiFile(file, name: base);
    _resetHistory();
    state = _next(
      project,
      dirty: false,
      warnings: file.warnings,
      newDocument: true,
    );
  }

  Uint8List exportBytes() =>
      MidiWriter.write(MidiConverter.toMidiFile(state.project));

  void markSaved() => state = _next(state.project, dirty: false);

  /// Applies [edit] as one undoable step.
  void apply(Project Function(Project) edit) {
    final updated = edit(state.project);
    if (identical(updated, state.project)) return;
    _push(state.project);
    state = _next(updated, dirty: true);
  }

  /// Starts a multi-step gesture (drag). Intermediate [updateGesture] calls
  /// do not create history; [endGesture] records a single undo step.
  void beginGesture() => _gestureBase = state.project;

  void updateGesture(Project Function(Project) edit) {
    state = _next(edit(state.project), dirty: true);
  }

  void endGesture() {
    final base = _gestureBase;
    _gestureBase = null;
    if (base == null || identical(base, state.project)) return;
    _push(base);
    state = _next(state.project, dirty: true);
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(state.project);
    state = _next(_undo.removeLast(), dirty: true);
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(state.project);
    state = _next(_redo.removeLast(), dirty: true);
  }

  void _push(Project snapshot) {
    _undo.add(snapshot);
    if (_undo.length > _maxHistory) _undo.removeAt(0);
    _redo.clear();
  }

  void _resetHistory() {
    _undo.clear();
    _redo.clear();
    _gestureBase = null;
  }
}

final projectProvider = NotifierProvider<ProjectNotifier, ProjectState>(
  ProjectNotifier.new,
);
