import 'dart:typed_data';

class MidiFormatException implements Exception {
  const MidiFormatException(this.message);
  final String message;

  @override
  String toString() => 'MidiFormatException: $message';
}

/// A raw MIDI event positioned at an absolute tick.
///
/// Channel events keep their status byte (command + channel) and 1-2 data
/// bytes. Meta events use status 0xFF with [metaType]. SysEx events use status
/// 0xF0 or 0xF7 and [data] holds the payload without its length prefix.
class MidiEvent {
  const MidiEvent({
    required this.tick,
    required this.status,
    this.metaType,
    required this.data,
  });

  factory MidiEvent.channel(int tick, int status, int d1, [int? d2]) =>
      MidiEvent(
        tick: tick,
        status: status,
        data: Uint8List.fromList([d1, ?d2]),
      );

  factory MidiEvent.meta(int tick, int type, List<int> data) => MidiEvent(
    tick: tick,
    status: 0xFF,
    metaType: type,
    data: Uint8List.fromList(data),
  );

  final int tick;
  final int status;
  final int? metaType;
  final Uint8List data;

  bool get isMeta => status == 0xFF;
  bool get isSysex => status == 0xF0 || status == 0xF7;
  bool get isChannel => status >= 0x80 && status < 0xF0;
  int get channel => status & 0x0F;
  int get command => status & 0xF0;

  MidiEvent withTick(int newTick) =>
      MidiEvent(tick: newTick, status: status, metaType: metaType, data: data);
}

/// A parsed Standard MIDI File: tracks of absolute-tick events.
class MidiFile {
  const MidiFile({
    required this.format,
    required this.division,
    required this.tracks,
    this.warnings = const [],
  });

  final int format;

  /// Ticks per quarter note.
  final int division;
  final List<List<MidiEvent>> tracks;

  /// Non-fatal problems found while parsing (truncation, bad bytes...).
  final List<String> warnings;
}
