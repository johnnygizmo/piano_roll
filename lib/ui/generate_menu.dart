import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/chords.dart';
import '../model/note.dart';
import 'constants.dart';
import 'editor_actions.dart';
import 'interaction.dart';
import 'pie_menu.dart';

/// Pie menu opened on a note: generate a chord (scale/arpeggio are planned).
Future<void> showGenerateMenu(
  BuildContext context,
  WidgetRef ref, {
  required Offset position,
  required Note note,
}) async {
  final actions = EditorActions(context, ref);
  await showPieMenu(
    context,
    center: position,
    title: pitchName(note.pitch),
    items: [
      PieItem(
        'Chord',
        children: [
          for (final quality in ChordQuality.values)
            PieItem(
              quality.label,
              children: [
                for (final extension in ChordExtension.values)
                  PieItem(
                    extension.label,
                    onSelected: () => actions.generateChord(note, quality, extension),
                  ),
              ],
            ),
        ],
      ),
      const PieItem('Scale', enabled: false),
      const PieItem('Arpeggio', enabled: false),
    ],
  );
  editorFocusNode.requestFocus();
}
