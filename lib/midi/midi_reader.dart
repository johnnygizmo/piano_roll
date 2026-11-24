import 'dart:typed_data';

import 'midi_events.dart';

class _Truncated implements Exception {
  const _Truncated();
}

/// Tolerant Standard MIDI File reader (formats 0, 1 and 2, PPQ timing only).
class MidiReader {
  const MidiReader._();

  static MidiFile parse(Uint8List bytes) {
    final warnings = <String>[];
    final headerPos = _findHeader(bytes);
    if (headerPos < 0) {
      throw const MidiFormatException('Not a MIDI file (missing MThd header).');
    }
    if (headerPos + 14 > bytes.length) {
      throw const MidiFormatException('MIDI header is truncated.');
    }
    final view = ByteData.sublistView(bytes);
    final headerLength = view.getUint32(headerPos + 4);
    if (headerLength < 6) {
      throw const MidiFormatException('Invalid MIDI header length.');
    }
    final format = view.getUint16(headerPos + 8);
    final declaredTracks = view.getUint16(headerPos + 10);
    final division = view.getUint16(headerPos + 12);
    if (division & 0x8000 != 0) {
      throw const MidiFormatException(
        'SMPTE time division is not supported (only ticks per quarter note).',
      );
    }
    if (division == 0) {
      throw const MidiFormatException('Invalid time division of 0.');
    }

    final tracks = <List<MidiEvent>>[];
    var pos = headerPos + 8 + headerLength;
    while (pos + 8 <= bytes.length) {
      final id = String.fromCharCodes(bytes, pos, pos + 4);
      final length = view.getUint32(pos + 4);
      final start = pos + 8;
      var end = start + length;
      if (end > bytes.length) {
        warnings.add('Chunk "$id" is truncated; reading what is available.');
        end = bytes.length;
      }
      if (id == 'MTrk') {
        tracks.add(_parseTrack(bytes, start, end, tracks.length, warnings));
      }
      pos = end;
    }
    if (tracks.isEmpty) {
      throw const MidiFormatException('The file contains no tracks.');
    }
    if (tracks.length != declaredTracks) {
      warnings.add(
        'Header declares $declaredTracks tracks but ${tracks.length} were found.',
      );
    }
    return MidiFile(
      format: format,
      division: division,
      tracks: tracks,
      warnings: warnings,
    );
  }

  // Some files (e.g. RIFF-wrapped RMID) have bytes before the header.
  static int _findHeader(Uint8List b) {
    final limit = b.length - 4;
    for (var i = 0; i <= limit && i < 4096; i++) {
      if (b[i] == 0x4D &&
          b[i + 1] == 0x54 &&
          b[i + 2] == 0x68 &&
          b[i + 3] == 0x64) {
        return i;
      }
    }
    return -1;
  }

  static List<MidiEvent> _parseTrack(
    Uint8List bytes,
    int start,
    int end,
    int index,
    List<String> warnings,
  ) {
    var p = start;
    var tick = 0;
    int? running;
    final events = <MidiEvent>[];

    int readByte() {
      if (p >= end) throw const _Truncated();
      return bytes[p++];
    }

    int readVlq() {
      var value = 0;
      for (var i = 0; i < 4; i++) {
        final b = readByte();
        value = (value << 7) | (b & 0x7F);
        if (b & 0x80 == 0) return value;
      }
      throw const MidiFormatException('Variable-length value is too long');
    }

    Uint8List readBlock(int length) {
      if (p + length > end) throw const _Truncated();
      final block = Uint8List.sublistView(bytes, p, p + length);
      p += length;
      return Uint8List.fromList(block);
    }

    try {
      while (p < end) {
        tick += readVlq();
        var status = bytes[p < end ? p : throw const _Truncated()];
        if (status < 0x80) {
          final r = running;
          if (r == null) {
            throw const MidiFormatException('Data byte without running status');
          }
          status = r;
        } else {
          p++;
        }

        if (status == 0xFF) {
          final type = readByte();
          final data = readBlock(readVlq());
          events.add(
            MidiEvent(tick: tick, status: 0xFF, metaType: type, data: data),
          );
          running = null;
          if (type == 0x2F) break;
        } else if (status == 0xF0 || status == 0xF7) {
          final data = readBlock(readVlq());
          events.add(MidiEvent(tick: tick, status: status, data: data));
          running = null;
        } else if (status >= 0xF1) {
          // System common/real-time messages do not belong in files; skip.
          final skip = switch (status) {
            0xF1 || 0xF3 => 1,
            0xF2 => 2,
            _ => 0,
          };
          readBlock(skip);
          running = null;
        } else {
          running = status;
          final count = (status & 0xF0) == 0xC0 || (status & 0xF0) == 0xD0
              ? 1
              : 2;
          final data = readBlock(count);
          for (final b in data) {
            if (b & 0x80 != 0) {
              throw const MidiFormatException(
                'Invalid data byte in channel event',
              );
            }
          }
          events.add(MidiEvent(tick: tick, status: status, data: data));
        }
      }
    } on _Truncated {
      warnings.add(
        'Track ${index + 1} ends unexpectedly; kept events read so far.',
      );
    } on MidiFormatException catch (e) {
      warnings.add(
        'Track ${index + 1}: ${e.message}; kept events read so far.',
      );
    }
    return events;
  }
}
