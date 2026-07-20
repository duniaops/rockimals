/// The AnimalSystem: the single home for the size→species ladder, naming,
/// `power()`, `flybyTag()`, and the Moon-distance formatters (`CLAUDE.md:78`).
///
/// This file currently holds the size ladder, naming, power, and the flyby tag.
/// The Moon-distance formatters land here too — one module, so that "the same
/// asteroid always yields the same animal" is a property of one table rather
/// than an agreement between several.
library;

import 'dart:math' as math;

import 'package:rockimals/data/models/asteroid.dart';

/// One rung of the ladder: an asteroid's species and how it is described to a
/// child.
///
/// [max] is an **exclusive** ceiling — a rung claims an asteroid when its
/// `diaMax` is *strictly* below it, which is what puts exactly 8 m in the
/// Rabbit band rather than the Mouse one.
class Animal {
  const Animal({
    required this.max,
    required this.emoji,
    required this.species,
    required this.sizeLabel,
  });

  /// The exclusive upper bound in metres. The Whale rung is unbounded.
  final double max;

  final String emoji;

  /// The species name, as shown to a child: "Milo the Fox".
  final String species;

  /// The kid vocabulary for this size band ("car-sized" → "mountain-sized").
  ///
  /// This lives on the rung rather than in a second lookup because the
  /// prototype's `sizeLabel()` (`index.html:416-419`) is a byte-for-byte
  /// parallel of the `ANIMALS` ladder (`index.html:431-440`): same seven
  /// boundaries, same order, and every call site passes the same `diaMax` that
  /// picked the species. Two tables would only be two places for those
  /// boundaries to drift apart. The public [sizeLabel] function keeps the
  /// prototype's diameter-in, string-out signature.
  final String sizeLabel;

  @override
  String toString() => '$emoji $species (<${max}m, $sizeLabel)';
}

/// The ladder, in ascending order — a direct port of `index.html:431-440`,
/// with the labels from `index.html:416-419` folded onto their rungs.
///
/// Order is load-bearing: [animalFor] returns the first rung an asteroid fits
/// under, so sorting or reordering this list silently reassigns species.
const List<Animal> kAnimals = <Animal>[
  Animal(max: 8, emoji: '🐭', species: 'Mouse', sizeLabel: 'car-sized'),
  Animal(max: 20, emoji: '🐰', species: 'Rabbit', sizeLabel: 'bus-sized'),
  Animal(max: 50, emoji: '🦊', species: 'Fox', sizeLabel: 'house-sized'),
  Animal(max: 120, emoji: '🐯', species: 'Tiger', sizeLabel: 'plane-sized'),
  Animal(
    max: 300,
    emoji: '🐻',
    species: 'Bear',
    sizeLabel: 'football-pitch-sized',
  ),
  Animal(
    max: 800,
    emoji: '🐘',
    species: 'Elephant',
    sizeLabel: 'stadium-sized',
  ),
  Animal(
    max: 2000,
    emoji: '🦕',
    species: 'Dino',
    sizeLabel: 'skyscraper-sized',
  ),
  Animal(
    max: double.infinity,
    emoji: '🐋',
    species: 'Whale',
    sizeLabel: 'mountain-sized',
  ),
];

