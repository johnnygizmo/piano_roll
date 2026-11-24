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
    chords.dart                Chord quality/extension -> intervals, buildChord
    intervals.dart             Transpose intervals (m2..Octave)
  state/                       Riverpod providers
    project_provider.dart      Document + undo/redo
    editor_provider.dart       View state: tool, zoom, scroll, selection, mute/solo
    transport_provider.dart    Playback scheduler + playhead, audioProvider
  audio/                       AudioEngine interface; web (Web Audio) + silent stub
  io/                          Open/download/beforeunload; web + stub
  ui/                          Widgets (page, toolbar, track drawer, grid, ruler, keyboard, velocity lane...)
test/
  midi_codec_test.dart         Reader/writer/converter/round-trip
  editor_test.dart             History, timing maths, widget interaction tests
  chords_test.dart             Chord intervals, pie geometry, pie-menu widget flows
tool/
  deploy_web.ps1 / .cmd        Build + publish to the web_deploy branch (GitHub Pages)
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

### Generate pie menu (chords)
Right-click on a note (mouse) or a 500 ms long-press (touch, cancelled by moving > 8 px) opens a pie menu centred on the pointer; it replaces the earlier "right-click deletes" behaviour (delete is the Delete/Backspace key and the Erase tool).
- `ui/pie_menu.dart`: generic, data-driven pie. `PieItem(label, children | onSelected, enabled)` forms a tree; a slice with children opens a sub-ring in place, the hub goes back (or closes at the root), Esc closes, Backspace goes back, clicking outside closes. `PieLayout` holds the geometry (slice 0 centred at the top, clockwise; hit testing; ring radius 110 px for <= 6 slices, 170 px for more) and is reused by the tests. The centre is clamped once using the largest ring so it does not move between rings. It is a transparent `showGeneralDialog` route (fade-in only: a scale transition would scale around the screen centre, not the pie, and mis-position hit testing while animating) so it overlays everything and is closed by the barrier.
- `ui/generate_menu.dart` builds the tree: Chord -> quality -> extension; Scale and Arpeggio (disabled placeholders, to be added as further subtrees without touching the pie widget); **Transpose -> Up / Down / Copy Up / Copy Down -> m2, M2, m3, M3, P4, TT, P5, m6, M6, m7, M7, Octave** (`model/intervals.dart`, 1-12 semitones; the tritone is labelled TT).
- Transpose acts on the **whole selection**. If the clicked note is not in the selection, opening the menu first makes it the only selected note (so right-clicking an unselected note never silently transposes other notes). If any selected note would leave MIDI 0-127 the whole operation is refused with a snackbar, so intervals between notes are never changed (unlike arrow-key nudging, which clamps). It is one undo step and auditions up to 8 of the moved notes. Plain Up/Down keep the selection (so you can repeat it).
- **Copy Up / Copy Down** leave the selected notes in place and add transposed copies (fresh ids, same start/duration/velocity); the **copies become the selection**, matching Alt-drag copying, so a copy can be repeated to build stacks. Copies that would exactly duplicate an existing note (same start and pitch) are skipped; if nothing is left to add, a snackbar says so and nothing changes.
- `model/chords.dart` is pure logic. Rules (confirmed with the user): ring 1 fixes the 3rd/5th (major 4,7; minor 3,7; aug 4,8; dim 3,6). Ring 2 chooses how far the chord stacks and the flavour of its 7th: prefix `m` = minor 7th (10), `M` = major 7th (11), none = dominant 7th (10; diminished 7th = 9 for dim). 9th/11th/13th are natural (+14/+17/+21) and stack: 9 = 7+9, 11 = 7+9+11, 13 = 7+9+13 (11th omitted). Consequently Major+m7 equals Major+7. The root note is kept and the new tones are stacked above it (root position) with the same start, duration and velocity; tones above MIDI 127 are dropped.
- `EditorActions.generateChord` adds the notes as one undoable step, skips pitches that already exist at the same start, clears the selection (user choice), and auditions the chord.

