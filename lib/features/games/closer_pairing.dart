/// The rules of Closer or Farther that are not a widget — how a round's anchor
/// and challenger are chosen, and which way the answer falls. A port of the
/// dealing half of the prototype's `closerRound` (`index.html:1063`) and its
/// comparison (`index.html:1075`).
///
/// **Separated from the screen for the same reason [dealDuelPair] is.** The deal
/// is a *retry loop with a give-up count* — the one part of this game that is
/// easy to port subtly wrong (an unbounded loop hangs the app on a sky of rocks
/// all flying at the same distance) and the one part a test can pin without
/// pumping a frame. The screen next door only renders a [CloserRound].
library;

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:rockimals/data/models/asteroid.dart';

/// The smallest distance gap the deal will settle for, in lunar distances
/// (`Math.abs(ch.missLunar-closerAnchor.missLunar)<0.05`, `index.html:1063`).
///
/// It is a fairness rule, not a cosmetic one: 0.05 of the way to the Moon is
/// finer than `distLabel` can even say (it rounds to whole percent below 1×), so
/// below this gap the two animals can print the *same distance string* and the
/// game would be asking a child to guess a coin flip it has already told them is
/// a tie.
const double kCloserMinLunarGap = 0.05;

/// How many challengers the deal will try before accepting whatever it last drew
/// (`t<60`, `index.html:1063`).
///
/// **The give-up is the load-bearing half of this rule.** A sky where nothing is
/// [kCloserMinLunarGap] away from the anchor is rare but perfectly possible — a
/// tight cluster of rocks on one pass — and without the cap the loop would spin
/// forever with the UI thread in it, which is a frozen app rather than a
/// slightly unfair round.
const int kCloserMaxDealAttempts = 60;

/// One round of Closer or Farther: the [anchor] the child already knows the
/// distance of, and the [challenger] they are guessing about.
///
/// **The two roles are not interchangeable** (unlike the duel's two cards): the
/// anchor's distance is shown and the challenger's is the answer. A win promotes
/// the challenger to anchor for the next round (`closerAnchor=ch`,
/// `index.html:1079`), which is what makes this a chain rather than a series of
/// unrelated questions.
@immutable
class CloserRound {
  const CloserRound({required this.anchor, required this.challenger});

  /// The animal on the card, with its distance spelled out.
  final Asteroid anchor;

  /// The animal being guessed about; its distance stays hidden until the reveal.
  final Asteroid challenger;

  /// Whether the challenger passes nearer to Earth than the anchor —
  /// `ch.missLunar < closerAnchor.missLunar` (`index.html:1075`).
  ///
  /// Strictly `<`, so an exact tie reads as *farther*. That cannot grade a child
  /// wrong on both buttons the way the duel's tie could: the answer here is one
  /// boolean and the guess is compared to it, so exactly one of the two buttons
  /// is always right. A tie is only reachable at all when the deal gives up (see
  /// [kCloserMaxDealAttempts]).
  bool get challengerIsCloser => challenger.missLunar < anchor.missLunar;
}

/// Draw the run's opening anchor (`closerAnchor=rand(asteroids)`,
/// `index.html:1061`) — unconstrained, because there is nothing yet for it to be
/// too close to.
///
/// [pool] is the whole sky (`asteroids`), not today's list, and must not be
/// empty; the repository never yields fewer than six (plan decision 10).
Asteroid pickCloserAnchor(List<Asteroid> pool, Random random) {
  assert(pool.isNotEmpty, 'a round needs a sky to draw from');
  return pool[random.nextInt(pool.length)];
}

/// Deal a challenger against [anchor] (`index.html:1063`).
///
/// The challenger is drawn at random and redrawn while it is the anchor itself
/// **or** within [kCloserMinLunarGap] of the anchor's distance, up to
/// [kCloserMaxDealAttempts] tries; after that the last draw stands, whatever it
/// is. So on a normal sky the child always gets a question with a real answer,
/// and on a pathological one they get *a* question rather than a hang.
///
/// The identity test is the prototype's and is kept, though the gap test already
/// subsumes it for every real rock (a rock's distance from itself is 0). It only
/// earns its keep if a distance is ever `NaN`, where every comparison is false —
/// which this port makes unreachable by throwing on a malformed feed instead.
CloserRound dealCloserRound(
  List<Asteroid> pool,
  Asteroid anchor,
  Random random,
) {
  assert(pool.isNotEmpty, 'a round needs a sky to draw from');
  late Asteroid challenger;
  int attempts = 0;
  do {
    challenger = pool[random.nextInt(pool.length)];
    attempts++;
  } while ((identical(challenger, anchor) ||
          (challenger.missLunar - anchor.missLunar).abs() <
              kCloserMinLunarGap) &&
      attempts < kCloserMaxDealAttempts);
  return CloserRound(anchor: anchor, challenger: challenger);
}
