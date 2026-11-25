import 'dart:convert';

import '../midi/midi_events.dart';
import 'note.dart';
import 'project.dart';
import 'track.dart';

class _OpenNote {
  _OpenNote(this.start, this.velocity);
  final int start;
  final int velocity;
}

/// Maps between raw MIDI events and the editable [Project] model.
class MidiConverter {
  const MidiConverter._();

  static Project fromMidiFile(MidiFile file, {String name = 'Untitled'}) {
    final tempos = <TempoChange>[];
    final sigs = <TimeSignatureChange>[];
    final keys = <KeySignatureChange>[];
    final conductorExtras = <MidiEvent>[];
    final tracks = <Track>[];

    for (final events in file.tracks) {
      String? trackName;
      final groups = <int, List<MidiEvent>>{};
      final others = <MidiEvent>[];
      var endTick = 0;

      for (final e in events) {
        if (e.tick > endTick) endTick = e.tick;
        if (e.isMeta) {
          switch (e.metaType) {
            case 0x51 when e.data.length == 3:
              tempos.add(
                TempoChange(
                  e.tick,
                  (e.data[0] << 16) | (e.data[1] << 8) | e.data[2],
                ),
              );
            case 0x58 when e.data.length >= 2:
              sigs.add(TimeSignatureChange(e.tick, e.data[0], e.data[1]));
            case 0x59 when e.data.length >= 2 && e.data[1] <= 1:
              final sf = e.data[0] > 127 ? e.data[0] - 256 : e.data[0];
              if (sf >= -7 && sf <= 7) {
                keys.add(KeySignatureChange(e.tick, sf, e.data[1] == 1));
              } else {
                others.add(e);
              }
            case 0x03:
              trackName ??= utf8.decode(e.data, allowMalformed: true);
            case 0x2F:
              break;
            default:
              others.add(e);
          }
        } else if (e.isSysex) {
          others.add(e);
        } else if (e.isChannel) {
          groups.putIfAbsent(e.channel, () => []).add(e);
        }
      }

      if (groups.isEmpty) {
        conductorExtras.addAll(others);
        continue;
      }

      final channels = groups.keys.toList()..sort();
      // Channels carrying only controllers (no notes) stay with a noted
      // channel's track rather than becoming empty tracks.
      bool hasNotes(int ch) =>
          groups[ch]!.any((e) => e.command == 0x90 || e.command == 0x80);
      final noted = channels.where(hasNotes).toList();
      if (noted.isNotEmpty && noted.length < channels.length) {
        for (final ch in channels.where((c) => !noted.contains(c))) {
          others.addAll(groups.remove(ch)!);
        }
        channels
          ..clear()
          ..addAll(noted);
      }
      for (var i = 0; i < channels.length; i++) {
        final ch = channels[i];
        final base = trackName ?? 'Track ${tracks.length + 1}';
        tracks.add(
          _buildTrack(
            groups[ch]!,
            i == 0 ? others : const [],
            channels.length > 1 ? '$base (Ch ${ch + 1})' : base,
            ch,
            endTick,
            file.division,
          ),
        );
      }
    }

    return Project(
      name: name,
      ppq: file.division,
      tempos: _normalizeTempos(tempos),
      timeSignatures: _normalizeSigs(sigs),
      keySignatures: _normalizeKeys(keys),
      tracks: tracks.isEmpty ? [Track.create(name: 'Track 1')] : tracks,
      conductorExtras: conductorExtras,
    );
  }

