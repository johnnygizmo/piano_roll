import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/chords.dart';
import '../model/intervals.dart';
import '../model/note.dart';
import '../state/editor_provider.dart';
import 'constants.dart';
import 'editor_actions.dart';
import 'interaction.dart';
import 'pie_menu.dart';

/// Pie menu opened on a note: Chord, Scale, Arpeggio (planned), Transpose.
///
/// Transpose acts on the whole selection; if the clicked note is not part of
/// it, the selection becomes just that note first.
Future<void> showGenerateMenu(
  BuildContext context,
  WidgetRef ref, {
  required Offset position,
  required Note note,
}) async {
  final actions = EditorActions(context, ref);
  final editor = ref.read(editorProvider.notifier);
  if (!ref.read(editorProvider).selection.contains(note.id)) {
    editor.setSelection({note.id});
  }

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
                    onSelected: () =>
                        actions.generateChord(note, quality, extension),
                  ),
              ],
            ),
        ],
      ),
      const PieItem('Scale', enabled: false),
      const PieItem('Arpeggio', enabled: false),
      PieItem(
        'Transpose',
        children: [
          for (final (label, direction, copy) in const [
            ('Up', 1, false),
            ('Down', -1, false),
            ('Copy Up', 1, true),
            ('Copy Down', -1, true),
          ])
            PieItem(
              label,
              children: [
                for (final interval in transposeIntervals)
                  PieItem(
                    interval.label,
                    onSelected: () => actions.transposeSelection(
                      direction * interval.semitones,
                      copy: copy,
                    ),
                  ),
              ],
            ),
        ],
      ),
    ],
  );
  editorFocusNode.requestFocus();
}
