import 'dart:typed_data';

import 'midi_events.dart';

/// Serialises a [MidiFile] to Standard MIDI File bytes.
class MidiWriter {
  const MidiWriter._();

  static Uint8List write(MidiFile file) {
    final out = BytesBuilder();
    out
      ..add(_ascii('MThd'))
      ..add(_u32(6))
      ..add(_u16(file.format))
      ..add(_u16(file.tracks.length))
      ..add(_u16(file.division));
    for (final track in file.tracks) {
      final body = _trackBytes(track);
      out
        ..add(_ascii('MTrk'))
        ..add(_u32(body.length))
        ..add(body);
    }
    return out.toBytes();
  }

  // Ordering of events sharing a tick: meta and setup first, note-offs before
  // note-ons so repeated notes retrigger instead of being cut short.
  static int _priority(MidiEvent e) {
    if (e.isMeta) return 0;
    if (e.isSysex) return 1;
    switch (e.command) {
      case 0x80:
        return 3;
      case 0x90:
        return e.data.length > 1 && e.data[1] == 0 ? 3 : 4;
      default:
        return 2;
    }
  }

  static Uint8List _trackBytes(List<MidiEvent> events) {
    final indexed = <(int, MidiEvent)>[];
    var maxTick = 0;
    for (final e in events) {
      if (e.isMeta && e.metaType == 0x2F) continue;
      indexed.add((indexed.length, e));
      if (e.tick > maxTick) maxTick = e.tick;
    }
    indexed.sort((a, b) {
      final t = a.$2.tick.compareTo(b.$2.tick);
      if (t != 0) return t;
      final p = _priority(a.$2).compareTo(_priority(b.$2));
      return p != 0 ? p : a.$1.compareTo(b.$1);
    });

    final out = BytesBuilder();
    var last = 0;
    for (final (_, e) in indexed) {
      out.add(_vlq(e.tick - last));
      last = e.tick;
      out.addByte(e.status);
      if (e.isMeta) {
        out.addByte(e.metaType!);
        out.add(_vlq(e.data.length));
        out.add(e.data);
      } else if (e.isSysex) {
        out.add(_vlq(e.data.length));
        out.add(e.data);
      } else {
        out.add(e.data);
      }
    }
    out
      ..add(_vlq(maxTick - last))
      ..add(const [0xFF, 0x2F, 0x00]);
    return out.toBytes();
  }

  static List<int> _vlq(int value) {
    var v = value;
    final bytes = <int>[v & 0x7F];
    v >>= 7;
    while (v > 0) {
      bytes.add((v & 0x7F) | 0x80);
      v >>= 7;
    }
    return bytes.reversed.toList();
  }

  static List<int> _ascii(String s) => s.codeUnits;
  static List<int> _u16(int v) => [(v >> 8) & 0xFF, v & 0xFF];
  static List<int> _u32(int v) => [
    (v >> 24) & 0xFF,
    (v >> 16) & 0xFF,
    (v >> 8) & 0xFF,
    v & 0xFF,
  ];
}
