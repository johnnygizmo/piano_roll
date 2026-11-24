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
- **Draw tool (D)** – click an empty cell to add a note; drag to set its length.
- **Select tool (V)** – click or marquee-drag to select; drag a note to move it, drag its right edge to resize. **Alt+drag** (or drag with two fingers on touch) copies the selection and moves the copies.
- **Erase tool (E)** – click/drag over notes. Delete/Backspace removes the selection.
- **Generate (right-click or long-press a note)** – pie menu: Chord → Major / Minor / Aug / Dim → Triad, m7, M7, 7, m9, M9, 9, m11, M11, 11, m13, M13, 13. The chord is built in root position above that note (same start, length and velocity). Scale and Arpeggio are shown but not implemented yet.
- **Transpose (same menu)** – Transpose → Up / Down / Copy Up / Copy Down → m2 … Octave moves (or copies and moves) all selected notes by that interval (the clicked note is selected first if it wasn't).
- Wheel scrolls, Shift+wheel scrolls sideways, Ctrl+wheel zooms time, Alt+wheel zooms rows, middle-drag pans.
- Drag the velocity bars along the bottom to change velocity.
- Click the ruler to place the playhead; Space plays/pauses.

The `?` button in the toolbar lists every shortcut. See [IMPLEMENTATION.md](IMPLEMENTATION.md) for design decisions and [PLAN.md](PLAN.md) for the roadmap.
