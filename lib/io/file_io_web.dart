import 'dart:async';
import 'dart:convert';
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

bool openSheetMusic(
  String title,
  String musicXml, {
  required bool showTitle,
  required bool showStaffLabels,
}) {
  final script = Uri.parse(web.document.baseURI)
      .resolve('osmd/opensheetmusicdisplay.min.js');
  // '</' would end the inline <script> early.
  final xmlJson = jsonEncode(musicXml).replaceAll('</', r'<\/');
  final safeTitle = const HtmlEscape().convert(title);
  final page =
      '''<!DOCTYPE html>
<html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$safeTitle - sheet music</title>
<style>
  body { margin: 0; font-family: sans-serif; background: #fff; color: #000; }
  .bar { position: sticky; top: 0; z-index: 1; display: flex; flex-wrap: wrap;
         gap: 8px; align-items: center; padding: 8px; background: #eceff1;
         border-bottom: 1px solid #b0bec5; }
  button { font-size: 15px; padding: 6px 12px; }
  #score { padding: 8px; }
  @media print { .bar { display: none; } #score { padding: 0; } }
</style>
<script src="${script.toString()}"></script></head>
<body>
<div class="bar">
  <button id="pdf">Save as PDF / Print</button>
  <button id="xml">Download MusicXML</button>
  <span id="msg">Rendering...</span>
</div>
<div id="score"></div>
<script>
  const xml = $xmlJson;
  const msg = document.getElementById('msg');
  document.getElementById('pdf').onclick = () => window.print();
  document.getElementById('xml').onclick = () => {
    const url = URL.createObjectURL(new Blob([xml], {type: 'application/xml'}));
    const a = document.createElement('a');
    a.href = url;
    a.download = ${jsonEncode('$title.musicxml')};
    a.click();
    URL.revokeObjectURL(url);
  };
  try {
    const osmd = new opensheetmusicdisplay.OpenSheetMusicDisplay('score', {
      backend: 'svg', autoResize: true, autoBeam: true,
      drawTitle: $showTitle, drawPartNames: $showStaffLabels,
      drawPartAbbreviations: $showStaffLabels,
    });
    osmd.load(xml).then(() => { osmd.render(); msg.textContent = ''; })
      .catch(e => { msg.textContent = 'Could not render: ' + e; });
    window.addEventListener('beforeprint', () => osmd.render());
  } catch (e) {
    msg.textContent = 'Could not load the score renderer: ' + e;
  }
</script>
</body></html>''';
  final blob = web.Blob(
    [page.toJS].toJS,
    web.BlobPropertyBag(type: 'text/html'),
  );
  return web.window.open(web.URL.createObjectURL(blob), '_blank') != null;
}
