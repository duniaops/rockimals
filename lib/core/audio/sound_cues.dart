/// The three Rockimals sounds, as note tables (`specs/05`, "Build the sound
/// engine") — the port of `playHappy`, `playSad`, and `playCheer`
/// (`index.html:965-967`).
///
/// **Data, not code, because that is what they are.** In the prototype each cue
/// is a one-line `forEach` over an array of `[frequency, start]` pairs with the
/// duration, waveform, and gain repeated in the call. Written out as [ToneNote]
/// tables here, every number a cue depends on is visible in one place and can be
/// retuned without touching a line of playback logic — and the suite can assert
/// the whole set against the prototype's figures in one table-driven pass.
///
/// The cues are musical, and worth naming as such, because the intervals are the
/// reason they read as encouraging rather than as beeps:
///
/// - **[SoundCue.happy]** — C5–E5–G5–C6, a rising major arpeggio. Unambiguously
///   "yes", which is the entire job: a child who got it right hears it before
///   they read anything.
/// - **[SoundCue.sad]** — G4 then D4, falling a fifth. Two soft sine notes, the
///   gentlest shape available, and *quieter* than the other two (`0.15` against
///   `0.2`). This is the guardrail in `CLAUDE.md` — "wrong answers are always
///   encouraging" — expressed in sound: it is a shrug, not a buzzer.
/// - **[SoundCue.cheer]** — E5–G5–B5–E6, a rising major arpeggio a third above
///   [SoundCue.happy] and a touch slower. Higher and longer, so a badge feels
///   bigger than a right answer without being louder than one.
library;

import 'package:rockimals/core/audio/tone_synth.dart';

/// The three sounds the app can make.
enum SoundCue {
  /// A right answer (`playHappy`, `index.html:965`). Also the confirmation blip
  /// when the sound toggle is switched back on (`index.html:1020`).
  happy,

  /// A wrong answer (`playSad`, `index.html:966`).
  sad,

  /// A newly earned badge (`playCheer`, `index.html:967`).
  ///
  /// **Its trigger does not exist yet.** In the prototype `playCheer` is called
  /// from exactly one place — `drainBadges()`, as the badge popup appears
  /// (`index.html:995`) — and the badge system is the *next* plan item. The cue
  /// is built and playable here because it is named in this item's scope; the
  /// call site lands with the popup it belongs to.
  cheer,
}

/// The notes of [cue], in the order the prototype schedules them.
List<ToneNote> notesFor(SoundCue cue) {
  switch (cue) {
    // `[[523,0],[659,.08],[784,.16],[1047,.25]].forEach(([f,s]) =>
    //  beep(f,s,.2,"triangle",0.2))` (`index.html:965`).
    case SoundCue.happy:
      return _arpeggio(
        const <List<double>>[
          <double>[523, 0],
          <double>[659, 0.08],
          <double>[784, 0.16],
          <double>[1047, 0.25],
        ],
        duration: 0.2,
        gain: 0.2,
      );

    // `beep(392,0,.24,"sine",0.15); beep(294,.17,.34,"sine",0.15);`
    // (`index.html:966`). The one cue whose notes differ in length, so it is
    // spelled out rather than run through [_arpeggio]: the second note is held
    // half again as long as the first, which is what makes it sigh.
    case SoundCue.sad:
      return const <ToneNote>[
        ToneNote(
          frequency: 392,
          start: 0,
          duration: 0.24,
          waveform: Waveform.sine,
          gain: 0.15,
        ),
        ToneNote(
          frequency: 294,
          start: 0.17,
          duration: 0.34,
          waveform: Waveform.sine,
          gain: 0.15,
        ),
      ];

    // `[[659,0],[784,.09],[988,.18],[1319,.28]].forEach(([f,s]) =>
    //  beep(f,s,.24,"triangle",0.2))` (`index.html:967`).
    case SoundCue.cheer:
      return _arpeggio(
        const <List<double>>[
          <double>[659, 0],
          <double>[784, 0.09],
          <double>[988, 0.18],
          <double>[1319, 0.28],
        ],
        duration: 0.24,
        gain: 0.2,
      );
  }
}

/// The two four-note triangle jingles share everything but their pitches and
/// timings, so they share a builder — the prototype's `forEach` over
/// `[frequency, start]` pairs, which is exactly this shape.
List<ToneNote> _arpeggio(
  List<List<double>> pitches, {
  required double duration,
  required double gain,
}) {
  return pitches
      .map(
        (List<double> pair) => ToneNote(
          frequency: pair[0],
          start: pair[1],
          duration: duration,
          waveform: Waveform.triangle,
          gain: gain,
        ),
      )
      .toList(growable: false);
}
