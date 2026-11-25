import 'package:flutter/material.dart';

Future<void> showShortcutsHelp(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Shortcuts & mouse'),
      content: const SingleChildScrollView(
        child: Text(
          'Draw tool: click empty grid to add a note (drag to set length).\n'
          'Select tool: click/drag notes; drag empty space to marquee select.\n'
          'Drag a note body to move, its right edge to resize. Alt+drag (or two-finger drag) copies and moves.\n'
          'Right-click (or long-press) a note: pie menu to generate a chord, edit (cut / copy / paste / delete / resize) or transpose / copy-transpose the selection.\n'
          'Middle-drag pans; so does the Pan tool (H), which also works with one finger.\n'
          'Wheel scrolls; Shift+wheel scrolls sideways; Ctrl+wheel zooms time; Alt+wheel zooms rows.\n'
          'Drag the piano keys up/down to scroll vertically; tap a key to preview it.\n'
          'Drag velocity bars at the bottom to change velocity; the arrow beside "Velocity" collapses the lane.\n'
          'Click the ruler to move the playhead.\n\n'
          'V / D / E / H: select / draw / erase / pan tool     T: tracks drawer\n'
          'Space: play/pause     Ctrl+O: open     Ctrl+S: export\n'
          'Ctrl+Z / Ctrl+Y: undo / redo\n'
          'Ctrl+A: select all     Delete: delete selection\n'
          'Ctrl+C / X / V: copy / cut / paste at playhead\n'
          'Ctrl+D: duplicate     Q: quantize selection\n'
          'Arrows: move selection (←/→ by snap, ↑/↓ by semitone)\n'
          'Shift+↑/↓: move by octave',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
