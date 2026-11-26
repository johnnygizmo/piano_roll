import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;

import 'package:web/web.dart' as web;

import 'audio_engine.dart';

/// MIDI messages are handed to the browser this far ahead of their time (ms),
/// so stopAll() can still cancel everything that has not been sent yet.
const _midiSendAhead = 30.0;

class _PendingMidi {
  _PendingMidi(this.time, this.order, this.bytes);

  /// Browser time (performance.now) in milliseconds.
  final double time;

  /// Tie-breaker at equal times: note-off, program change, then note-on.
  final int order;
  final List<int> bytes;
}

extension type _MidiOutputMap._(JSObject _) implements JSObject {
  external void forEach(JSFunction callback);
}

/// Plays through the system's General MIDI synth (Web MIDI, e.g. "Microsoft
/// GS Wavetable Synth" on Windows) when the browser exposes one; otherwise
/// falls back to a simple Web Audio synth with a timbre per instrument family.
class _WebAudioEngine implements AudioEngine {
  web.AudioContext? _ctx;
  web.DynamicsCompressorNode? _compressor;
  web.GainNode? _bus;
  web.AudioBuffer? _noise;

  Future<void>? _midiSetup;
  web.MIDIOutput? _midiOut;
  bool _useSystemMidi = true;
  final _pending = <_PendingMidi>[];
  Timer? _midiTimer;

  web.AudioContext get _context => _ctx ??= web.AudioContext();

  // Notes connect to a bus; stopAll() disconnects it and starts a fresh one,
  // which silences every scheduled voice at once.
  web.GainNode get _out {
    final existing = _bus;
    if (existing != null) return existing;
    final ctx = _context;
    final compressor = _compressor ??= (() {
      final c = ctx.createDynamicsCompressor();
      c.connect(ctx.destination);
      return c;
    })();
    final bus = ctx.createGain();
    bus.gain.value = 0.5;
    bus.connect(compressor);
    return _bus = bus;
  }

  @override
  double get currentTime => _context.currentTime;

  @override
  Future<void> unlock() async {
    final ctx = _context;
    if (ctx.state != 'running') {
      await ctx.resume().toDart;
    }
  }

  @override
  Future<void> resume() async {
    await unlock();
    if (_useSystemMidi) {
      unawaited(_midiSetup ??= _openMidi());
    }
  }

  @override
  void setUseSystemMidi(bool enabled) {
    if (_useSystemMidi == enabled) return;
    stopAll();
    _useSystemMidi = enabled;
  }

  Future<void> _openMidi() async {
    try {
      final access = await web.window.navigator.requestMIDIAccess().toDart;
      web.MIDIOutput? chosen;
      web.MIDIOutput? first;
      (access.outputs as _MidiOutputMap).forEach(
        ((web.MIDIOutput output, JSAny? key, JSAny? map) {
          first ??= output;
          final name = (output.name ?? '').toLowerCase();
          if (chosen == null &&
              (name.contains('wavetable') || name.contains('gs '))) {
            chosen = output;
          }
        }).toJS,
      );
      _midiOut = chosen ?? first;
    } catch (_) {
      // No Web MIDI support or permission denied: keep the built-in synth.
    }
  }

  @override
  void playNote({
    required int pitch,
    required int velocity,
    required double when,
    required double duration,
    bool drum = false,
    int program = 0,
    int channel = 0,
  }) {
    if (_useSystemMidi && _midiOut != null) {
      _playMidi(pitch, velocity, when, duration, drum, program, channel);
    } else {
      _playOscillator(pitch, velocity, when, duration, drum, program);
    }
  }

  void _playMidi(
    int pitch,
    int velocity,
    double when,
    double duration,
    bool drum,
    int program,
    int channel,
  ) {
    final ch = drum ? 9 : channel & 0x0F;
    final start =
        web.window.performance.now() + (when - _context.currentTime) * 1000;
    final end = start + math.max(duration, 0.02) * 1000;
    _pending
      ..add(_PendingMidi(start, 1, [0xC0 | ch, program & 0x7F]))
      ..add(_PendingMidi(start, 2, [0x90 | ch, pitch & 0x7F, velocity & 0x7F]))
      ..add(_PendingMidi(end, 0, [0x80 | ch, pitch & 0x7F, 0]));
    _midiTimer ??= Timer.periodic(
      const Duration(milliseconds: 10),
      (_) => _flushMidi(),
    );
    _flushMidi();
  }

