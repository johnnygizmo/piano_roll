import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'file_io.dart';

Future<PickedFile?> pickMidiFile() {
  final completer = Completer<PickedFile?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = '.mid,.midi,audio/midi,audio/x-midi';

  input.onchange = ((web.Event _) {
    final files = input.files;
    if (files == null || files.length == 0) {
      completer.complete(null);
      return;
    }
    final file = files.item(0)!;
    file.arrayBuffer().toDart.then((buffer) {
      completer.complete(PickedFile(file.name, buffer.toDart.asUint8List()));
    }, onError: completer.completeError);
  }).toJS;
  input.oncancel = ((web.Event _) {
    if (!completer.isCompleted) completer.complete(null);
  }).toJS;

  input.click();
  return completer.future;
}

void downloadBytes(String fileName, Uint8List bytes) {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'audio/midi'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName;
  anchor.click();
  web.URL.revokeObjectURL(url);
}

void setUnsavedChangesWarning(bool enabled) {
  web.window.onbeforeunload = enabled
      ? ((web.Event e) {
          e.preventDefault();
        }).toJS
      : null;
}