/// The 24 first names a critter can be given — a verbatim port of
/// `index.html:430`.
///
/// Order is load-bearing: [critter] indexes this list by `hash % length`, so
/// reordering it, or adding a 25th name, renames every animal in the sky.
///
/// **Two rocks may share an animal name, and that is accepted rather than
/// overlooked.** Decided 2026-07-19; the numbers are pinned by
/// `test/core/animals/name_collisions_test.dart` so this paragraph can fail.
///
/// A name is one of these 24 paired with a species, and the species is forced
/// by size — so two rocks in the same size band draw from 24 names, not from
/// 192. Measured over 155,520 real-format designations, two same-band rocks
/// share a name **4.18%** of the time against an ideal 4.17%: the pool is
/// *small*, not broken, so a better hash is not the fix.
///
/// From those two measured facts the rest is arithmetic rather than
/// measurement, and is flagged as such because it assumes a feed's
/// designations are unrelated to one another — true of a NeoWs window, which
/// draws rocks discovered decades apart, but not provable without live feed
/// data. A band of k rocks carries about `C(k, 2) / 24` duplicate pairs — 1.9
/// at k=10, 7.9 at k=20 — and above k=24 the pigeonhole makes a duplicate
/// certain, which *is* asserted. `specs/07-sky-tab.md:57` calls 60+ animals a
/// busy day, and real near-Earth sizes cluster into a few rungs, so on a live
/// feed duplicates are the steady state and not an unlucky day. The bundled
/// sky shows the same thing in miniature, and is the one collision anyone has
/// actually observed: `2010 WC9` and `2019 OK` are both 130 m, so both are
/// Bears, and both hash to `Bruno`.
///
/// Accepted for three reasons. **Nothing identifies a rock by its animal
/// name** — follows are keyed on the real designation, and `Store.follows`
/// already documents that the name is derived and the pool may change, so a
/// homonym points at nothing and renames break nothing. **Widening cannot
/// reach zero**: holding a busy band of 30 to even half an expected duplicate
/// needs `C(30, 2) / 0.5` ≈ 870 names, which is not a list anyone writes, and
/// every intermediate size buys a rename of every animal in the sky for a
/// collision that still happens. And **the 24 are the prototype's copy**
/// (`index.html:430`), which `CLAUDE.md:44` says to port rather than reinvent.
/// Two animals in a zoo sharing a name is also just what zoos are like.
///
/// The one place it is *not* fine is a screen showing two names at once —
/// Power Duel, Closer or Farther and Today's Challenge all can, and two
/// identical labels make their question unanswerable. That is a bug in the
/// **deal**, not in this pool, and it is fixed there: see the open plan item
/// "Reject a deal whose animals share a name".
const List<String> kNamePool = <String>[
  'Milo',
  'Bella',
  'Coco',
  'Rocky',
  'Daisy',
  'Simba',
  'Luna',
  'Buddy',
  'Ruby',
  'Zola',
  'Pip',
  'Nova',
  'Ziggy',
  'Mango',
  'Pepper',
  'Biscuit',
  'Waffle',
  'Olive',
  'Peanut',
  'Bruno',
  'Poppy',
  'Teddy',
  'Suki',
  'Gizmo',
];

/// An asteroid presented as a friendly space animal: a species from the size
/// ladder plus a first name from [kNamePool].
class Critter {
  const Critter({required this.animal, required this.first});

  /// The rung the asteroid's diameter put it on — its emoji, species, and
  /// size label all read through here rather than being copied, so the ladder
  /// stays the one table.
  final Animal animal;

  /// The first name, chosen by hashing the real designation.
  final String first;

  /// How a child is introduced to this rock: "Milo the Fox"
  /// (`index.html:444`).
  String get name => '$first the ${animal.species}';

  @override
  String toString() => '${animal.emoji} $name';
}

/// The djb2 variant the prototype seeds its names with (`index.html:442`):
/// `h = 5381; h = ((h * 33) ^ codeUnit) >>> 0`.
///
/// The `& 0xFFFFFFFF` is JavaScript's `>>> 0` written out. Dart's ints are
/// 64-bit and do not wrap to unsigned 32-bit on their own, so without the mask
/// `h` grows past 2^32 and every name after the first character diverges from
/// the prototype. Masking is enough to be bit-exact rather than merely close:
/// `h < 2^32` means `h * 33 < 2^37`, well inside both Dart's 64-bit int and the
/// 2^53 JS doubles compute it exactly in, and the XOR only touches the low 16
/// bits — so truncating to the low 32 at the end lands on the same value JS
/// reaches by truncating at each step.
///
/// Always non-negative, which is what makes `%` in [critter] safe: Dart's `%`
/// returns a non-negative remainder anyway, but a negative hash would still
/// pick a different name than JS does.
int hashStr(String s) {
  int h = 5381;
  for (final int codeUnit in s.codeUnits) {
    h = ((h * 33) ^ codeUnit) & 0xFFFFFFFF;
  }
  return h;
}

/// The animal an asteroid *is*, name and all — a port of `index.html:443-444`.
///
/// Deterministic and storage-free (`CLAUDE.md:70`): the species comes from
/// [Asteroid.diaMax] and the first name from hashing [Asteroid.name], so the
/// same rock is the same animal on every device, every launch, with nothing
/// written down. Both inputs are facts about the asteroid, which is the whole
/// trick — there is no counter, no seed, and nothing to keep in sync.
///
/// Seeded on the **real designation** deliberately: it is this app's identity
/// for a rock everywhere else too (dedupe, radar seeds, follows), so an animal
/// cannot drift away from the asteroid it belongs to.
Critter critter(Asteroid a) => Critter(
  animal: animalFor(a),
  first: kNamePool[hashStr(a.name) % kNamePool.length],
);

/// The species an asteroid is, decided by its real maximum diameter.
///
/// Deterministic and storage-free: the same rock is always the same animal
/// because [Asteroid.diaMax] is the only input.
Animal animalFor(Asteroid a) => _rungFor(a.diaMax);

