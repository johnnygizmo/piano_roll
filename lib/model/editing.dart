import 'note.dart';
import 'project.dart';
import 'track.dart';

/// Pure functions that produce edited copies of a [Project]. Keeping edits
/// pure lets undo/redo store whole-project snapshots cheaply (structural
/// sharing of immutable notes/tracks).
class Edits {
  const Edits._();

  static Project mapTrack(Project p, int trackId, Track Function(Track) f) => p
      .copyWith(tracks: [for (final t in p.tracks) t.id == trackId ? f(t) : t]);

  static Project addNotes(Project p, int trackId, Iterable<Note> notes) =>
      mapTrack(p, trackId, (t) => t.copyWith(notes: [...t.notes, ...notes]));

  /// Replaces notes (matched by id) with the given versions.
  static Project replaceNotes(Project p, int trackId, Map<int, Note> updates) =>
      mapTrack(
        p,
        trackId,
        (t) => t.copyWith(notes: [for (final n in t.notes) updates[n.id] ?? n]),
      );

  static Project removeNotes(Project p, int trackId, Set<int> ids) => mapTrack(
    p,
    trackId,
    (t) => t.copyWith(
      notes: [
        for (final n in t.notes)
          if (!ids.contains(n.id)) n,
      ],
    ),
  );

  static Project addTrack(Project p, Track track) =>
      p.copyWith(tracks: [...p.tracks, track]);

  static Project removeTrack(Project p, int trackId) => p.copyWith(
    tracks: [
      for (final t in p.tracks)
        if (t.id != trackId) t,
    ],
  );

  static Project setTempo(Project p, double bpm) {
    final micros = (60000000 / bpm.clamp(10, 400)).round();
    return p.copyWith(
      tempos: [TempoChange(0, micros), ...p.tempos.where((t) => t.tick != 0)],
    );
  }

  static Project setTimeSignature(
    Project p,
    int numerator,
    int denominatorPower,
  ) => p.copyWith(
    timeSignatures: [
      TimeSignatureChange(0, numerator, denominatorPower),
      ...p.timeSignatures.where((s) => s.tick != 0),
    ],
  );

  static Project setName(Project p, String name) => p.copyWith(name: name);
}
