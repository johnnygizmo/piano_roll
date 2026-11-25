import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../midi/midi_events.dart';
import '../state/autosave.dart';
import '../state/project_provider.dart';

/// Starts autosaving and, on first build, offers to restore unsaved work left
/// in the local store by a previous session that was reloaded or crashed.
class RestoreGate extends ConsumerStatefulWidget {
  const RestoreGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<RestoreGate> createState() => _RestoreGateState();
}

class _RestoreGateState extends ConsumerState<RestoreGate> {
  @override
  void initState() {
    super.initState();
    // Reading the provider also starts listening for edits.
    final autosave = ref.read(autosaveProvider);
    final entry = autosave.read();
    if (entry == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final restore = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Restore unsaved work?'),
          content: Text(
            '"${entry.name}" was being edited and was not saved '
            '(last change ${_describe(entry.savedAt)}). '
            'Do you want to load it?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Discard'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Restore'),
            ),
          ],
        ),
      );
      if (restore == true) {
        try {
          ref
              .read(projectProvider.notifier)
              .loadBytes(entry.bytes, entry.name, dirty: true);
          return;
        } on MidiFormatException catch (_) {
          if (mounted) {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              const SnackBar(content: Text('The saved copy is unreadable.')),
            );
          }
        }
      }
      autosave.clear();
    });
  }

  static String _describe(DateTime time) {
    String two(int n) => n.toString().padLeft(2, '0');
    final now = DateTime.now();
    final clock = '${two(time.hour)}:${two(time.minute)}';
    final sameDay =
        time.year == now.year && time.month == now.month && time.day == now.day;
    return sameDay
        ? 'at $clock'
        : 'on ${time.year}-${two(time.month)}-${two(time.day)} at $clock';
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