/// How a child hears the size of a [m]-metre rock: "car-sized" →
/// "mountain-sized" (`index.html:416-419`).
String sizeLabel(double m) => _rungFor(m).sizeLabel;

/// How fast a child hears an asteroid travelling: a whole-number km/s value.
///
/// The compact, rounded form keeps the card, radar, detail screen, and games
/// consistent while avoiding precision that is not useful in the main flow.
String speedLabel(double kps) => '${kps.round()} km/s';

/// First-fit down the ladder, exactly as `index.html:441` scans `ANIMALS`.
///
/// The trailing return is the Whale rung again — unreachable for any real
/// diameter, since Whale's ceiling is infinite, but it is the answer for a
/// `NaN` [m], where every `<` comparison is false. The prototype has the same
/// line for the same reason.
Animal _rungFor(double m) {
  for (final Animal rung in kAnimals) {
    if (m < rung.max) return rung;
  }
  return kAnimals.last;
}

/// How impressive a space animal is: a blend of how big, how close, and how
/// fast it is, with a bump for a close flyby. A port of the prototype's
/// `danger()` (`index.html:353-359`).
///
/// The rename is a guardrail, not a preference. `CLAUDE.md:65` turns "threat"
/// into "power ⭐" — nothing in this app is allowed to tell a child an asteroid
/// is dangerous — so the word does not survive into the port, only the formula.
/// Its three terms, kept in the prototype's order and weights:
///
///  * **size** — `log10(diaMax + 1) * 3`, then weighted `× 3`. The log is what
///    lets a 16.8 km Eros and a 9 m pebble share one scale; the `+ 1` keeps a
///    sub-metre rock from going negative.
///  * **prox** — `min(6, 10 / (missLunar + 0.4))`, weighted `× 2`. The `+ 0.4`
///    stops a grazing pass dividing by ~0, and the cap of 6 means everything
///    inside ~1.27 Moons scores the same on closeness: past that point a child
///    is being asked to compare "very close" with "very close".
///  * **speed** — `velKps / 9`, unweighted.
///
/// Plus `2.2` when NASA flags the rock, which is the one place the raw
/// `hazardous` flag reaches a number a child sees.
///
/// Returns the **unrounded** score, and both forms are load-bearing: the games
/// rank animals against each other on this double (`index.html:917,1037,1048`)
/// while the cards show [powerStars]. Ranking on the rounded stars instead
/// would tie rocks the prototype separates, so this is not merely
/// `powerStars / 3`.
double power(Asteroid a) {
  final double size = _log10(a.diaMax + 1) * 3;
  final double prox = math.min(6, 10 / (a.missLunar + 0.4));
  final double speed = a.velKps / 9;
  final double pha = a.hazardous ? 2.2 : 0;
  return size * 3 + prox * 2 + speed + pha;
}

/// The "Power ⭐" a child is shown — [power] scaled up and rounded, exactly as
/// `index.html:360` does it.
///
/// The `* 3` is cosmetic: it spreads a real sky's scores across roughly 50–125
/// instead of 17–42, so two animals a child is comparing rarely tie.
///
/// Dart's [num.round] rounds half *away from zero* where JS's `Math.round`
/// rounds half *up*. They disagree only at negative halves, which [power]
/// cannot reach: every term is non-negative and `prox` is strictly positive.
int powerStars(Asteroid a) => (power(a) * 3).round();

/// `dart:math` has no `log10`, so this is JS's `Math.log10` written out.
///
/// This is the one place the port cannot promise bit-exactness: V8 implements
/// `Math.log10` directly, and dividing by [math.ln10] can land an ulp away. It
/// does not reach a child — [powerStars] rounds to an integer, so a difference
/// in the 16th digit would have to fall within an ulp of a `.5` boundary to
/// change a star, and none of the 14 sample rocks comes close. The tests assert
/// the stars exactly and the raw score to a tolerance, for this reason.
double _log10(double x) => math.log(x) / math.ln10;

/// The wave that means "close flyby", wherever the app says so.
///
/// One constant rather than eight literals because it is not decoration: it is
/// the **icon** half of `specs/06-title-polish-safety.md:23`, "never rely on
/// colour alone — pair the close-flyby colour with icon + text". Every surface
/// that tints something for a close flyby has to show this too, so a
/// colour-blind child sees the state and not just the hue. Keeping it here, next
/// to [flybyTag], is what makes "which surfaces mark a close flyby" answerable
/// by grep instead of by memory.
///
/// It is also deliberately a *greeting* and not a warning triangle
/// (`CLAUDE.md:64`).
const String kCloseFlybyGlyph = '👋';

