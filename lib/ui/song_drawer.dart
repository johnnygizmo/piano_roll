import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/editing.dart';
import '../state/project_provider.dart';
import '../state/sheet_options_provider.dart';
import 'editor_actions.dart';
import 'interaction.dart';
import 'shortcuts_help.dart';

const _timeSignatures = <(int, int)>[
  (4, 2),
  (3, 2),
  (2, 2),
  (5, 2),
  (6, 3),
  (7, 3),
  (9, 3),
  (12, 3),
];

const _majorKeys = [
  'C♭', 'G♭', 'D♭', 'A♭', 'E♭', 'B♭', 'F', 'C', //
  'G', 'D', 'A', 'E', 'B', 'F♯', 'C♯',
];
const _minorKeys = [
  'A♭', 'E♭', 'B♭', 'F', 'C', 'G', 'D', 'A', //
  'E', 'B', 'F♯', 'C♯', 'G♯', 'D♯', 'A♯',
];

String _keyName(int sharps, bool minor) =>
    '${(minor ? _minorKeys : _majorKeys)[sharps + 7]} ${minor ? 'minor' : 'major'}';

/// Right-hand drawer: file commands, song title and song settings.
class SongDrawer extends ConsumerWidget {
  const SongDrawer({super.key});

  // Actions open dialogs and the browser file chooser, so they run while the
  // drawer is still open (it stays mounted) and it closes afterwards.
  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    await action();
    if (context.mounted) Scaffold.maybeOf(context)?.closeEndDrawer();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(projectProvider);
    final project = state.project;
    final actions = EditorActions(context, ref);
    final sheet = ref.watch(sheetOptionsProvider);
    final sheetNotifier = ref.read(sheetOptionsProvider.notifier);
    final sig = project.timeSignatures.first;
    final sigValue = (sig.numerator, sig.denominatorPower);
    final key = project.keySignatures.first;
    final extraChanges =
        project.tempos.length -
        1 +
        project.timeSignatures.length -
        1 +
        project.keySignatures.length -
        1;
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          const _SectionHeader('File'),
          ListTile(
            dense: true,
            leading: const Icon(Icons.note_add_outlined),
            title: const Text('New'),
            subtitle: const Text('Start a blank project'),
            onTap: () => _run(context, actions.newProject),
          ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.folder_open),
            title: const Text('Open…'),
            subtitle: const Text('Load a .mid file (Ctrl+O)'),
            onTap: () => _run(context, actions.openFile),
          ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.download),
            title: const Text('Save'),
            subtitle: Text(
              'Download ${_fileName(project.name)} (Ctrl+S)'
              '${state.dirty ? ' • unsaved changes' : ''}',
            ),
            onTap: () => _run(context, () async => actions.exportFile()),
          ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.music_note),
            title: const Text('Sheet music'),
            subtitle: const Text('View in a new tab, save as PDF'),
            onTap: () => _run(context, () async => actions.showSheetMusic()),
          ),
          SwitchListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: 32, right: 16),
            title: const Text('Title'),
            value: sheet.title,
            onChanged: (v) => sheetNotifier.update((o) => o.copyWith(title: v)),
          ),
          SwitchListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: 32, right: 16),
            title: const Text('Chords'),
            value: sheet.chords,
            onChanged: (v) =>
                sheetNotifier.update((o) => o.copyWith(chords: v)),
          ),
          SwitchListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: 32, right: 16),
            title: const Text('Staff labels'),
            value: sheet.staffLabels,
            onChanged: (v) =>
                sheetNotifier.update((o) => o.copyWith(staffLabels: v)),
          ),
          SwitchListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: 32, right: 16),
            title: const Text('Tempo'),
            value: sheet.tempo,
            onChanged: (v) => sheetNotifier.update((o) => o.copyWith(tempo: v)),
          ),
          const Divider(),
          const _SectionHeader('Title'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: CommitTextField(
              text: project.name,
              hint: 'Song title',
              onCommit: (name) => ref
                  .read(projectProvider.notifier)
                  .apply((p) => Edits.setName(p, name)),
            ),
          ),
          const Divider(height: 24),
          const _SectionHeader('Song settings'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Expanded(child: Text('Tempo (BPM)')),
                SizedBox(
                  width: 96,
                  child: CommitTextField(
                    text: _formatBpm(project.tempos.first.bpm),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    validate: (t) {
                      final v = double.tryParse(t);
                      return v != null && v > 0;
                    },
                    onCommit: (t) => ref
                        .read(projectProvider.notifier)
                        .apply((p) => Edits.setTempo(p, double.parse(t))),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Expanded(child: Text('Time signature')),
                DropdownButton<(int, int)>(
                  value: _timeSignatures.contains(sigValue) ? sigValue : null,
                  hint: Text('${sig.numerator}/${sig.denominator}'),
                  items: [
                    for (final s in _timeSignatures)
                      DropdownMenuItem(
                        value: s,
                        child: Text('${s.$1}/${1 << s.$2}'),
                      ),
                  ],
                  onChanged: (s) {
                    if (s == null) return;
                    ref
                        .read(projectProvider.notifier)
                        .apply((p) => Edits.setTimeSignature(p, s.$1, s.$2));
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Expanded(child: Text('Key signature')),
                DropdownButton<(int, bool)>(
                  value: (key.sharps, key.minor),
                  items: [
                    for (final minor in const [false, true])
                      for (var s = -7; s <= 7; s++)
                        DropdownMenuItem(
                          value: (s, minor),
                          child: Text(_keyName(s, minor)),
                        ),
                  ],
                  onChanged: (k) {
                    if (k == null) return;
                    ref
                        .read(projectProvider.notifier)
                        .apply((p) => Edits.setKeySignature(p, k.$1, k.$2));
                  },
                ),
              ],
            ),
          ),
          if (extraChanges > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                'This song also has $extraChanges later tempo/time/key-signature '
                'change(s). They are kept and played but cannot be edited here.',
                style: textTheme.bodySmall,
              ),
            ),
          // Shown last so it stays at the bottom of the drawer.
          const Divider(height: 24),
          ListTile(
            dense: true,
            leading: const Icon(Icons.keyboard_outlined),
            title: const Text('Keyboard shortcuts'),
            subtitle: const Text('Mouse, touch and key reference'),
            onTap: () => _run(context, () => showShortcutsHelp(context)),
          ),
        ],
      ),
    );
  }

  static String _fileName(String name) =>
      '${name.trim().isEmpty ? 'untitled' : name.trim()}.mid';

  // Tempo is stored as microseconds per quarter, so 90 BPM reads back as
  // 89.99998; show at most two decimals without trailing zeros.
  static String _formatBpm(double bpm) =>
      bpm.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.bold,
      ),
    ),
  );
}