### Tracks drawer
The track list is a standard Material `Scaffold.drawer` (`TrackPanel` inside a `Drawer`), not a permanent column, so the grid gets the full window width. It opens from the first toolbar button or the **T** key (the page's `scaffoldKey` in `ui/interaction.dart`), and the toolbar always shows the active track's colour and name in a chip. The drawer is modal and closes when a track is chosen ("edit this one"); mute/solo, add track and the properties/delete menu leave it open so several tracks can be adjusted in one visit. Closing it returns keyboard focus to the editor (`onDrawerChanged`). The grid already tracks its own viewport size, so the wider layout needed no other changes.

### Song drawer (right side)
File commands, the title and the song settings live in a second `Scaffold.endDrawer` (`ui/song_drawer.dart`), opened by the tune button pinned to the right end of the toolbar (next to the help button); the rest of the toolbar scrolls horizontally on narrow windows. The button carries a dot while the document has unsaved edits (this replaced the "•" that used to follow the title in the toolbar).
- **File:** New / Open… / Save. Save is the existing export (a browser download of `<title>.mid`; there is no server or File System Access API) and its subtitle shows the file name and an "unsaved changes" hint. Actions run while the drawer is still open and the drawer closes afterwards, because they open a confirmation dialog and the browser file chooser and the drawer's context must stay mounted for them.
- **Title:** `Project.name`, editable (`Edits.setName`), used as the export file name and written into the conductor track's name. After an import it is the file name without `.mid`.
- **Song settings:** tempo (BPM) and time signature of the first tempo/time-signature entries; a note appears when the song has later changes that cannot be edited.
- `CommitTextField` is the shared text field: it applies its value on Enter or focus loss, only when it changed and passes validation (an invalid tempo such as `0` snaps back); merely focusing and leaving a field is not an edit (previously this created an empty undo step and marked the document dirty). Tempo is stored as microseconds per quarter, so it is displayed with at most two decimals and no trailing zeros (90 BPM reads back as 89.99998).

### Rendering and interaction
- `CustomPainter`s draw the grid, notes, ruler, keyboard and velocity lane, culling to the visible tick/pitch range.
- Scrolling is **not** a `Scrollable`: scroll offsets and zoom live in `EditorState` and are shared by grid, ruler, keyboard, velocity lane and scrollbars. This keeps all views in sync and makes culling trivial. Custom `AxisScrollbar`s and `WheelRegion` (wheel/Ctrl-zoom/Alt-zoom) replace the built-ins. Mouse-wheel events are claimed through `pointerSignalResolver` so Ctrl+wheel does not zoom the browser page.
- The grid uses raw `Listener` pointer events (rather than `GestureDetector`) because it needs mouse button identity (right/middle), modifier keys, touch long-press timing and immediate pointer-down handling.
- Dragging computes positions from the drag-start state each move (no incremental drift), snapping the *grabbed note's* start/end, and moves/resizes the whole selection by the same delta, clamped to tick >= 0 and pitch 0-127.
- **Copy-drag:** dragging a note with **Alt held** (Option on macOS) or with **two fingers down** (touch) duplicates the selection and moves the copies, leaving the originals in place. The decision is taken on the first movement that actually changes the position (`_beginCopy`), so a click or a drag that snaps back to zero never creates duplicates. The copies get fresh ids, become the selection, and the whole copy+move is one undo step (it runs inside the same gesture). Alt/two fingers apply to move drags only, not resizing. The cursor shows the copy cursor over a note while Alt is held.
- **Multi-touch:** the grid remembers the pointer that started a gesture and ignores moves/ups from any other pointer; extra touch pointers only count towards the two-finger test and cancel the long-press timer (so a two-finger gesture doesn't open the pie menu). Lifting the extra finger mid-drag does not end the drag.
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
A single top-level `editorFocusNode` receives shortcuts. Pointer-downs in the editor and submitting a text-field in the song drawer return focus to it so shortcuts keep working after using a text field. Right-click opens the generate pie menu, so `BrowserContextMenu.disableContextMenu()` is called at startup.

## Publishing (GitHub Pages)

`tool/deploy_web.ps1` (wrapper: `tool/deploy_web.cmd`) builds and publishes the web app; usage is in the README. Design choices (confirmed with the user: commit on top of the existing `web_deploy`, no push unless `-Push`, two tag kinds):

- **Base href `/piano_roll/`**: the project site lives under the repository name. `web/index.html` keeps Flutter's `$FLUTTER_BASE_HREF` placeholder and the script passes `--base-href`; after the build it verifies `<base href="/piano_roll/">` is really in `index.html`, and warns if the value differs from the GitHub repository name.
- **Build folder, then branch**: output goes to `build/pages` (git-ignored), then is copied into the deploy branch. The deploy branch contains *only* the build output (+ `.nojekyll`, so Pages does not run Jekyll, and `.gitattributes` with `* -text`).
- **Worktree instead of branch switching**: the deploy branch is checked out in a temporary `git worktree` (`build/.deploy_worktree`, always removed in a `finally`). The user's working tree, index and checked-out branch are never disturbed by the commit step, and no stash/checkout dance can lose work. The only automatic switch is *to the source branch* when the script is started from the deploy branch (a branch cannot be checked out in two worktrees); that switch is refused if there are uncommitted changes.
- **No force-push, history kept**: the first deploy added a commit on top of `web_deploy` (which initially held the source tree) that replaces its whole tree with the build. Later deploys do the same. A local deploy branch that is behind the remote is fast-forwarded; if it has diverged the script stops. If the branch does not exist anywhere it is created as an orphan.
- **Byte-exact output**: commits are made with `core.autocrlf=false` and the branch carries `* -text`. Without this, Windows `autocrlf` rewrote CRLF to LF in four build files (e.g. `flutter_service_worker.js`), so the deployed bytes differed from the build.
- **Tagging**: annotated tags `v<version>` on the source commit (version = `pubspec.yaml` `version:` including the build number, e.g. `v1.0.0+1`) and `deploy-<version>-<UTC yyyyMMdd-HHmmss>` on the deploy commit. The source tag is only created from a clean tree (so it always matches what was built) and the script fails early if `v<version>` already exists on a *different* commit, which forces a version bump per release. Tags are created after the deploy commit succeeds, so a failed build leaves none behind. With `-Push`, all `v*` and `deploy-*` tags are pushed, which also publishes tags from earlier local-only runs.
- **Safety checks before building**: clean working tree (`-AllowDirty` overrides and skips the source tag), `flutter analyze` and `flutter test` must pass (`-SkipChecks` skips), warns if the source branch is behind its remote or has unpushed commits.
- Rebuilding identical source can still produce a different build (service-worker/version metadata), so re-running creates another deploy commit; it only skips committing when the output is byte-identical.
- **Windows PowerShell 5.1 compatibility**: `tool\deploy_web.cmd` starts `powershell.exe` (5.1), which turns *any* stderr text from a native command into an error record; with `$ErrorActionPreference = 'Stop'` the normal `From https://...` line that `git fetch` prints aborted the script (`NativeCommandError`). All native calls now go through helpers (`Invoke-GitRaw`, `Invoke-Git`, `Get-Git`, `Test-Git`, `Invoke-Native`) that run with `'Continue'` inside the function and decide success purely by exit code; no `*> $null` / `2>$null` redirections remain. Tested under both PowerShell 7 and 5.1 (including a fetch that brings in new remote commits, the fast-forward of a behind local branch, and `-Push`).
- The script was tested end to end against a throw-away clone with a bare local remote (switch from `web_deploy`, deploy, re-deploy, version-tag guard, push of branch and tags, byte-for-byte comparison of the committed files with the build).

## Scope decisions / known limitations (v1)

- Tempo and time signature are editable only for the initial values (song drawer); later changes from imported files are preserved, displayed, and played but not editable (the drawer says how many there are).
- Generate menu: only Chord and Transpose are implemented; Scale and Arpeggio are disabled placeholders. Chords apply to the single note that was clicked; Transpose applies to the whole selection.
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