  static Track _buildTrack(
    List<MidiEvent> events,
    List<MidiEvent> others,
    String name,
    int channel,
    int endTick,
    int ppq,
  ) {
    int? program;
    final extras = [...others];
    final open = <int, List<_OpenNote>>{};
    final notes = <Note>[];

    void close(int pitch, int tick) {
      final queue = open[pitch];
      if (queue == null || queue.isEmpty) return;
      final o = queue.removeAt(0);
      notes.add(
        Note.create(
          pitch: pitch,
          start: o.start,
          duration: tick > o.start ? tick - o.start : 1,
          velocity: o.velocity,
        ),
      );
    }

    for (final e in events) {
      switch (e.command) {
        case 0x90 when e.data[1] > 0:
          open
              .putIfAbsent(e.data[0], () => [])
              .add(_OpenNote(e.tick, e.data[1]));
        case 0x90 || 0x80:
          close(e.data[0], e.tick);
        case 0xC0 when program == null && e.tick == 0:
          program = e.data[0];
        default:
          extras.add(e);
      }
    }

    // Notes that never receive a note-off run to the end of the track.
    open.forEach((pitch, queue) {
      for (final o in queue) {
        notes.add(
          Note.create(
            pitch: pitch,
            start: o.start,
            duration: endTick > o.start ? endTick - o.start : ppq,
            velocity: o.velocity,
          ),
        );
      }
    });

    notes.sort((a, b) {
      final s = a.start.compareTo(b.start);
      return s != 0 ? s : a.pitch.compareTo(b.pitch);
    });
    return Track.create(
      name: name,
      channel: channel,
      program: program ?? 0,
      notes: notes,
      extras: extras,
    );
  }

  static List<TempoChange> _normalizeTempos(List<TempoChange> input) {
    final byTick = <int, TempoChange>{};
    for (final t in input) {
      if (t.microsPerQuarter > 0) byTick[t.tick] = t;
    }
    final list = byTick.values.toList()
      ..sort((a, b) => a.tick.compareTo(b.tick));
    if (list.isEmpty || list.first.tick != 0) {
      list.insert(0, const TempoChange(0, 500000));
    }
    return list;
  }

  static List<TimeSignatureChange> _normalizeSigs(
    List<TimeSignatureChange> input,
  ) {
    final byTick = <int, TimeSignatureChange>{};
    for (final s in input) {
      if (s.numerator > 0 && s.denominatorPower <= 6) byTick[s.tick] = s;
    }
    final list = byTick.values.toList()
      ..sort((a, b) => a.tick.compareTo(b.tick));
    if (list.isEmpty || list.first.tick != 0) {
      list.insert(0, const TimeSignatureChange(0, 4, 2));
    }
    return list;
  }

  static List<KeySignatureChange> _normalizeKeys(
    List<KeySignatureChange> input,
  ) {
    final byTick = <int, KeySignatureChange>{};
    for (final k in input) {
      byTick[k.tick] = k;
    }
    final list = byTick.values.toList()
      ..sort((a, b) => a.tick.compareTo(b.tick));
    if (list.isEmpty || list.first.tick != 0) {
      list.insert(0, const KeySignatureChange(0, 0, false));
    }
    return list;
  }

  /// Builds a format 1 file: track 0 holds tempo/time signature, followed by
  /// one MIDI track per editor track.
  static MidiFile toMidiFile(Project p) {
    final conductor = <MidiEvent>[
      if (p.name.isNotEmpty) MidiEvent.meta(0, 0x03, utf8.encode(p.name)),
      for (final t in p.tempos)
        MidiEvent.meta(t.tick, 0x51, [
          (t.microsPerQuarter >> 16) & 0xFF,
          (t.microsPerQuarter >> 8) & 0xFF,
          t.microsPerQuarter & 0xFF,
        ]),
      for (final s in p.timeSignatures)
        MidiEvent.meta(s.tick, 0x58, [s.numerator, s.denominatorPower, 24, 8]),
      for (final k in p.keySignatures)
        MidiEvent.meta(k.tick, 0x59, [k.sharps & 0xFF, k.minor ? 1 : 0]),
      ...p.conductorExtras,
    ];

    final tracks = <List<MidiEvent>>[conductor];
    for (final t in p.tracks) {
      final status = t.channel & 0x0F;
      tracks.add([
        if (t.name.isNotEmpty) MidiEvent.meta(0, 0x03, utf8.encode(t.name)),
        MidiEvent.channel(0, 0xC0 | status, t.program),
        for (final n in t.notes) ...[
          MidiEvent.channel(n.start, 0x90 | status, n.pitch, n.velocity),
          MidiEvent.channel(n.end, 0x80 | status, n.pitch, 64),
        ],
        ...t.extras,
      ]);
    }
    return MidiFile(format: 1, division: p.ppq, tracks: tracks);
  }
}
