/// The tone synthesiser (`specs/05`, "Build the sound engine") — the port of the
/// prototype's `beep()` (`index.html:961-964`), which builds every Rockimals
/// sound from oscillators at runtime.
///
/// **Why synthesis rather than bundled clips.** `specs/05` allows either ("or a
/// few tiny bundled clips") and ends "No audio asset dependencies required". The
/// prototype takes the synthesis branch, and porting it keeps three properties
/// worth having: the app ships no audio bytes (it already works offline, and this
/// adds nothing to download), the cues stay *readable as data* — a note table
/// anyone can retune without an editor — and, most usefully here, the whole thing
/// is arithmetic, so it can be tested to the sample on the host VM instead of
/// only by ear on a device.
///
/// **This file is deliberately plugin-free** — it reaches no platform channel and
/// imports nothing beyond `dart:math` and Flutter's annotations. It turns a note
/// table into WAV bytes and stops there; handing those bytes to a speaker is
/// [SoundEngine]'s job (`sound_engine.dart`). That seam is what lets the entire
/// envelope, waveform, mixing, and encoding be verified without an audio device —
/// the one part of this feature a machine can actually check.
///
/// See `sound_cues.dart` for the three cues themselves.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Samples per second. CD rate — the WebAudio default on every desktop browser,
/// so the prototype's tones were authored against it, and comfortably above the
/// ~2.6kHz top partial these cues reach.
const int kSampleRate = 44100;

/// The attack: how long the gain takes to ramp from silence to a note's peak
/// (`exponentialRampToValueAtTime(gain, t+0.02)`, `index.html:963`). Short enough
/// to read as a chime rather than a swell, long enough to avoid a click.
const double kAttackSeconds = 0.02;

/// The floor an exponential ramp starts from and returns to
/// (`setValueAtTime(0.0001, t)`, `index.html:963`).
///
/// **It is not zero, and it cannot be.** WebAudio's `exponentialRampToValueAtTime`
/// is undefined for a zero endpoint — the ramp is a constant *ratio* per unit
/// time, and no number of doublings reaches zero from zero. `0.0001` is −80dB,
/// which is silence to an ear but a legal endpoint to the maths. Ported as-is
/// because the audible curve is the shape between this floor and the peak.
const double kSilenceGain = 0.0001;

/// The pad after a note's envelope ends, before its oscillator stops
/// (`o.stop(t+dur+0.03)`, `index.html:964`).
///
/// Inaudible by construction — the gain has already reached [kSilenceGain] — and
/// kept only so a cue's rendered length matches the prototype's exactly. In
/// WebAudio the pad exists to stop the oscillator at a moment the envelope has
/// already silenced, rather than cutting a live waveform mid-cycle and clicking.
const double kTailSeconds = 0.03;

/// An oscillator shape. Only the two the prototype uses
/// (`o.type = type || "sine"`, `index.html:962`); the cues are all `sine` or
/// `triangle`.
enum Waveform {
  /// The pure tone the "aww" is built from — no harmonics, so it reads as soft.
  sine,

  /// The brighter shape the happy and cheer jingles use. Odd harmonics only,
  /// falling off as 1/n², so it sparkles without the buzz of a square.
  triangle,
}

/// One note of a cue: an oscillator with a fixed [frequency], switched on at
/// [start] and shaped by an attack-then-decay gain envelope spanning [duration].
///
/// The five arguments of `beep(freq, start, dur, type, gain)`
/// (`index.html:961`), named — at four call sites with positional booleans and
/// bare numbers, a note table reads far better spelled out.
@immutable
class ToneNote {
  const ToneNote({
    required this.frequency,
    required this.start,
    required this.duration,
    required this.waveform,
    required this.gain,
  });

  /// Pitch in hertz, constant for the note's life (`o.frequency.value = freq`) —
  /// none of the cues glide.
  final double frequency;

  /// Seconds from the start of the *cue* at which this note begins. What makes
  /// the four-note jingles arpeggios rather than chords.
  final double start;

  /// Seconds the gain envelope spans, from the note's start to the moment it is
  /// back at [kSilenceGain]. The note's audible length.
  final double duration;

  /// The oscillator shape.
  final Waveform waveform;

  /// Peak gain, reached at the end of the attack. Below 1.0 so several
  /// overlapping notes sum without clipping — see [renderSamples].
  final double gain;

  /// When this note's oscillator stops, including the silent [kTailSeconds] pad.
  double get end => start + duration + kTailSeconds;
}

/// The gain envelope of [note] at [t] seconds *after that note started*.
///
/// Two exponential ramps, exactly as the prototype schedules them
/// (`index.html:963`): up from [kSilenceGain] to [ToneNote.gain] over
/// [kAttackSeconds], then down again over the rest of [ToneNote.duration].
///
/// **Exponential, not linear, and it is the whole character of the sound.**
/// Loudness is perceived roughly logarithmically, so a gain that falls by a
/// constant *ratio* per unit time is what an ear hears as a smooth, even decay —
/// a plucked note. A linear ramp to zero sounds like it hangs and then drops. The
/// curve between two ramp endpoints is `v0 * (v1/v0)^(elapsed/span)`, which is
/// what WebAudio defines and what this reproduces.
@visibleForTesting
double envelopeAt(ToneNote note, double t) {
  if (t < 0 || t > note.duration + kTailSeconds) {
    return 0;
  }
  if (t <= kAttackSeconds) {
    return kSilenceGain *
        math.pow(note.gain / kSilenceGain, t / kAttackSeconds).toDouble();
  }
  if (t <= note.duration) {
    return note.gain *
        math
            .pow(
              kSilenceGain / note.gain,
              (t - kAttackSeconds) / (note.duration - kAttackSeconds),
            )
            .toDouble();
  }
  // The silent pad: the envelope has finished but the oscillator has not stopped.
  return kSilenceGain;
}

