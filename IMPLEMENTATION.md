# Implementation Notes

Living record of the design choices and direction for the Piano Roll app. Update it whenever a decision changes.

## Decisions confirmed with the user

| Topic | Decision |
|---|---|
| State management | `flutter_riverpod` (v3 `Notifier` / `NotifierProvider`) |
| MIDI codec | Hand-written reader/writer, no MIDI package |
| Playback | Included in v1: Web Audio oscillator synth |
| Theme | Dark, DAW style (Material 3, indigo seed) |

## Architecture

```
lib/
  main.dart                    ProviderScope + dark MaterialApp
  midi/                        Byte-level SMF: MidiEvent/MidiFile, MidiReader, MidiWriter
  model/                       Immutable document model + pure logic
    note.dart track.dart project.dart tempo_map.dart
    midi_converter.dart        MidiFile <-> Project
    editing.dart               Pure edit functions (Edits.*)
    snap_and_grid.dart         Snap enum, bar/beat grid lines
  state/                       Riverpod providers
    project_provider.dart      Document + undo/redo
    editor_provider.dart       View state: tool, zoom, scroll, selection, mute/solo
    transport_provider.dart    Playback scheduler + playhead, audioProvider
  audio/                       AudioEngine interface; web (Web Audio) + silent stub
  io/                          Open/download/beforeunload; web + stub
  ui/                          Widgets (page, toolbar, track panel, grid, ruler, keyboard, velocity lane...)
test/
  midi_codec_test.dart         Reader/writer/converter/round-trip
  editor_test.dart             History, timing maths, widget interaction tests
```

Dependencies are one-directional: `ui -> state -> model -> midi`. `model` and `midi` are pure Dart (no Flutter), so they are unit-testable on the VM.

## Core design choices

