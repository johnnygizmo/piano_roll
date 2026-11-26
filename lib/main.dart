import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state/transport_provider.dart';
import 'ui/piano_roll_page.dart';
import 'ui/restore_gate.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Right-click is used for deleting notes, so suppress the browser menu.
  BrowserContextMenu.disableContextMenu().catchError((Object _) {});
  runApp(
    const ProviderScope(child: _AudioActivationGate(child: PianoRollApp())),
  );
}

class _AudioActivationGate extends ConsumerWidget {
  const _AudioActivationGate({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Listener(
      onPointerDown: (_) => unawaited(ref.read(audioProvider).unlock()),
      child: child,
    );
  }
}

class PianoRollApp extends StatelessWidget {
  const PianoRollApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Piano Roll',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        visualDensity: VisualDensity.compact,
      ),
      home: const RestoreGate(child: PianoRollPage()),
    );
  }
}
