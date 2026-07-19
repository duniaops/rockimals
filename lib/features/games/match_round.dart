/// The rules of Animal Match that are not a widget — which rock a round asks
/// about and which three species it offers. A port of the dealing half of the
/// prototype's `sizeRound` (`index.html:1095-1096`).
///
/// **Separated from the screen for the same reason [dealDuelPair] and
/// [dealCloserRound] are**, though this deal has no retry loop: what is easy to
/// get subtly wrong here is the *option set*. The correct species must be in it
/// exactly once and the two distractors must differ from it and from each other,
/// or a round is unanswerable (no right button) or trivially answerable (a
/// duplicate names the answer). Those are set properties a plain test can pin
/// over many deals without pumping a single frame; the screen next door only
/// renders a [MatchRound].
library;

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/data/models/asteroid.dart';

/// How many questions one run asks (`SIZE_ROUNDS`, `index.html:1087`).
///
/// It is also the perfect score: a run of exactly this many correct answers is
/// what raises `perfect` and unlocks the Perfect Match badge.
const int kMatchRounds = 8;

/// How many species a round offers — the correct one plus two others
/// (`shuffle(ANIMALS.filter(…)).slice(0,2)`, `index.html:1096`).
const int kMatchOptions = 3;

/// One question of Animal Match: a mystery [rock] described only by its width,
/// and the three species [options] the child chooses between.
///
/// **The rock's identity is the hidden truth here** (the shape Closer or Farther
/// also has): its diameter is on screen, its animal is not. So the round holds
/// the asteroid rather than a pre-computed answer — [answer] is derived from the
/// same ladder the rest of the app uses, and nothing can drift out of step with
/// it.
@immutable
class MatchRound {
  const MatchRound({required this.rock, required this.options});

  /// The asteroid behind the "❓" — only `diaMax` is shown until the reveal.
  final Asteroid rock;

  /// The three species on offer, already shuffled. The correct one is somewhere
  /// among them; nothing in the order says where.
  final List<Animal> options;

  /// The species the rock really is (`animalFor(a)`, `index.html:1095`).
  Animal get answer => animalFor(rock);

  /// Whether [option] is the right answer.
  ///
  /// Compared by `species`, as the prototype does (`o.species===correct`),
  /// rather than by identity: the ladder's species names are unique, so the two
  /// tests agree, and comparing the value keeps this honest if an option ever
  /// arrives from anywhere but [kAnimals].
  bool isCorrect(Animal option) => option.species == answer.species;
}

/// Deal one round from [pool] (`index.html:1095-1096`).
///
/// The rock is drawn from the whole sky with no memory of earlier rounds — the
/// prototype's `rand(asteroids)` — so a run of 8 can legitimately ask about the
/// same rock twice. That is not a bug to fix here: on the offline sample sky of
/// 14 it is a real possibility, and each showing is still a fair question.
///
/// The two distractors are drawn **without replacement** from the ladder minus
/// the correct rung, so they always differ from the answer and from each other.
MatchRound dealMatchRound(List<Asteroid> pool, Random random) {
  assert(pool.isNotEmpty, 'a round needs a sky to draw from');
  final Asteroid rock = pool[random.nextInt(pool.length)];
  final Animal answer = animalFor(rock);

  final List<Animal> others =
      kAnimals.where((Animal a) => a.species != answer.species).toList()
        ..shuffle(random);

  final List<Animal> options = <Animal>[
    answer,
    ...others.take(kMatchOptions - 1),
    // Shuffled again *after* the correct one is added, or it would always be
    // the first button (`shuffle([an, ...])`, `index.html:1096`).
  ]..shuffle(random);

  return MatchRound(rock: rock, options: List<Animal>.unmodifiable(options));
}
