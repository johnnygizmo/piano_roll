import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import '../model/chord_symbol.dart';

@JS('Tonal.Chord.detect')
external JSArray<JSString> _detect(JSArray<JSString> notes);

@JS('Tonal.Chord.get')
external _TonalChord _get(String name);

extension type _TonalChord._(JSObject _) implements JSObject {
  external bool get empty;
  external JSString? get tonic;
  external JSArray<JSString> get aliases;
}

ChordDetector? tonalChordDetector() {
  if (!globalContext.has('Tonal')) return null;
  return (noteNames) {
    try {
      final names = _detect([for (final n in noteNames) n.toJS].toJS).toDart;
      final result = <DetectedChord>[];
      for (final jsName in names) {
        // Tonal names slash chords like "CM/E" but only parses the part
        // before the slash.
        final parts = jsName.toDart.split('/');
        final chord = _get(parts.first);
        final aliases = chord.aliases.toDart;
        final tonic = chord.tonic?.toDart;
        if (chord.empty || tonic == null || aliases.isEmpty) continue;
        result.add(
          DetectedChord(
            tonic,
            aliases.first.toDart,
            parts.length > 1 ? parts[1] : null,
          ),
        );
      }
      return result;
    } catch (_) {
      return const [];
    }
  };
}