### Time is measured in ticks
Every position and duration is an integer in MIDI ticks (the file's PPQ is preserved, default 480 for new projects). Pixels and seconds are derived only in the view layer (`EditorState.tickToX`) and the transport (`TempoMap`). This keeps editing exact and import/export lossless with respect to timing.

### Immutable model + snapshot undo
`Note`, `Track` and `Project` are immutable; edits are pure functions in `Edits` that return new projects. Undo/redo stores whole `Project` snapshots (cheap because unchanged notes/tracks are shared). History is capped at 200 steps.
Drags use `beginGesture` / `updateGesture` / `endGesture`: intermediate updates change the visible project without recording history, and `endGesture` pushes the pre-drag snapshot once, so a whole drag is a single undo step.

### Tracks and channels
Each editor `Track` is one MIDI channel. On import every source MIDI track is split per channel (so a format 0 file becomes one editor track per channel, named `<name> (Ch N)`). Channels that only carry controllers (no notes) are merged into the first noted channel of that source track instead of becoming empty tracks. Channel 10 (index 9) is treated as drums: it plays noise bursts and its keyboard preview uses the drum voice.

### Lossless-ish round trip
Things the editor does not model are kept and re-emitted:
- `Track.extras`: controllers, pitch bend, aftertouch, later program changes, sysex and non-structural meta events (key signature, markers, lyrics...) with their absolute ticks.
- `Project.conductorExtras`: meta events from source tracks that contain no channel events.
Handled explicitly: tempo map, time-signature map, track names, the program change at tick 0.
Not preserved: SMPTE-timed files (rejected with a clear error), the exact original track layout (export is always format 1: track 0 = tempo/time signature, then one track per editor track), running status (the writer always writes full status bytes), and the track name of a notes-less conductor track.

### Reader tolerance
`MidiReader` handles running status, 1-4 byte VLQs, sysex (F0/F7), stray system messages, bytes before `MThd` (RMID), truncated chunks and missing end-of-track. Problems become `MidiFile.warnings` and whatever was read is kept; only unusable files throw `MidiFormatException`. Note pairing: note-on with velocity 0 = note-off; per-pitch FIFO queue; notes without a note-off run to the end of their track; zero-length notes become 1 tick.

### Writer ordering
Events at the same tick are ordered meta -> sysex -> other channel events -> note-off -> note-on, so repeated notes retrigger and program/controller setup precedes notes.

### Rendering and interaction
- `CustomPainter`s draw the grid, notes, ruler, keyboard and velocity lane, culling to the visible tick/pitch range.
- Scrolling is **not** a `Scrollable`: scroll offsets and zoom live in `EditorState` and are shared by grid, ruler, keyboard, velocity lane and scrollbars. This keeps all views in sync and makes culling trivial. Custom `AxisScrollbar`s and `WheelRegion` (wheel/Ctrl-zoom/Alt-zoom) replace the built-ins. Mouse-wheel events are claimed through `pointerSignalResolver` so Ctrl+wheel does not zoom the browser page.
- The grid uses raw `Listener` pointer events (rather than `GestureDetector`) because it needs mouse button identity (right/middle), modifier keys and immediate pointer-down handling.
- Dragging computes positions from the drag-start state each move (no incremental drift), snapping the *grabbed note's* start/end, and moves/resizes the whole selection by the same delta, clamped to tick >= 0 and pitch 0-127.
- Notes within a track may overlap (even at the same pitch); export pairs them FIFO.
- Notes: velocity shown by colour; other tracks are drawn ghosted behind the active track.
- Playhead is its own overlay widget so playback repaints only that layer.

### Snap and grid
`Snap` offers 1/4, 1/8, 1/16, 1/32, 1/8T, 1/16T and Off (1 tick). Bar/beat lines come from the time-signature map; time-signature changes are assumed to occur on bar boundaries. Sub-beat lines appear when zoomed in.

### Playback
`TransportNotifier` polls every 25 ms and schedules notes starting within a 250 ms look-ahead on the Web Audio clock (`AudioContext.currentTime`), which gives sample-accurate timing independent of the UI frame rate. Playhead tick = `TempoMap.tickAtMicros(...)`, so tempo changes are honoured. Behaviour choices:
- The note set (including mute/solo) is captured when play starts; edits made during playback take effect on the next play.
- Starting mid-song skips notes that began before the playhead.
- Playback stops and rewinds to 0 one beat after the last note. Pause keeps the position; Stop rewinds.
- The viewport auto-scrolls to follow the playhead.
- Synth: triangle oscillator + short attack/decay/release envelope, velocity -> gain, shared compressor to avoid clipping on chords; drums are band-passed noise. `stopAll()` disconnects the current gain bus and builds a new one, which silences all scheduled voices at once. GM program is stored/exported but does not change the sound.

### Platform abstraction
`AudioEngine` and file I/O use conditional imports (`dart.library.js_interop`): `*_web.dart` uses `package:web`; `*_stub.dart` is a silent clock / no-ops so the same code runs in `flutter test`. `dart:html` is not used (deprecated).

### File I/O without a plugin
Open uses a transient `<input type=file>` and reads bytes via `Blob.arrayBuffer`; Export creates a Blob URL and clicks an anchor. `file_picker` was evaluated and rejected: it drags in many native-platform packages for a web-only app. While there are unsaved edits, a `beforeunload` handler asks the browser to confirm closing the tab. "Dirty" is cleared on export and set by any edit; New/Open ask before discarding.

### Keyboard focus
A single top-level `editorFocusNode` receives shortcuts. Pointer-downs in the editor and submitting the BPM field return focus to it so shortcuts keep working after using a text field. Right-click is the delete shortcut, so `BrowserContextMenu.disableContextMenu()` is called at startup.

## Scope decisions / known limitations (v1)

- Tempo and time signature are editable only for the initial values (toolbar); later changes from imported files are preserved, displayed, and played but not editable.
- No loop region, no automation/controller lanes, no notation view, no live Web MIDI input/recording, no drag-and-drop of files onto the page, no autosave.
- Instruments are a single oscillator voice; the GM program only affects the exported file.
- Selection and clipboard operate on the active track only; paste goes to the playhead (snapped).
- Overlapping same-pitch notes are allowed in the editor but are ambiguous in MIDI; they re-import as FIFO pairs, which can differ from the original lengths.
- Tick-based time-signature bar numbering assumes time-signature changes fall on bar lines.

## Verification performed

- `flutter analyze`: clean. `flutter test`: codec round-trip, reader edge cases, undo/redo, snap/grid/tempo maths, and widget tests that draw, move, resize, erase, play/pause.
- `flutter build web --release` succeeds.
- Manually in Chromium: imported a generated `.mid` (name, instrument, velocities correct), played it (Web Audio scheduling observed, playhead advanced), exported it (valid format 1 file, bytes checked), `beforeunload` guard fires when dirty.

## Possible next steps

Loop region, editable tempo/time-signature events, controller lanes, per-track volume, file drag-and-drop, autosave to IndexedDB, SoundFont/sample-based instruments, Web MIDI input.
