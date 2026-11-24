import 'package:flutter/material.dart';

const double keyboardWidth = 72;
const double rulerHeight = 30;
const double velocityHeight = 96;
const double trackPanelWidth = 240;
const double scrollbarThickness = 12;

/// Pixels from a note's right edge that act as a resize handle.
const double resizeHandleWidth = 7;

const trackColors = <Color>[
  Color(0xFF4FC3F7),
  Color(0xFFFF8A65),
  Color(0xFF81C784),
  Color(0xFFBA68C8),
  Color(0xFFFFD54F),
  Color(0xFF4DB6AC),
  Color(0xFFF06292),
  Color(0xFFA1887F),
];

Color trackColor(int index) => trackColors[index % trackColors.length];

const _blackKeys = {1, 3, 6, 8, 10};

bool isBlackKey(int pitch) => _blackKeys.contains(pitch % 12);

const _names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

/// Scientific pitch name where 60 is C4.
String pitchName(int pitch) => '${_names[pitch % 12]}${pitch ~/ 12 - 1}';

const generalMidiPrograms = [
  'Acoustic Grand Piano', 'Bright Acoustic Piano', 'Electric Grand Piano',
  'Honky-tonk Piano', 'Electric Piano 1', 'Electric Piano 2', 'Harpsichord',
  'Clavinet', 'Celesta', 'Glockenspiel', 'Music Box', 'Vibraphone',
  'Marimba', 'Xylophone', 'Tubular Bells', 'Dulcimer', 'Drawbar Organ',
  'Percussive Organ', 'Rock Organ', 'Church Organ', 'Reed Organ',
  'Accordion', 'Harmonica', 'Tango Accordion', 'Acoustic Guitar (nylon)',
  'Acoustic Guitar (steel)', 'Electric Guitar (jazz)',
  'Electric Guitar (clean)', 'Electric Guitar (muted)', 'Overdriven Guitar',
  'Distortion Guitar', 'Guitar Harmonics', 'Acoustic Bass',
  'Electric Bass (finger)', 'Electric Bass (pick)', 'Fretless Bass',
  'Slap Bass 1', 'Slap Bass 2', 'Synth Bass 1', 'Synth Bass 2', 'Violin',
  'Viola', 'Cello', 'Contrabass', 'Tremolo Strings', 'Pizzicato Strings',
  'Orchestral Harp', 'Timpani', 'String Ensemble 1', 'String Ensemble 2',
  'Synth Strings 1', 'Synth Strings 2', 'Choir Aahs', 'Voice Oohs',
  'Synth Voice', 'Orchestra Hit', 'Trumpet', 'Trombone', 'Tuba',
  'Muted Trumpet', 'French Horn', 'Brass Section', 'Synth Brass 1',
  'Synth Brass 2', 'Soprano Sax', 'Alto Sax', 'Tenor Sax', 'Baritone Sax',
  'Oboe', 'English Horn', 'Bassoon', 'Clarinet', 'Piccolo', 'Flute',
  'Recorder', 'Pan Flute', 'Blown Bottle', 'Shakuhachi', 'Whistle',
  'Ocarina', 'Lead 1 (square)', 'Lead 2 (sawtooth)', 'Lead 3 (calliope)',
  'Lead 4 (chiff)', 'Lead 5 (charang)', 'Lead 6 (voice)', 'Lead 7 (fifths)',
  'Lead 8 (bass + lead)', 'Pad 1 (new age)', 'Pad 2 (warm)',
  'Pad 3 (polysynth)', 'Pad 4 (choir)', 'Pad 5 (bowed)', 'Pad 6 (metallic)',
  'Pad 7 (halo)', 'Pad 8 (sweep)', 'FX 1 (rain)', 'FX 2 (soundtrack)',
  'FX 3 (crystal)', 'FX 4 (atmosphere)', 'FX 5 (brightness)',
  'FX 6 (goblins)', 'FX 7 (echoes)', 'FX 8 (sci-fi)', 'Sitar', 'Banjo',
  'Shamisen', 'Koto', 'Kalimba', 'Bagpipe', 'Fiddle', 'Shanai',
  'Tinkle Bell', 'Agogo', 'Steel Drums', 'Woodblock', 'Taiko Drum',
  'Melodic Tom', 'Synth Drum', 'Reverse Cymbal', 'Guitar Fret Noise',
  'Breath Noise', 'Seashore', 'Bird Tweet', 'Telephone Ring', 'Helicopter',
  'Applause', 'Gunshot',
];
