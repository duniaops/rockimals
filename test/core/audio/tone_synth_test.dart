/// The tone synthesiser (`specs/05`, "Build the sound engine").
///
/// **This suite exists because it is the only part of the sound feature a machine
/// in this project can check at all.** There is no Xcode and no Android SDK (the
/// human-gated plan item), so nothing here has ever made an audible noise. What
/// saves the port from being unverified is that `tone_synth.dart` is pure
/// arithmetic: the envelope, the waveforms, the mixing, and the WAV container can
/// each be asserted exactly, and if all four are right then the bytes handed to
/// the speaker are right. Only the handoff itself rests on a device.
///
/// So the assertions below are deliberately about *values*, not about "it ran".
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/audio/tone_synth.dart';

/// Floating-point slack. The envelope is built from `pow`, so exact equality is
/// not available; this is far tighter than any audible difference.
const double _tol = 1e-9;

/// [duration] and [gain] have no defaults on purpose: they are what most of the
/// assertions below are *about*, so every call states them.
ToneNote _note({
  required double duration,
  required double gain,
  double frequency = 440,
  double start = 0,
  Waveform waveform = Waveform.sine,
}) => ToneNote(
  frequency: frequency,
  start: start,
  duration: duration,
  waveform: waveform,
  gain: gain,
);

