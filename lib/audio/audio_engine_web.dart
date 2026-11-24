import 'dart:js_interop';
import 'dart:math' as math;

import 'package:web/web.dart' as web;

import 'audio_engine.dart';

/// Oscillator-based synth built on the Web Audio API.
class _WebAudioEngine implements AudioEngine {
  web.AudioContext? _ctx;
  web.DynamicsCompressorNode? _compressor;
  web.GainNode? _bus;
  web.AudioBuffer? _noise;

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
  Future<void> resume() async {
    final ctx = _context;
    if (ctx.state == 'suspended') {
      await ctx.resume().toDart;
    }
  }

  @override
  void playNote({
    required int pitch,
    required int velocity,
    required double when,
    required double duration,
    bool drum = false,
  }) {
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

    final osc = ctx.createOscillator();
    osc.type = 'triangle';
    osc.frequency.value = 440 * math.pow(2, (pitch - 69) / 12);
    osc.connect(gain);

    final end = t + math.max(duration, 0.02);
    gain.gain.setValueAtTime(0, t);
    gain.gain.linearRampToValueAtTime(peak, t + 0.01);
    gain.gain.setTargetAtTime(peak * 0.7, t + 0.01, 0.25);
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
  }
}

AudioEngine createAudioEngineImpl() => _WebAudioEngine();
