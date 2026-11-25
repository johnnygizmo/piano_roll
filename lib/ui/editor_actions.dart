import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../io/chord_detect.dart';
import '../io/file_io.dart';
import '../midi/midi_events.dart';
import '../model/chords.dart';
import '../model/editing.dart';
import '../model/musicxml.dart';
import '../model/note.dart';
import '../model/snap_and_grid.dart';
import '../state/editor_provider.dart';
import '../state/project_provider.dart';
import '../state/sheet_options_provider.dart';
import '../state/transport_provider.dart';
import 'interaction.dart';

/// User-level commands shared by the toolbar and keyboard shortcuts.
class EditorActions {
  EditorActions(this.context, this.ref);

  final BuildContext context;
  final WidgetRef ref;

  ProjectNotifier get _doc => ref.read(projectProvider.notifier);
  EditorNotifier get _view => ref.read(editorProvider.notifier);
  EditorState get _editor => ref.read(editorProvider);
  ProjectState get _state => ref.read(projectProvider);

  int? get _trackId => _editor.activeTrackId;

  List<Note> get _selectedNotes {
    final track = _state.project.trackById(_trackId);
    if (track == null) return const [];
    return [
      for (final n in track.notes)
        if (_editor.selection.contains(n.id)) n,
    ];
  }

