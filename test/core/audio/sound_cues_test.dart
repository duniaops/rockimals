/// The three cues (`specs/05`, "Build the sound engine").
///
/// **A table check against the prototype, because a mistyped digit here is a
/// bug nothing else can catch.** Every other test in this feature would pass with
/// 523Hz written as 532: the envelope would still be exponential, the WAV would
/// still be well-formed, the toggle would still gate it, and the only symptom
/// would be a jingle that is subtly wrong to an ear nobody on this project can
/// currently bring to it (no Xcode, no Android SDK). So the numbers themselves
/// are pinned against `index.html:965-967`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/audio/sound_cues.dart';
import 'package:rockimals/core/audio/tone_synth.dart';

void main() {
  group('the note tables match the prototype exactly', () {
    test('happy is the C major arpeggio from playHappy', () {
      // `[[523,0],[659,.08],[784,.16],[1047,.25]] … beep(f,s,.2,"triangle",0.2)`
      final List<ToneNote> notes = notesFor(SoundCue.happy);
      expect(notes.map((ToneNote n) => n.frequency), <double>[523, 659, 784, 1047]);
      expect(notes.map((ToneNote n) => n.start), <double>[0, 0.08, 0.16, 0.25]);
      expect(notes.every((ToneNote n) => n.duration == 0.2), isTrue);
      expect(notes.every((ToneNote n) => n.waveform == Waveform.triangle), isTrue);
      expect(notes.every((ToneNote n) => n.gain == 0.2), isTrue);
    });

    test('sad is the two falling sine notes from playSad', () {
      // `beep(392,0,.24,"sine",0.15); beep(294,.17,.34,"sine",0.15)`
      final List<ToneNote> notes = notesFor(SoundCue.sad);
      expect(notes.map((ToneNote n) => n.frequency), <double>[392, 294]);
      expect(notes.map((ToneNote n) => n.start), <double>[0, 0.17]);
      expect(notes.map((ToneNote n) => n.duration), <double>[0.24, 0.34]);
      expect(notes.every((ToneNote n) => n.waveform == Waveform.sine), isTrue);
      expect(notes.every((ToneNote n) => n.gain == 0.15), isTrue);
    });

    test('cheer is the E major arpeggio from playCheer', () {
      // `[[659,0],[784,.09],[988,.18],[1319,.28]] … beep(f,s,.24,"triangle",0.2)`
      final List<ToneNote> notes = notesFor(SoundCue.cheer);
      expect(notes.map((ToneNote n) => n.frequency), <double>[659, 784, 988, 1319]);
      expect(notes.map((ToneNote n) => n.start), <double>[0, 0.09, 0.18, 0.28]);
      expect(notes.every((ToneNote n) => n.duration == 0.24), isTrue);
      expect(notes.every((ToneNote n) => n.waveform == Waveform.triangle), isTrue);
      expect(notes.every((ToneNote n) => n.gain == 0.2), isTrue);
    });
  });

  group('the qualities that make these cues kind', () {
    test('the wrong-answer cue is the quietest of the three', () {
      // `CLAUDE.md`: "Wrong answers are always encouraging." The sad cue being
      // softer than the happy one is that rule expressed in sound — it is a
      // shrug, not a buzzer — and it is the kind of thing a later retune could
      // undo without anyone noticing. Pinned deliberately.
      final double sad = notesFor(SoundCue.sad).first.gain;
      for (final SoundCue cue in <SoundCue>[SoundCue.happy, SoundCue.cheer]) {
        expect(notesFor(cue).first.gain, greaterThan(sad));
      }
    });

    test('the wrong-answer cue falls; the other two rise', () {
      // Direction is what carries the meaning before any word is read.
      expect(_isAscending(notesFor(SoundCue.happy)), isTrue);
      expect(_isAscending(notesFor(SoundCue.cheer)), isTrue);
      expect(_isAscending(notesFor(SoundCue.sad)), isFalse);
    });

    test('cheer sits above happy, so a badge outranks a right answer', () {
      final List<ToneNote> happy = notesFor(SoundCue.happy);
      final List<ToneNote> cheer = notesFor(SoundCue.cheer);
      for (int i = 0; i < happy.length; i++) {
        expect(cheer[i].frequency, greaterThan(happy[i].frequency));
      }
      // …and is a touch longer, without being louder.
      expect(cheer.first.duration, greaterThan(happy.first.duration));
      expect(cheer.first.gain, happy.first.gain);
    });

    test('every cue is short enough not to trail the next answer', () {
      // A child can answer again quickly; a cue that outlasts the gap would
      // overlap itself. All three stay under two thirds of a second.
      for (final SoundCue cue in SoundCue.values) {
        final double span = notesFor(cue)
            .map((ToneNote n) => n.end)
            .reduce((double a, double b) => a > b ? a : b);
        expect(span, lessThan(0.65), reason: '$cue runs $span s');
      }
    });
  });

  group('every cue renders to real, clean audio', () {
    test('none of the three clips', () {
      // The clamp in `renderSamples` is a guard against a crack, and these gain
      // choices are what keep it from ever engaging. If a retune pushes a cue
      // into the clamp, this fails before an ear has to.
      for (final SoundCue cue in SoundCue.values) {
        final double peak = renderSamples(notesFor(cue)).fold<double>(
          0,
          (double m, double s) => s.abs() > m ? s.abs() : m,
        );
        expect(peak, lessThan(1.0), reason: '$cue peaks at $peak');
        expect(peak, greaterThan(0.05), reason: '$cue is too quiet to hear');
      }
    });

    test('each encodes to a WAV of a plausible size', () {
      for (final SoundCue cue in SoundCue.values) {
        final int bytes = encodeWav(notesFor(cue)).length;
        // 44-byte header + 2 bytes per sample of a roughly half-second cue.
        expect(bytes, greaterThan(44));
        expect(bytes, lessThan(kSampleRate * 2));
      }
    });

    test('every cue in the enum has notes — none is a stub', () {
      for (final SoundCue cue in SoundCue.values) {
        expect(notesFor(cue), isNotEmpty, reason: '$cue has no notes');
      }
    });
  });
}

/// Whether [notes] climb in pitch from first to last.
bool _isAscending(List<ToneNote> notes) {
  for (int i = 1; i < notes.length; i++) {
    if (notes[i].frequency <= notes[i - 1].frequency) {
      return false;
    }
  }
  return true;
}
