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

- **Open / Export** – toolbar buttons (Ctrl+O / Ctrl+S). Export downloads `<project name>.mid` (format 1).
- **Draw tool (D)** – click an empty cell to add a note; drag to set its length.
- **Select tool (V)** – click or marquee-drag to select; drag a note to move it, drag its right edge to resize.
- **Erase tool (E)** – click/drag over notes. Right-click deletes in any tool.
- Wheel scrolls, Shift+wheel scrolls sideways, Ctrl+wheel zooms time, Alt+wheel zooms rows, middle-drag pans.
- Drag the velocity bars along the bottom to change velocity.
- Click the ruler to place the playhead; Space plays/pauses.

The `?` button in the toolbar lists every shortcut. See [IMPLEMENTATION.md](IMPLEMENTATION.md) for design decisions and [PLAN.md](PLAN.md) for the roadmap.