/// How a flyby is described to a child (`index.html:445-447`).
///
/// Two values, never a raw boolean: `hazardous` is NASA's word and
/// `CLAUDE.md:64` forbids it reaching a child, so the flag is only ever read
/// *through* this tag. Nothing here is scary — the closest a rock gets to being
/// singled out is a friendly wave.
enum FlybyTag {
  /// A rock NASA flags, or one passing inside the Moon's distance.
  closeFlyby('$kCloseFlybyGlyph close flyby'),

  /// Everything else — the overwhelming majority of the sky.
  justPassing('just passing');

  const FlybyTag(this.label);

  /// The copy shown on the badge. The prototype returns this wrapped in HTML;
  /// the string is the part worth porting, and the styling belongs to whatever
  /// renders it.
  final String label;
}

/// Which of the two things a rock is doing (`index.html:445`).
///
/// `hazardous || missLunar < 1` — so a rock earns the wave either because NASA
/// flagged it *or* because it passes closer than the Moon, and the two are
/// independent of [power]: `2015 TB145` is the strongest animal in the sample
/// sky (⭐123) and is still just passing, at 1.3 Moons and unflagged.
FlybyTag flybyTag(Asteroid a) =>
    a.hazardous || a.missLunar < 1 ? FlybyTag.closeFlyby : FlybyTag.justPassing;

/// How far away a rock passes, in the only unit this app speaks: the Moon.
/// A port of `index.html:420-423`.
///
/// The Moon is not a stylistic choice, it is the guardrail (`CLAUDE.md:67-69`):
/// every distance is shown relative to it, and no raw kilometre, lunar-distance
/// or AU figure reaches a child. "384,400 km" means nothing to a six-year-old
/// and "0.07 LD" means nothing to anyone; "7% to Moon" is a thing you can
/// picture. [Asteroid.missKm] exists on the model and stays there.
///
/// Two forms, because [l] below 1 is the interesting case — most rocks that a
/// child will care about pass *inside* the Moon's orbit, where a multiplier
/// would read "0.1× Moon" and bury the drama:
///
///  * `l < 1` → `"7% to Moon"` — how far along the trip it got.
///  * `1 ≤ l < 10` → `"1.3× Moon"` — one decimal, so nearby rocks stay distinct.
///  * `l ≥ 10` → `"12× Moon"` — a decimal on a far rock is noise.
///
/// Takes the lunar distance rather than an [Asteroid] because the radar HUD
/// passes the closest approach in the sky rather than any one rock
/// (`index.html:455`), matching the prototype's signature.
String distLabel(double l) =>
    l < 1 ? '${_moonPercent(l)}% to Moon' : '${_moonMultiple(l)}× Moon';

/// The same distance as [distLabel], said in full — for the one place with room
/// for a sentence: the "How close does it pass?" heading on the animal detail
/// panel (`index.html:591`). A port of `index.html:424-426`.
///
/// Identical thresholds and identical numbers to [distLabel]; only the copy is
/// longer. The two share [_moonPercent] and [_moonMultiple] rather than
/// restating `< 1` and `< 10`, so the compact and long forms of one distance
/// cannot drift into disagreeing about it — the same argument that folded
/// `sizeLabel` onto its [Animal] rung.
String moonCompare(double l) => l < 1
    ? '${_moonPercent(l)}% of the way to the Moon'
    : "${_moonMultiple(l)}× the Moon's distance";

/// How far along the trip to the Moon, as a whole percent.
///
/// Rounds, so anything from 99.5% out to the Moon itself reads "100% to Moon" —
/// a rock at `l = 0.999` claims to have arrived. Ported as-is: it is the
/// prototype's answer, it is off by at most half a percent, and "100% to Moon"
/// for a rock that is essentially at the Moon is a fair thing to tell a child.
///
/// Dart's [num.round] breaks ties away from zero where JS's `Math.round` breaks
/// them upward. They differ only on negative halves, which a miss distance
/// cannot reach.
int _moonPercent(double l) => (l * 100).round();

/// The multiplier, with the prototype's decimal rule: one digit under 10, none
/// at or above it (`index.html:422`).
///
/// The two branches meet awkwardly and it is faithful — `9.99` renders
/// "10.0× Moon" while `10.0` renders "10× Moon", because `9.99` takes the
/// one-decimal branch and rounds up inside it. Both are true, neither is
/// misleading, and the alternative is diverging from the prototype over a
/// hundredth of a Moon.
///
/// [num.toStringAsFixed] is specified to agree with JS's `toFixed`, so the
/// decimal branch is exact rather than approximate.
String _moonMultiple(double l) =>
    l < 10 ? l.toStringAsFixed(1) : l.round().toString();
