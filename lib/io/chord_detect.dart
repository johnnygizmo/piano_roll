import '../model/chord_symbol.dart';
import 'chord_detect_stub.dart'
    if (dart.library.js_interop) 'chord_detect_web.dart'
    as impl;

/// Chord detection backed by the Tonal library (loaded by the web page), or
/// null when it is not available.
ChordDetector? tonalChordDetector() => impl.tonalChordDetector();
