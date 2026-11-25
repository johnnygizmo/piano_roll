import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/editing.dart';
import '../model/track.dart';
import '../state/editor_provider.dart';
import '../state/project_provider.dart';
import 'constants.dart';

/// Track list shown in the side drawer: select, mute/solo, properties.
class TrackPanel extends ConsumerWidget {
  const TrackPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(projectProvider.select((s) => s.project.tracks));
    final editor = ref.watch(editorProvider);
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: trackPanelWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 0),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Tracks',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: 'Add track',
                  icon: const Icon(Icons.add),
                  onPressed: () => _addTrack(ref),
                ),
              ],
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              itemCount: tracks.length,
              onReorderItem: (from, to) => ref
                  .read(projectProvider.notifier)
                  .apply((p) => Edits.moveTrack(p, from, to)),
              itemBuilder: (context, i) {
                final track = tracks[i];
                final selected = track.id == editor.activeTrackId;
                return Material(
                  key: ValueKey(track.id),
                  color: selected
                      ? scheme.primaryContainer.withValues(alpha: 0.45)
                      : Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      ref.read(editorProvider.notifier).selectTrack(track.id);
                      // Choosing a track means "edit this one": get out of the way.
                      Scaffold.maybeOf(context)?.closeDrawer();
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(color: trackColor(i), width: 4),
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(8, 6, 2, 6),
                      child: Row(
                        children: [
                          ReorderableDragStartListener(
                            index: i,
                            child: const Tooltip(
                              message: 'Drag to reorder',
                              child: MouseRegion(
                                cursor: SystemMouseCursors.grab,
                                child: Padding(
                                  padding: EdgeInsets.only(right: 4),
                                  child: Icon(
                                    Icons.drag_indicator,
                                    size: 18,
                                    color: Colors.white54,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  track.name.isEmpty ? '(unnamed)' : track.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  track.isDrum
                                      ? 'Ch ${track.channel + 1} · Drums · ${track.notes.length} notes'
                                      : 'Ch ${track.channel + 1} · ${generalMidiPrograms[track.program]} · ${track.notes.length} notes',
                                  style: Theme.of(context).textTheme.bodySmall,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          _ToggleChip(
                            label: 'M',
                            tooltip: 'Mute',
                            on: editor.muted.contains(track.id),
                            color: Colors.orange,
                            onTap: () => ref
                                .read(editorProvider.notifier)
                                .toggleMute(track.id),
                          ),
                          _ToggleChip(
                            label: 'S',
                            tooltip: 'Solo',
                            on: editor.solo.contains(track.id),
                            color: Colors.green,
                            onTap: () => ref
                                .read(editorProvider.notifier)
                                .toggleSolo(track.id),
                          ),
                          PopupMenuButton<String>(
                            tooltip: 'Track options',
                            iconSize: 18,
                            onSelected: (v) {
                              if (v == 'edit') _editTrack(context, ref, track);
                              if (v == 'delete') {
                                _deleteTrack(
                                  context,
                                  ref,
                                  track,
                                  tracks.length,
                                );
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'edit',
                                child: Text('Properties…'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                enabled: tracks.length > 1,
                                child: const Text('Delete track'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _addTrack(WidgetRef ref) {
    final project = ref.read(projectProvider).project;
    final used = {for (final t in project.tracks) t.channel};
    var channel = 0;
    while (used.contains(channel) && channel < 15) {
      channel++;
    }
    final track = Track.create(
      name: 'Track ${project.tracks.length + 1}',
      channel: channel,
    );
    ref.read(projectProvider.notifier).apply((p) => Edits.addTrack(p, track));
    ref.read(editorProvider.notifier).selectTrack(track.id);
  }

  Future<void> _deleteTrack(
    BuildContext context,
    WidgetRef ref,
    Track track,
    int count,
  ) async {
    if (count <= 1) return;
    if (track.notes.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Delete "${track.name}"?'),
          content: Text(
            'This removes ${track.notes.length} notes (undo is available).',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    ref
        .read(projectProvider.notifier)
        .apply((p) => Edits.removeTrack(p, track.id));
  }

  Future<void> _editTrack(
    BuildContext context,
    WidgetRef ref,
    Track track,
  ) async {
    final nameController = TextEditingController(text: track.name);
    var channel = track.channel;
    var program = track.program;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Track properties'),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: channel,
                  decoration: const InputDecoration(
                    labelText: 'MIDI channel (10 = drums)',
                  ),
                  items: [
                    for (var c = 0; c < 16; c++)
                      DropdownMenuItem(value: c, child: Text('${c + 1}')),
                  ],
                  onChanged: (v) => setState(() => channel = v ?? channel),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: program,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Instrument (GM program)',
                  ),
                  items: [
                    for (var i = 0; i < generalMidiPrograms.length; i++)
                      DropdownMenuItem(
                        value: i,
                        child: Text('${i + 1}. ${generalMidiPrograms[i]}'),
                      ),
                  ],
                  onChanged: (v) => setState(() => program = v ?? program),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
    final name = nameController.text;
    nameController.dispose();
    if (result != true) return;
    ref
        .read(projectProvider.notifier)
        .apply(
          (p) => Edits.mapTrack(
            p,
            track.id,
            (t) => t.copyWith(name: name, channel: channel, program: program),
          ),
        );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.label,
    required this.tooltip,
    required this.on,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String tooltip;
  final bool on;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 24,
          height: 24,
          margin: const EdgeInsets.only(left: 2),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? color : Colors.transparent,
            border: Border.all(color: on ? color : Colors.white24),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: on ? Colors.black : Colors.white70,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
