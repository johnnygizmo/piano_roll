@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:flutter_test/flutter_test.dart';
import 'package:piano_roll/audio/audio_engine.dart';
import 'package:web/web.dart' as web;

@JS('eval')
external JSAny? _eval(JSString source);

int _count(String expression) => (_eval(expression.toJS) as JSNumber).toDartInt;

void main() {
  setUp(() {
    _eval(
      '''
      globalThis.originalAudioContext = globalThis.AudioContext;
      globalThis.audioTest = { resumes: 0, starts: 0, closes: 0 };
      globalThis.AudioContext = class {
        constructor() {
          this.state = 'suspended';
          this.sampleRate = 44100;
          this.currentTime = 0;
          this.destination = {};
          audioTest.context = this;
        }
        createBuffer() { return {}; }
        createBufferSource() {
          return { connect() {}, start() { audioTest.starts++; } };
        }
        resume() {
          audioTest.resumes++;
          this.state = 'running';
          return Promise.resolve();
        }
        close() { audioTest.closes++; return Promise.resolve(); }
      };
    '''
          .toJS,
    );
  });

  tearDown(() {
    _eval('globalThis.AudioContext = globalThis.originalAudioContext;'.toJS);
  });

  test(
    'native gestures activate and reactivate audio until disposal',
    () async {
      final audio = createAudioEngine();
      web.document.dispatchEvent(web.Event('touchend'));
      expect(_count('audioTest.resumes'), 1);
      expect(_count('audioTest.starts'), 1);

      await audio.resume();
      expect(_count('audioTest.resumes'), 1);

      _eval("audioTest.context.state = 'interrupted';".toJS);
      web.document.dispatchEvent(web.Event('pointerdown'));
      expect(_count('audioTest.resumes'), 2);
      expect(_count('audioTest.starts'), 2);

      audio.dispose();
      web.document.dispatchEvent(web.Event('keydown'));
      expect(_count('audioTest.resumes'), 2);
      expect(_count('audioTest.closes'), 1);
    },
  );
}