  void _snack(String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _confirmDiscard() async {
    if (!_state.dirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard unsaved changes?'),
        content: const Text(
          'Your edits have not been exported to a .mid file.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> newProject() async {
    if (!await _confirmDiscard()) return;
    ref.read(transportProvider.notifier).stop();
    _doc.newProject();
  }

  Future<void> openFile() async {
    if (!await _confirmDiscard()) return;
    final picked = await pickMidiFile();
    if (picked == null) return;
    ref.read(transportProvider.notifier).stop();
    try {
      _doc.loadBytes(picked.bytes, picked.name);
      final warnings = _state.warnings;
      if (warnings.isNotEmpty) {
        _snack('Opened with ${warnings.length} warning(s): ${warnings.first}');
      }
    } on MidiFormatException catch (e) {
      _snack('Could not open "${picked.name}": ${e.message}');
    }
  }

  void exportFile() {
    final name = _state.project.name.trim().isEmpty
        ? 'untitled'
        : _state.project.name.trim();
    downloadBytes('$name.mid', _doc.exportBytes());
    _doc.markSaved();
    _snack('Exported $name.mid');
  }

  void showSheetMusic() {
    final options = ref.read(sheetOptionsProvider);
    final xml = projectToMusicXml(
      _state.project,
      options: options,
      chordDetector: tonalChordDetector(),
    );
    if (xml == null) {
      _snack('Nothing to show: no track has any notes.');
      return;
    }
    final name = _state.project.name.trim();
    if (!openSheetMusic(
      name.isEmpty ? 'untitled' : name,
      xml,
      showTitle: options.title,
      showStaffLabels: options.staffLabels,
    )) {
      _snack(
        'The browser blocked the sheet music tab. Allow pop-ups and retry.',
      );
    }
  }

  void undo() {
    _doc.undo();
    _pruneSelection();
  }

  void redo() {
    _doc.redo();
    _pruneSelection();
  }

  void _pruneSelection() {
    final track = _state.project.trackById(_trackId);
    final ids = {for (final n in track?.notes ?? const <Note>[]) n.id};
    final kept = _editor.selection.intersection(ids);
    if (kept.length != _editor.selection.length) _view.setSelection(kept);
  }

  void selectAll() {
    final track = _state.project.trackById(_trackId);
    if (track == null) return;
    _view.setSelection({for (final n in track.notes) n.id});
  }

  void deleteSelected() {
    final id = _trackId;
    final selection = _editor.selection;
    if (id == null || selection.isEmpty) return;
    _doc.apply((p) => Edits.removeNotes(p, id, selection));
    _view.clearSelection();
  }

  void copy() {
    final notes = _selectedNotes;
    if (notes.isEmpty) return;
    final first = notes.map((n) => n.start).reduce(math.min);
    _view.setClipboard([
      for (final n in notes) n.copyWith(start: n.start - first),
    ]);
  }

  void cut() {
    copy();
    deleteSelected();
  }

  void paste() {
    final id = _trackId;
    final clip = _editor.clipboard;
    if (id == null || clip.isEmpty) return;
    final ppq = _state.project.ppq;
    final at = _editor.snap.round(ref.read(transportProvider).tick, ppq);
    final pasted = [for (final n in clip) n.clone(start: n.start + at)];
    _doc.apply((p) => Edits.addNotes(p, id, pasted));
    _view.setSelection({for (final n in pasted) n.id});
  }

  void duplicate() {
    final id = _trackId;
    final notes = _selectedNotes;
    if (id == null || notes.isEmpty) return;
    final ppq = _state.project.ppq;
    final first = notes.map((n) => n.start).reduce(math.min);
    final last = notes.map((n) => n.end).reduce(math.max);
    final snap = _editor.snap.ticks(ppq);
    final shift = ((last - first + snap - 1) ~/ snap) * snap;
    final copies = [for (final n in notes) n.clone(start: n.start + shift)];
    _doc.apply((p) => Edits.addNotes(p, id, copies));
    _view.setSelection({for (final n in copies) n.id});
  }

  /// Moves selected notes by [dTick] ticks and [dPitch] semitones.
  void nudge({int dTick = 0, int dPitch = 0}) {
    final id = _trackId;
    final notes = _selectedNotes;
    if (id == null || notes.isEmpty) return;
    var dt = dTick;
    var dp = dPitch;
    dt = math.max(dt, -notes.map((n) => n.start).reduce(math.min));
    dp = dp.clamp(
      -notes.map((n) => n.pitch).reduce(math.min),
      127 - notes.map((n) => n.pitch).reduce(math.max),
    );
    if (dt == 0 && dp == 0) return;
    _doc.apply(
      (p) => Edits.replaceNotes(p, id, {
        for (final n in notes)
          n.id: n.copyWith(start: n.start + dt, pitch: n.pitch + dp),
      }),
    );
    if (dp != 0 && notes.length == 1) {
      final track = _state.project.trackById(id);
      auditionNote(ref, notes.first.pitch + dp, drum: track?.isDrum ?? false);
    }
  }

  int get snapTicks => _editor.snap.ticks(_state.project.ppq);

  /// Transposes every selected note by [semitones] (negative = down), or,
  /// with [copy], leaves them in place and adds transposed copies (which
  /// become the selection). Does nothing if any note would leave the MIDI
  /// range 0-127, so the intervals between the notes are never altered.
  void transposeSelection(int semitones, {bool copy = false}) {
    final id = _trackId;
    final track = _state.project.trackById(id);
    final notes = _selectedNotes;
    if (id == null || track == null || notes.isEmpty) return;
    if (notes.any(
      (n) => n.pitch + semitones < 0 || n.pitch + semitones > 127,
    )) {
      _snack(
        'Cannot transpose: some notes would leave the MIDI range (0-127).',
      );
      return;
    }

    final List<Note> moved;
    if (copy) {
      final taken = {for (final n in track.notes) (n.start, n.pitch)};
      moved = [
        for (final n in notes)
          if (!taken.contains((n.start, n.pitch + semitones)))
            n.clone(pitch: n.pitch + semitones),
      ];
      if (moved.isEmpty) {
        _snack('Nothing to add: those notes already exist there.');
        return;
      }
      _doc.apply((p) => Edits.addNotes(p, id, moved));
      _view.setSelection({for (final n in moved) n.id});
    } else {
      _doc.apply(
        (p) => Edits.replaceNotes(p, id, {
          for (final n in notes) n.id: n.copyWith(pitch: n.pitch + semitones),
        }),
      );
      moved = [for (final n in notes) n.copyWith(pitch: n.pitch + semitones)];
    }
    for (final n in moved.take(8)) {
      auditionNote(ref, n.pitch, velocity: n.velocity, drum: track.isDrum);
    }
  }

  /// Stacks a root-position chord on [root] (same start, duration, velocity).
  void generateChord(
    Note root,
    ChordQuality quality,
    ChordExtension extension,
  ) {
    final id = _trackId;
    final track = _state.project.trackById(id);
    if (id == null || track == null) return;
    final taken = {
      for (final n in track.notes)
        if (n.start == root.start) n.pitch,
    };
    final chord = [
      for (final n in buildChord(root, quality, extension))
        if (!taken.contains(n.pitch)) n,
    ];
    if (chord.isEmpty) {
      _snack(
        'Nothing to add: the chord tones already exist or are out of range.',
      );
      return;
    }
    _doc.apply((p) => Edits.addNotes(p, id, chord));
    _view.clearSelection();
    for (final n in [root, ...chord]) {
      auditionNote(ref, n.pitch, velocity: n.velocity, drum: track.isDrum);
    }
  }

  /// Step used by lengthen/shorten: the snap size, or a 1/128 note with snap off.
  int get resizeStep => _editor.snap == Snap.off
      ? math.max(1, _state.project.ppq ~/ 32)
      : snapTicks;

  /// Lengthens every selected note by one snap step.
  void lengthenSelected() {
    final step = resizeStep;
    _resizeSelected((n) => n.duration + step);
  }

  /// Shortens every selected note by one snap step; notes that would vanish
  /// (length <= 0) are left unchanged.
  void shortenSelected() {
    final step = resizeStep;
    _resizeSelected((n) => n.duration - step > 0 ? n.duration - step : null);
  }

  /// Gives every selected note exactly [ticks] length.
  void setSelectedLength(int ticks) {
    if (ticks < 1) return;
    _resizeSelected((n) => ticks);
  }

  void _resizeSelected(int? Function(Note) newDuration) {
    final id = _trackId;
    final notes = _selectedNotes;
    if (id == null || notes.isEmpty) return;
    final updates = <int, Note>{};
    for (final n in notes) {
      final d = newDuration(n);
      if (d != null && d != n.duration) updates[n.id] = n.copyWith(duration: d);
    }
    if (updates.isEmpty) {
      _snack('Nothing to resize.');
      return;
    }
    _doc.apply((p) => Edits.replaceNotes(p, id, updates));
  }

  void quantize() {
    final id = _trackId;
    final notes = _selectedNotes;
    if (id == null || notes.isEmpty) return;
    final ppq = _state.project.ppq;
    final snap = _editor.snap;
    _doc.apply(
      (p) => Edits.replaceNotes(p, id, {
        for (final n in notes)
          n.id: n.copyWith(start: math.max(0, snap.round(n.start, ppq))),
      }),
    );
  }

  Future<void> togglePlay() => ref.read(transportProvider.notifier).toggle();

  void stop() => ref.read(transportProvider.notifier).stop();

  void setSnap(Snap snap) => _view.setSnap(snap);

  /// Note lengths offered by the "Set Size" pie menu.
  List<({String label, int ticks})> get lengthChoices {
    final ppq = _state.project.ppq;
    return [
      (label: '1/1', ticks: ppq * 4),
      (label: '1/2', ticks: ppq * 2),
      for (final s in Snap.values)
        if (s != Snap.off) (label: s.label, ticks: s.ticks(ppq)),
    ];
  }

  bool get canPaste => _editor.clipboard.isNotEmpty;
}