/// The value of [waveform] at [cycles] elapsed periods (so `0.25` is a quarter of
/// the way through one), in `[-1, 1]`.
///
/// **The triangle is the naive one, and the aliasing that costs is inaudible
/// here.** WebAudio builds its `triangle` from a band-limited `PeriodicWave`, so
/// no partial ever exceeds Nyquist. Summing harmonics per sample to match that
/// would be far more code for a difference that does not arrive: a triangle's nth
/// partial carries 1/n² of the fundamental, so for the highest note in any cue
/// (1319Hz, cheer) the first partial to fold back over 22.05kHz is the 33rd, at
/// about −60dB. That is beneath the noise floor of any phone speaker a child will
/// hold. Written as arithmetic instead, where it can be checked exactly.
///
/// Both shapes start at zero and rise, matching an oscillator started at phase 0.
@visibleForTesting
double waveAt(Waveform waveform, double cycles) {
  final double phase = cycles - cycles.floorToDouble();
  switch (waveform) {
    case Waveform.sine:
      return math.sin(2 * math.pi * phase);
    case Waveform.triangle:
      // Shifted a quarter period so it leaves zero rising, like the sine.
      final double shifted = (phase + 0.75) - (phase + 0.75).floorToDouble();
      return 4 * (shifted - 0.5).abs() - 1;
  }
}

/// Render [notes] to mono samples in `[-1, 1]` at [sampleRate].
///
/// Every note is summed into one buffer — the notes of a cue overlap, and that
/// overlap *is* the chord — then clamped, which is what a real output device does
/// with a sum that leaves the representable range. The cue tables keep peak gains
/// low enough (`0.15`–`0.2`) that four overlapping notes stay well inside it, so
/// the clamp is a guard rather than part of the sound; `sound_cues_test.dart`
/// pins that no shipped cue actually reaches it.
Float64List renderSamples(
  List<ToneNote> notes, {
  int sampleRate = kSampleRate,
}) {
  if (notes.isEmpty) {
    return Float64List(0);
  }
  final double span = notes
      .map((ToneNote n) => n.end)
      .reduce((double a, double b) => a > b ? a : b);
  final Float64List out = Float64List((span * sampleRate).ceil());

  for (final ToneNote note in notes) {
    final int from = (note.start * sampleRate).floor();
    final int to = math.min((note.end * sampleRate).ceil(), out.length);
    for (int i = math.max(from, 0); i < to; i++) {
      final double t = i / sampleRate - note.start;
      out[i] += envelopeAt(note, t) * waveAt(note.waveform, note.frequency * t);
    }
  }

  for (int i = 0; i < out.length; i++) {
    out[i] = out[i].clamp(-1.0, 1.0);
  }
  return out;
}

/// Encode [notes] as a complete mono 16-bit PCM WAV file.
///
/// **A WAV rather than raw samples because the thing on the other end is a media
/// player, not a synthesiser.** The platform audio players Flutter can reach
/// decode container formats; none of them accepts a bare buffer of floats. WAV is
/// the cheapest container that exists — a 44-byte header and the samples
/// verbatim, no compression, nothing to go wrong — and a half-second cue at CD
/// rate is about 44kB, built once and cached ([SoundEngine]).
///
/// 16-bit signed little-endian, the universally supported PCM format.
Uint8List encodeWav(List<ToneNote> notes, {int sampleRate = kSampleRate}) {
  final Float64List samples = renderSamples(notes, sampleRate: sampleRate);

  const int channels = 1;
  const int bitsPerSample = 16;
  const int headerBytes = 44;
  final int dataBytes = samples.length * 2;
  final int byteRate = sampleRate * channels * bitsPerSample ~/ 8;

  final ByteData out = ByteData(headerBytes + dataBytes);
  // **The mixed endianness below is the format, not a slip.** WAV's four-byte
  // tags are ASCII, so their bytes must land in reading order — big-endian, which
  // is `ByteData`'s default and therefore written bare. Every *number* in the
  // header is little-endian, and says so explicitly.
  //
  // RIFF chunk descriptor.
  out.setUint32(0, 0x52494646); // "RIFF"
  out.setUint32(4, 36 + dataBytes, Endian.little); // size of everything after
  out.setUint32(8, 0x57415645); // "WAVE"
  // "fmt " sub-chunk.
  out.setUint32(12, 0x666D7420); // "fmt "
  out.setUint32(16, 16, Endian.little); // PCM header length
  out.setUint16(20, 1, Endian.little); // format 1 = uncompressed PCM
  out.setUint16(22, channels, Endian.little);
  out.setUint32(24, sampleRate, Endian.little);
  out.setUint32(28, byteRate, Endian.little);
  out.setUint16(
    32,
    channels * bitsPerSample ~/ 8,
    Endian.little,
  ); // block align
  out.setUint16(34, bitsPerSample, Endian.little);
  // "data" sub-chunk.
  out.setUint32(36, 0x64617461); // "data"
  out.setUint32(40, dataBytes, Endian.little);

  for (int i = 0; i < samples.length; i++) {
    // 32767, not 32768: the positive side of a signed 16-bit range stops one
    // short, and scaling by 32768 would wrap a full-scale +1.0 to negative.
    out.setInt16(
      headerBytes + i * 2,
      (samples[i] * 32767).round().clamp(-32768, 32767),
      Endian.little,
    );
  }
  return out.buffer.asUint8List();
}