  void _flushMidi() {
    final out = _midiOut;
    if (out == null) return;
    final horizon = web.window.performance.now() + _midiSendAhead;
    final due = _pending.where((m) => m.time <= horizon).toList()
      ..sort((a, b) {
        final t = a.time.compareTo(b.time);
        return t != 0 ? t : a.order.compareTo(b.order);
      });
    if (due.isNotEmpty) {
      _pending.removeWhere((m) => m.time <= horizon);
      for (final m in due) {
        out.send([for (final b in m.bytes) b.toJS].toJS, m.time);
      }
    }
    if (_pending.isEmpty) {
      _midiTimer?.cancel();
      _midiTimer = null;
    }
  }

  void _playOscillator(
    int pitch,
    int velocity,
    double when,
    double duration,
    bool drum,
    int program,
  ) {
    final ctx = _context;
    final t = math.max(when, ctx.currentTime);
    final peak = math.pow(velocity / 127, 1.5).toDouble() * 0.35;
    final gain = ctx.createGain();
    gain.connect(_out);

    if (drum) {
      final src = ctx.createBufferSource();
      src.buffer = _noiseBuffer(ctx);
      final filter = ctx.createBiquadFilter();
      filter.type = 'bandpass';
      filter.frequency.value = 200 + pitch * 40;
      src.connect(filter);
      filter.connect(gain);
      gain.gain.setValueAtTime(peak * 1.5, t);
      gain.gain.exponentialRampToValueAtTime(0.001, t + 0.15);
      src.start(t);
      src.stop(t + 0.2);
      return;
    }

    final timbre = _timbres[(program & 0x7F) >> 3];
    final osc = ctx.createOscillator();
    osc.type = timbre.wave;
    osc.frequency.value = 440 * math.pow(2, (pitch - 69) / 12);
    osc.connect(gain);

    final end = t + math.max(duration, 0.02);
    gain.gain.setValueAtTime(0, t);
    gain.gain.linearRampToValueAtTime(peak, t + timbre.attack);
    gain.gain.setTargetAtTime(
      peak * timbre.sustain,
      t + timbre.attack,
      timbre.decay,
    );
    gain.gain.setTargetAtTime(0, end, 0.04);
    osc.start(t);
    osc.stop(end + 0.3);
  }

  web.AudioBuffer _noiseBuffer(web.AudioContext ctx) {
    final existing = _noise;
    if (existing != null) return existing;
    final length = (ctx.sampleRate * 0.5).round();
    final buffer = ctx.createBuffer(1, length, ctx.sampleRate);
    final data = buffer.getChannelData(0).toDart;
    final rng = math.Random(1);
    for (var i = 0; i < data.length; i++) {
      data[i] = rng.nextDouble() * 2 - 1;
    }
    return _noise = buffer;
  }

  @override
  void stopAll() {
    _bus?.disconnect();
    _bus = null;

    _pending.clear();
    _midiTimer?.cancel();
    _midiTimer = null;
    final out = _midiOut;
    if (out != null) {
      for (var ch = 0; ch < 16; ch++) {
        out.send([(0xB0 | ch).toJS, 120.toJS, 0.toJS].toJS); // all sound off
        out.send([(0xB0 | ch).toJS, 123.toJS, 0.toJS].toJS); // all notes off
      }
    }
  }
}

class _Timbre {
  const _Timbre(this.wave, this.attack, this.sustain, this.decay);
  final String wave;
  final double attack;

  /// Level held after the attack, relative to the peak.
  final double sustain;
  final double decay;
}

/// Web Audio fallback voices, one per General MIDI family (program ~/ 8).
const _timbres = <_Timbre>[
  _Timbre('triangle', 0.01, 0.4, 0.25), // piano
  _Timbre('sine', 0.005, 0.3, 0.4), // chromatic percussion
  _Timbre('square', 0.02, 0.8, 0.1), // organ
  _Timbre('triangle', 0.005, 0.25, 0.2), // guitar
  _Timbre('sawtooth', 0.01, 0.6, 0.15), // bass
  _Timbre('sawtooth', 0.08, 0.9, 0.1), // strings
  _Timbre('sawtooth', 0.06, 0.85, 0.1), // ensemble
  _Timbre('square', 0.04, 0.8, 0.1), // brass
  _Timbre('square', 0.05, 0.75, 0.1), // reed
  _Timbre('sine', 0.05, 0.9, 0.1), // pipe
  _Timbre('sawtooth', 0.02, 0.8, 0.1), // synth lead
  _Timbre('triangle', 0.15, 0.9, 0.2), // synth pad
  _Timbre('triangle', 0.05, 0.6, 0.3), // synth effects
  _Timbre('triangle', 0.005, 0.3, 0.2), // ethnic
  _Timbre('sine', 0.005, 0.2, 0.1), // percussive
  _Timbre('triangle', 0.1, 0.7, 0.3), // sound effects
];

AudioEngine createAudioEngineImpl() => _WebAudioEngine();