void main() {
  group('the gain envelope', () {
    final ToneNote note = _note(duration: 0.2, gain: 0.2);

    test('opens at the silence floor, not at zero', () {
      // Ported precisely: WebAudio's exponential ramp has no zero endpoint (a
      // constant ratio never reaches zero), so the prototype starts at 0.0001.
      expect(envelopeAt(note, 0), closeTo(kSilenceGain, _tol));
    });

    test('reaches the note\'s peak exactly at the end of the attack', () {
      expect(envelopeAt(note, kAttackSeconds), closeTo(0.2, _tol));
    });

    test('is back at the floor when the note\'s duration is up', () {
      expect(envelopeAt(note, 0.2), closeTo(kSilenceGain, _tol));
    });

    test('rises monotonically through the attack and falls after it', () {
      double previous = -1;
      for (int i = 0; i <= 20; i++) {
        final double v = envelopeAt(note, kAttackSeconds * i / 20);
        expect(v, greaterThan(previous), reason: 'attack must only rise');
        previous = v;
      }
      previous = double.infinity;
      for (int i = 0; i <= 20; i++) {
        final double v = envelopeAt(
          note,
          kAttackSeconds + (0.2 - kAttackSeconds) * i / 20,
        );
        expect(v, lessThan(previous), reason: 'decay must only fall');
        previous = v;
      }
    });

    test('decays by a constant ratio — the reason it sounds plucked', () {
      // The whole character of the sound is that it is exponential, not linear:
      // equal time steps drop the gain by equal *factors*, which is what an ear
      // reads as an even fade. Linear would sound like it hangs and then stops.
      const double span = 0.2 - kAttackSeconds;
      final double a = envelopeAt(note, kAttackSeconds + span * 0.25);
      final double b = envelopeAt(note, kAttackSeconds + span * 0.5);
      final double c = envelopeAt(note, kAttackSeconds + span * 0.75);
      expect(a / b, closeTo(b / c, 1e-6));
    });

    test('holds the floor through the silent tail, then stops', () {
      // `o.stop(t+dur+0.03)` — the oscillator outlives the envelope so it is
      // switched off during silence rather than mid-cycle (which would click).
      expect(
        envelopeAt(note, 0.2 + kTailSeconds / 2),
        closeTo(kSilenceGain, _tol),
      );
      expect(envelopeAt(note, 0.2 + kTailSeconds + 0.001), 0);
    });

    test('is silent before the note starts', () {
      expect(envelopeAt(note, -0.01), 0);
    });

    test('scales to whatever peak the note asks for', () {
      // The sad cue is quieter than the others (0.15 against 0.2) and that is
      // load-bearing kindness, not a typo — see `sound_cues.dart`.
      expect(
        envelopeAt(_note(duration: 0.2, gain: 0.15), kAttackSeconds),
        closeTo(0.15, _tol),
      );
    });
  });

  group('the waveforms', () {
    test('the sine is a sine', () {
      for (final double p in <double>[0, 0.125, 0.25, 0.5, 0.75, 0.9]) {
        expect(
          waveAt(Waveform.sine, p),
          closeTo(math.sin(2 * math.pi * p), _tol),
        );
      }
    });

    test('the triangle hits its corners where a triangle should', () {
      expect(waveAt(Waveform.triangle, 0), closeTo(0, _tol));
      expect(waveAt(Waveform.triangle, 0.25), closeTo(1, _tol));
      expect(waveAt(Waveform.triangle, 0.5), closeTo(0, _tol));
      expect(waveAt(Waveform.triangle, 0.75), closeTo(-1, _tol));
    });

    test('the triangle is linear between its corners', () {
      // The defining property, and the one a botched phase shift breaks: equal
      // steps in phase give equal steps in value.
      expect(waveAt(Waveform.triangle, 0.125), closeTo(0.5, _tol));
      expect(waveAt(Waveform.triangle, 0.375), closeTo(0.5, _tol));
      expect(waveAt(Waveform.triangle, 0.625), closeTo(-0.5, _tol));
    });

    test('both leave zero rising, like an oscillator started at phase 0', () {
      for (final Waveform w in Waveform.values) {
        expect(waveAt(w, 0), closeTo(0, _tol));
        expect(
          waveAt(w, 0.01),
          greaterThan(0),
          reason: '$w must rise from zero',
        );
      }
    });

    test('both repeat every cycle', () {
      for (final Waveform w in Waveform.values) {
        for (final double p in <double>[0.1, 0.3, 0.6, 0.85]) {
          expect(waveAt(w, p), closeTo(waveAt(w, p + 3), _tol));
        }
      }
    });

    test('both stay inside the representable range', () {
      for (final Waveform w in Waveform.values) {
        for (int i = 0; i < 200; i++) {
          expect(waveAt(w, i / 37), inInclusiveRange(-1, 1));
        }
      }
    });
  });

  group('rendering', () {
    test('an empty note list renders nothing', () {
      expect(renderSamples(const <ToneNote>[]), isEmpty);
    });

    test('the buffer is as long as the last note runs, tail included', () {
      final Float64List out = renderSamples(<ToneNote>[
        _note(duration: 0.2, gain: 0.2),
        _note(start: 0.25, duration: 0.2, gain: 0.2),
      ]);
      // 0.25 + 0.2 + 0.03 = 0.48s.
      expect(out.length, (0.48 * kSampleRate).ceil());
    });

    test('a note contributes nothing before it starts', () {
      final Float64List out = renderSamples(<ToneNote>[
        _note(start: 0.1, duration: 0.2, gain: 0.2),
      ]);
      for (int i = 0; i < (0.1 * kSampleRate).floor(); i++) {
        expect(out[i], 0, reason: 'sample $i is before the note begins');
      }
      // And something after.
      expect(
        out
            .sublist((0.1 * kSampleRate).ceil())
            .any((double s) => s.abs() > 0.01),
        isTrue,
      );
    });

    test('overlapping notes sum — the overlap is the chord', () {
      // Two identical simultaneous notes must be twice one of them. This is what
      // makes the four-note jingles read as arpeggios ringing together rather
      // than as four separate beeps.
      final Float64List one = renderSamples(<ToneNote>[
        _note(duration: 0.2, gain: 0.2),
      ]);
      final Float64List two = renderSamples(<ToneNote>[
        _note(duration: 0.2, gain: 0.2),
        _note(duration: 0.2, gain: 0.2),
      ]);
      for (int i = 0; i < one.length; i += 97) {
        expect(two[i], closeTo(one[i] * 2, _tol));
      }
    });

    test('a sum that would leave the range is clamped, not wrapped', () {
      // A guard, not part of any shipped cue (`sound_cues_test.dart` pins that
      // none of the three gets near it). It matters because the alternative to
      // clamping is integer wraparound in `encodeWav`, which turns a loud moment
      // into a violent crack — the opposite of a gentle app.
      final Float64List out = renderSamples(
        List<ToneNote>.filled(12, _note(duration: 0.2, gain: 1.0)),
      );
      expect(out.every((double s) => s >= -1.0 && s <= 1.0), isTrue);
      expect(
        out.any((double s) => s.abs() == 1.0),
        isTrue,
        reason: 'twelve full-gain notes should actually reach the clamp',
      );
    });

    test('a rendered note peaks near its gain, shortly after it starts', () {
      final Float64List out = renderSamples(<ToneNote>[
        _note(duration: 0.2, gain: 0.2),
      ]);
      final double peak = out.fold<double>(
        0,
        (double m, double s) => math.max(m, s.abs()),
      );
      expect(peak, closeTo(0.2, 0.01));
    });
  });

  group('the WAV container', () {
    final Uint8List wav = encodeWav(<ToneNote>[
      _note(duration: 0.2, gain: 0.2),
    ]);
    final ByteData view = ByteData.sublistView(wav);

    String tag(int offset) =>
        String.fromCharCodes(wav.sublist(offset, offset + 4));

    test('carries the four RIFF/WAVE tags in reading order', () {
      // Regression guard on the one genuinely error-prone line in the encoder:
      // the tags are ASCII and must be big-endian while every number around them
      // is little-endian. Getting it backwards yields "FFIR", which no decoder
      // will touch.
      expect(tag(0), 'RIFF');
      expect(tag(8), 'WAVE');
      expect(tag(12), 'fmt ');
      expect(tag(36), 'data');
    });

    test('declares uncompressed 16-bit mono PCM at the sample rate', () {
      expect(view.getUint32(16, Endian.little), 16, reason: 'fmt chunk length');
      expect(
        view.getUint16(20, Endian.little),
        1,
        reason: '1 = uncompressed PCM',
      );
      expect(view.getUint16(22, Endian.little), 1, reason: 'mono');
      expect(view.getUint32(24, Endian.little), kSampleRate);
      expect(view.getUint16(34, Endian.little), 16, reason: 'bits per sample');
    });

    test('its byte rate and block align agree with that declaration', () {
      // A decoder trusts these rather than recomputing them, so a mismatch plays
      // the cue at the wrong speed instead of failing loudly.
      final int channels = view.getUint16(22, Endian.little);
      final int bits = view.getUint16(34, Endian.little);
      final int rate = view.getUint32(24, Endian.little);
      expect(view.getUint32(28, Endian.little), rate * channels * bits ~/ 8);
      expect(view.getUint16(32, Endian.little), channels * bits ~/ 8);
    });

    test('both declared sizes match the bytes actually present', () {
      final int dataBytes = view.getUint32(40, Endian.little);
      expect(dataBytes, wav.length - 44);
      expect(view.getUint32(4, Endian.little), wav.length - 8);
    });

    test('holds one 16-bit sample per rendered sample', () {
      final Float64List samples = renderSamples(<ToneNote>[
        _note(duration: 0.2, gain: 0.2),
      ]);
      expect(wav.length, 44 + samples.length * 2);
      for (int i = 0; i < samples.length; i += 101) {
        expect(
          view.getInt16(44 + i * 2, Endian.little),
          (samples[i] * 32767).round(),
        );
      }
    });

    test('a full-scale sample encodes without wrapping', () {
      // 32767, not 32768: scaling +1.0 by 32768 overflows a signed 16-bit int and
      // wraps to -32768 — silence's opposite, a full-amplitude click.
      final Uint8List loud = encodeWav(
        List<ToneNote>.filled(12, _note(duration: 0.2, gain: 1.0)),
      );
      final ByteData loudView = ByteData.sublistView(loud);
      for (int i = 44; i < loud.length; i += 2) {
        expect(
          loudView.getInt16(i, Endian.little),
          inInclusiveRange(-32768, 32767),
        );
      }
    });

    test('an honest empty cue is a valid, empty WAV', () {
      final Uint8List empty = encodeWav(const <ToneNote>[]);
      expect(empty.length, 44);
      expect(ByteData.sublistView(empty).getUint32(40, Endian.little), 0);
    });
  });
}