/// Text field that applies its value once editing ends (Enter or focus loss),
/// only if it changed and passes [validate]; otherwise the old text returns.
/// It follows external changes to [text] while it is not focused.
class CommitTextField extends StatefulWidget {
  const CommitTextField({
    super.key,
    required this.text,
    required this.onCommit,
    this.validate,
    this.hint,
    this.keyboardType,
    this.inputFormatters,
  });

  final String text;
  final ValueChanged<String> onCommit;
  final bool Function(String)? validate;
  final String? hint;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  @override
  State<CommitTextField> createState() => _CommitTextFieldState();
}

class _CommitTextFieldState extends State<CommitTextField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.text,
  );
  late final FocusNode _focus = FocusNode()..addListener(_onFocus);

  void _onFocus() {
    if (!_focus.hasFocus) _commit();
  }

  void _commit() {
    if (!mounted) return;
    final value = _controller.text.trim();
    final valid = widget.validate?.call(value) ?? true;
    if (!valid || value == widget.text) {
      _controller.text = widget.text;
      return;
    }
    widget.onCommit(value);
  }

  @override
  void didUpdateWidget(CommitTextField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && old.text != widget.text) {
      _controller.text = widget.text;
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focus,
      keyboardType: widget.keyboardType,
      inputFormatters: widget.inputFormatters,
      decoration: InputDecoration(
        isDense: true,
        border: const OutlineInputBorder(),
        hintText: widget.hint,
      ),
      onSubmitted: (_) {
        _commit();
        editorFocusNode.requestFocus();
      },
    );
  }
}

/// Drawer-opening toolbar button; a dot shows when there are unsaved edits.
class SongDrawerButton extends ConsumerWidget {
  const SongDrawerButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dirty = ref.watch(projectProvider.select((s) => s.dirty));
    return IconButton(
      tooltip: 'File & song settings',
      visualDensity: VisualDensity.compact,
      icon: Badge(
        isLabelVisible: dirty,
        smallSize: 8,
        child: const Icon(Icons.tune),
      ),
      onPressed: () => scaffoldKey.currentState?.openEndDrawer(),
    );
  }
}
