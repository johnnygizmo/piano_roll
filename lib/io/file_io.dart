import 'dart:typed_data';

import 'file_io_stub.dart'
    if (dart.library.js_interop) 'file_io_web.dart'
    as impl;

class PickedFile {
  const PickedFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

/// Shows the browser's file chooser; returns null if cancelled.
Future<PickedFile?> pickMidiFile() => impl.pickMidiFile();

/// Triggers a browser download of [bytes] as [fileName].
void downloadBytes(String fileName, Uint8List bytes) =>
    impl.downloadBytes(fileName, bytes);

/// Asks the browser to confirm before the tab is closed with unsaved edits.
void setUnsavedChangesWarning(bool enabled) =>
    impl.setUnsavedChangesWarning(enabled);
