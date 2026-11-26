# Piano Roll

A Flutter web MIDI piano roll editor. Opens and exports Standard MIDI Files (`.mid`), edits notes on a piano-roll grid and plays them back in the browser.

## Run

```
flutter pub get
flutter run -d chrome        # development
flutter build web --release  # output in build/web
flutter test                 # unit + widget tests
```

## Using it

- **File & song** – the sliders button at the right end of the toolbar opens a right-hand drawer with **File** (New, Open…, Save = download `<title>.mid`, format 1; Ctrl+O / Ctrl+S also work), the **Title**, and **Song settings** (tempo, time signature). A dot on the button means unsaved changes.
- **Tracks** – the track list is a side drawer: toolbar button or **T**. Pick a track to edit it; M/S mute/solo, + adds, ⋮ opens properties/delete.
- **Audio output** – open the song drawer and toggle **System MIDI** to use an available system MIDI synth or the browser-generated sound.
- **Draw tool (D)** – click an empty cell to add a note; drag to set its length.
- **Select tool (V)** – click or marquee-drag to select; drag a note to move it, drag its right edge to resize. **Alt+drag** (or drag with two fingers on touch) copies the selection and moves the copies.
- **Erase tool (E)** – click/drag over notes. Delete/Backspace removes the selection.
- **Pan tool (H)** – drag the grid to scroll in both directions (works with one finger on touch screens). The scrollbars are larger on narrow screens, and pressing the scrollbar track jumps there.
- **Generate (right-click or long-press a note)** – pie menu: Chord → Major / Minor / Aug / Dim → Triad, m7, M7, 7, m9, M9, 9, m11, M11, 11, m13, M13, 13. The chord is built in root position above that note (same start, length and velocity).
- **Edit (same menu)** – Edit → Cut / Copy / Paste (at the playhead) / Delete the selection, or Resize → Lengthen / Shorten (by the snap size; notes that would vanish are left alone) / Set Size (1/1 … 1/16T).
- **Transpose (same menu)** – Transpose → Up / Down / Copy Up / Copy Down → m2 … Octave moves (or copies and moves) all selected notes by that interval (the clicked note is selected first if it wasn't).
- Wheel scrolls, Shift+wheel scrolls sideways, Ctrl+wheel zooms time, Alt+wheel zooms rows, middle-drag pans. Drag the piano keys up/down to scroll vertically (tap a key to hear it).
- Drag the velocity bars along the bottom to change velocity; the arrow next to "Velocity" collapses the lane.
- **Sheet music** – the **Sheet music** item in the File section of the song drawer opens a new tab that engraves all tracks with [OpenSheetMusicDisplay](https://opensheetmusicdisplay.org/) (bundled in `web/osmd/`, BSD-3). "Save as PDF / Print" uses the browser's print dialog; "Download MusicXML" saves the score. The switches under the item (all on by default) toggle the title, chord symbols, staff labels and tempo mark. Chord symbols are guessed per beat from the notes of all pitched tracks with [Tonal](https://github.com/tonaljs/tonal) (bundled in `web/tonal/`, MIT) and shown above the first track. The key signature and each track's General MIDI instrument (grand staff for keyboards, bass clef for tuba, ...) are honoured. Notation is approximate: times are quantised to 32nd notes (no triplets) and overlapping notes are cut at the next onset.
- Click the ruler to place the playhead; Space plays/pauses.

The **Keyboard shortcuts** item at the bottom of the song drawer lists every shortcut. See [IMPLEMENTATION.md](IMPLEMENTATION.md) for design decisions and [PLAN.md](PLAN.md) for the roadmap.

## Publishing to GitHub Pages

The site is served from `https://<user>.github.io/piano_roll/`, so it is built with `--base-href /piano_roll/`. One script does everything:

```
tool\deploy_web.cmd            # build, commit to web_deploy and tag, all locally
tool\deploy_web.cmd -Push      # ...and push the branch and tags to origin
```
(`powershell -File tool\deploy_web.ps1 [...]` is equivalent; see the script header for all options: `-SkipChecks`, `-AllowDirty`, `-SourceBranch`, `-DeployBranch`, `-BaseHref`, `-Remote`, `-OutputDir`.)

What it does, in order: switches to the source branch (`main`) if you ran it from `web_deploy` (refuses if you have uncommitted changes), requires a clean tree, runs `flutter pub get`, `flutter analyze`, `flutter test`, builds into `build/pages`, then replaces the contents of `web_deploy` with that build in a temporary git worktree (your checkout is never touched) and commits it. It tags the source commit `v<version>` (version from `pubspec.yaml`, e.g. `v1.0.0+1`) and the deploy commit `deploy-<version>-<UTC timestamp>`. **Bump `version:` in `pubspec.yaml` before each release** – the script refuses to reuse a `v<version>` tag that points at a different commit.

One-time GitHub setup: repository **Settings → Pages → Source: Deploy from a branch → `web_deploy`, folder `/ (root)`**.
