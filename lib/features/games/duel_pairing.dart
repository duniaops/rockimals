/// The rules of Power Duel that are not a widget — how a round's two animals
/// are chosen, and which of them wins. A port of the dealing half of the
/// prototype's `duelRound` (`index.html:1037`) and its winner test
/// (`index.html:1048`).
///
/// **Separated from the screen for the same reason the challenge's grader is.**
/// The deal is a *retry loop with a give-up count* — the one part of this game
/// that is easy to port subtly wrong (an unbounded loop hangs the app on a sky
/// of near-identical rocks) and the one part a test can pin without pumping a
/// frame. The screen below only renders a [DuelPair].
library;

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/data/models/asteroid.dart';

/// The two animals of one Power Duel round.
@immutable
class DuelPair {
  const DuelPair({required this.a, required this.b});

  /// The left-hand animal (the prototype's card `A`).
  final Asteroid a;

  /// The right-hand animal (card `B`).
  final Asteroid b;

  /// Whether the left-hand animal is the more powerful of the two —
  /// `danger(a) >= danger(b) ? 'A' : 'B'` (`index.html:1048`).
  ///
  /// **Ties go to A, and that asymmetry is deliberate in the prototype**: with
  /// `>=` there is always exactly one winning card, so a tie can never be graded
  /// as two wrong answers. The deal below tries hard to avoid ties reaching a
  /// child at all (see [dealDuelPair]); this is what happens when it cannot.
  ///
  /// Compared on the **unrounded** [power], not on the `powerStars` the cards
  /// show, exactly as the prototype does. Two rocks can therefore display the
  /// same star count and still have a winner — which is why the deal separates
  /// them by a margin rather than trusting the display.
  bool get winnerIsA => power(a) >= power(b);

  /// The winning animal.
  Asteroid get winner => winnerIsA ? a : b;
}

/// The smallest power gap the deal will settle for
/// (`Math.abs(danger(a)-danger(b))<0.6`, `index.html:1037`).
///
/// It is a fairness rule, not a cosmetic one: below this the two animals can
/// round to the same displayed `powerStars`, and the game would be asking a
/// child to pick between two cards that look identical.
const double kDuelMinPowerGap = 0.6;

/// How many pairs the deal will try before accepting whatever it last drew
/// (`t<50`, `index.html:1037`).
///
/// **The give-up is the load-bearing half of this rule.** A sky where no two
/// rocks are [kDuelMinPowerGap] apart is rare but perfectly possible — and
/// without the cap the loop would spin forever with the UI thread in it, which
/// is a frozen app rather than a slightly unfair round.
const int kDuelMaxDealAttempts = 50;

/// Draw one round's pair from [pool] (`index.html:1037`).
///
/// Both animals are drawn independently at random and redrawn while they are
/// the same rock **or** closer than [kDuelMinPowerGap] in [power], up to
/// [kDuelMaxDealAttempts] tries; after that the last draw stands, whatever it
/// is. So on a normal sky the child always gets a clearly-decidable pair, and on
/// a pathological one they get *a* pair rather than a hang.
///
/// [pool] is the whole sky (`asteroids`), not today's list — the prototype duels
/// across the full window (`rand(asteroids)`), which is also the only pool with
/// enough rocks for the margin rule to be satisfiable. It must not be empty; the
/// repository never yields fewer than six (plan decision 10).
DuelPair dealDuelPair(List<Asteroid> pool, Random random) {
  assert(pool.isNotEmpty, 'a duel needs a sky to draw from');
  late Asteroid a;
  late Asteroid b;
  int attempts = 0;
  do {
    a = pool[random.nextInt(pool.length)];
    b = pool[random.nextInt(pool.length)];
    attempts++;
  } while ((identical(a, b) ||
          (power(a) - power(b)).abs() < kDuelMinPowerGap) &&
      attempts < kDuelMaxDealAttempts);
  return DuelPair(a: a, b: b);
}
