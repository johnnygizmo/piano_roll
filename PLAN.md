# Piano Roll – Implementation Plan

**Goal:** A Flutter web app: a MIDI piano roll editor that reads and writes standard MIDI files (.mid).

**Current state:** Fresh `flutter create` scaffold (counter demo in `lib/main.dart`, default `widget_test.dart`). Only dependencies are `flutter` and `cupertino_icons`.

## 1. Scope

**In scope (v1)**
- Import `.mid` (SMF format 0 and 1) and export format 1 `.mid`.
- Piano roll grid: keyboard on the left, time ruler on top, note rectangles in the grid.
- Edit notes: create, select, move, resize, delete, copy/paste, velocity change.
- Multiple tracks with a track selector; tempo and time-signature display/edit.
- Playback in the browser (Web Audio) with a moving playhead.
- Undo/redo, snap-to-grid, zoom.

**Out of scope (v1)**
- Audio recording / live MIDI input (Web MIDI), SoundFont instruments, automation lanes, notation view, cloud storage.

## 2. Tech decisions

| Concern | Choice | Notes |
|---|---|---|
| State management | `provider` (ChangeNotifier) or `flutter_riverpod` | Pick one; keep the model pure Dart |
| MIDI parse/write | Own implementation in `lib/midi/` | SMF is small; avoids web-compat risks. Evaluate `dart_midi_pro` only if time-constrained |
| File I/O on web | `file_picker` (open) + `package:web` Blob/anchor download (save) | `dart:html` is deprecated |
| Rendering | `CustomPainter` for grid/notes/keyboard | Needed for performance with thousands of notes |
| Audio | Web Audio API via `package:web` / `dart:js_interop` (oscillator synth) | Simple synth first |
| Tests | `flutter_test` unit tests for the MIDI codec and editing model | Round-trip tests are the priority |

## 3. Architecture

```
lib/
  main.dart                  App entry, theme
  midi/
    midi_reader.dart         bytes -> MidiFile (VLQ, running status, meta/sysex)
    midi_writer.dart         MidiFile -> bytes
    midi_events.dart         Raw event types
  model/
    note.dart                Note {id, pitch, startTick, durationTicks, velocity, channel}
    track.dart               Track {name, channel, instrument, notes}
    project.dart             Project {ppq, tempoMap, timeSigs, tracks}
    midi_converter.dart      Raw events <-> Project (pair note-on/off)
  state/
    editor_state.dart        Selection, tool, zoom, snap, playhead
    history.dart             Undo/redo command stack
  ui/
    piano_roll_page.dart     Layout
    toolbar.dart             Open/Save, tools, snap, zoom, transport
    keyboard_view.dart       Left piano keys
    ruler_view.dart          Bars/beats ruler
    note_grid.dart           CustomPainter grid + notes + gestures
    velocity_lane.dart       Bottom velocity bars
    track_list.dart          Track selector
  audio/
    synth_web.dart           Web Audio playback
    transport.dart           Scheduler / playhead clock
  io/
    file_io.dart             Open/save abstraction (web impl)
test/
  midi_reader_test.dart
  midi_writer_test.dart
  roundtrip_test.dart
  editing_test.dart
```

Key principle: **ticks are the single source of truth** for time; pixel/second conversions happen only in the view and transport layers.

## 4. Milestones

### M0 – Project setup
- [ ] Rename app title, clean out the counter demo, update `README.md` and `web/index.html`/`manifest.json` metadata.
- [ ] Add dependencies (`provider`, `file_picker`, `web`).
- [ ] Create the folder structure above; keep `flutter analyze` clean.

### M1 – MIDI codec (no UI)
- [ ] Reader: header chunk, track chunks, variable-length quantities, running status, meta events (tempo, time sig, key sig, track name, end of track), channel events, sysex (preserved/skipped).
- [ ] Writer: format 1, correct delta times, running status optional, End-of-Track.
- [ ] Converter: pair note-on/note-off (note-on vel 0 = off), handle overlapping and unterminated notes, preserve PPQ and tempo map; preserve unknown events for round-trip.
- [ ] Unit tests: hand-built byte fixtures, format 0 and 1, round-trip equality.
- **Done when:** a sample `.mid` imports and re-exports with identical note data.

### M2 – Read-only piano roll
- [ ] Layout: keyboard, ruler, scrollable/zoomable grid (horizontal + vertical).
- [ ] Paint grid lines (bar/beat/subdivision), black/white key row shading, notes colored by velocity.
- [ ] Open file via picker; display tracks and note counts.
- [ ] Track selector, show other tracks ghosted.
- **Done when:** user opens a MIDI file and sees notes correctly placed.

### M3 – Editing
- [ ] Tools: select, draw, erase.
- [ ] Draw/move/resize notes with snap (1/4 … 1/32, triplets, off).
- [ ] Marquee and multi-select; delete; duplicate; copy/paste; transpose via arrow keys.
- [ ] Velocity lane editing.
- [ ] Undo/redo (Ctrl+Z / Ctrl+Y) through command pattern.
- [ ] Tempo and time-signature editing (initial values at minimum).
- **Done when:** all edits are undoable and survive export → re-import.

### M4 – Save / export
- [ ] Export to `.mid` via browser download; filename from the project.
- [ ] Unsaved-changes indicator and `beforeunload` warning.
- [ ] Optional: autosave to `localStorage`/IndexedDB.

### M5 – Playback
- [ ] Web Audio oscillator synth with ADSR envelope; velocity → gain.
- [ ] Transport: play/pause/stop, loop region, playhead tracking, click-to-seek on ruler.
- [ ] Audition note on click/draw; per-track mute/solo/volume.
- [ ] Tempo map respected during scheduling.

### M6 – Polish & release
- [ ] Keyboard shortcuts overlay, mouse wheel zoom (Ctrl+wheel), touch gesture support.
- [ ] Performance pass: 10k+ notes at 60fps (viewport culling, `RepaintBoundary`, cached paints).
- [ ] Widget tests for the main flows; manual test on Chrome, Edge, Firefox, Safari.
- [ ] `flutter build web --release`; deploy (GitHub Pages / Firebase Hosting).

## 5. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Malformed / unusual MIDI files (running status, missing end-of-track, SMPTE timing) | Tolerant reader, surface warnings; test with varied real files |
| Large files make rendering slow | Viewport culling, spatial index by start tick |
| Web Audio autoplay restrictions | Create/resume `AudioContext` on first user gesture |
| Lossy round-trip (sysex, controllers, pitch bend) | Keep unknown events attached to the track and re-emit them |
| Tempo changes complicate tick↔time | Central `TempoMap` with tested conversions |

## 6. Testing strategy
- **Unit:** VLQ encode/decode, reader/writer fixtures, converter pairing, tempo map, undo/redo commands.
- **Round-trip:** import → export → import equality on sample files in `test/fixtures/`.
- **Widget:** open file, add/move/delete note, undo.
- **Manual:** cross-browser, load exports in a DAW (e.g. Reaper, Ableton, MuseScore) to verify validity.

## 7. Definition of done (v1)
- Opens format 0/1 MIDI files and shows all notes accurately.
- Notes can be edited with snapping, selection, and undo/redo.
- Exported `.mid` opens correctly in a third-party DAW.
- Plays back in the browser with a synced playhead.
- `flutter analyze` and `flutter test` pass; release web build deploys.
