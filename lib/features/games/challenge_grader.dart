/// The rules of Today's Challenge, with no widget in sight — a port of the
/// grading half of the prototype's `revealChallenge` (`index.html:916-949`).
///
/// **Separated from the screen on purpose.** This is the one part of the game a
/// test can pin exactly (the item's Done-when is "a unit test on the grader"),
/// and it is also the part that is easy to get subtly wrong: the game scores a
/// child on *two different notions of correct at once* — see [ChallengeGrade].
/// Keeping it here means the screen only has to render a [ChallengeGrade], and
/// the arithmetic is checked against the prototype without pumping a frame.
library;

import 'package:flutter/foundation.dart';
import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/data/models/asteroid.dart';

/// How a finished round of Today's Challenge scored.
///
/// **The two notions of "correct" are not the same number, and that is the
/// prototype's design, not a bug to tidy.** `revealChallenge` grades the same
/// ranking twice:
///
///  * [accuracy] is **pairwise concordance** — of the 6 ordered pairs in a
///    4-card ranking, how many did the child put in the right relative order
///    (`index.html:920-925`). It is forgiving: it rewards "roughly right".
///  * [exactlyCorrect] is **exact position** — how many cards landed on their
///    true rank (`index.html:940`). It is strict.
///
/// They disagree constantly. Swap the middle two of four and the child keeps
/// 5 of 6 pairs (83%, "🎯 Amazing!") while only 2 cards sit in their exact
/// slot — so the banner cheers and the score is 30, not 60. Collapsing the two
/// into one measure would change scores for real play, which is why both are
/// computed and both are on this class.
@immutable
class ChallengeGrade {
  const ChallengeGrade({
    required this.truthRank,
    required this.accuracy,
    required this.exactlyCorrect,
    required this.gain,
  });

  /// The true rank of each card, indexed by its position in the card list:
  /// `truthRank[i] == 0` means card `i` is the most powerful of the four
  /// (`truthRank` in `index.html:918-919`). Zero-based; the card shows
  /// `truthRank[i] + 1`.
  final List<int> truthRank;

  /// Pairwise concordance as a whole percentage (`acc`, `index.html:926`) — the
  /// number the banner says and the only input to the perfect-order bonus.
  final int accuracy;

  /// How many cards the child placed in their exact true position
  /// (`correctCount`, `index.html:940`) — the per-card ✓/✗ marks, and 15 points
  /// each.
  final int exactlyCorrect;

  /// Points awarded: `exactlyCorrect * 15`, plus **40** for a flawless order
  /// (`index.html:941`). A perfect round is therefore `4 * 15 + 40 = 100`.
  final int gain;

  /// Whether the round reads as a win — the prototype's one threshold for the
  /// happy-vs-sad cue and the green-vs-red banner (`acc >= 60`,
  /// `index.html:939,944`). Deliberately generous: guessing two pairs right out
  /// of six already earns encouragement rather than a red banner
  /// (`CLAUDE.md:70`, wrong answers are never harsh).
  bool get isWin => accuracy >= 60;

  /// The banner shown under the grid (`index.html:944-945`), e.g.
  /// `🎯 Amazing! — 83% right · +30 ⭐`. Three tiers of praise, none of which is
  /// a telling-off: the bottom one is "Good try — keep going!".
  String get banner {
    final String praise = accuracy >= 80
        ? '🎯 Amazing!'
        : accuracy >= 60
        ? '✓ Nice job!'
        : 'Good try — keep going!';
    return '$praise — $accuracy% right · +$gain ⭐';
  }
}

/// The card indices ordered strongest [power] first — the answer the child is
/// trying to reproduce (`truthOrder`, `index.html:917`).
///
/// **Ties break by card order, which is what makes this deterministic.** The
/// prototype sorts with `danger(b) - danger(a)`, and V8's `Array#sort` has been
/// stable since ES2019, so two equally-powerful rocks keep their original
/// order. Dart's [List.sort] promises no such thing, so the tiebreak is written
/// out rather than assumed.
///
/// It is, today, redundant at a challenge's size: [List.sort] insertion-sorts
/// up to 32 elements and *is* stable there (probed: stable at 32, not at 40), so
/// a 4-card board would tie-break by position anyway. Keeping the comparator
/// explicit means the guarantee is this function's, not an undocumented
/// threshold's — and the test that pins it uses a 40-card board for exactly that
/// reason, because at 4 the assertion cannot fail.
///
/// Ranks on the unrounded [power] rather than [powerStars], exactly as the
/// prototype does: the stars are rounded for display and would tie rocks the
/// real score separates.
List<int> challengeTruthOrder(List<Asteroid> cards) {
  final List<int> order = List<int>.generate(cards.length, (int i) => i);
  order.sort((int a, int b) {
    final int byPower = power(cards[b]).compareTo(power(cards[a]));
    return byPower != 0 ? byPower : a.compareTo(b);
  });
  return order;
}

/// Grade a finished ranking: [picks] is the card indices in the order the child
/// tapped them, strongest-first, and [cards] is the round's four animals.
///
/// Only ever called on a *complete* ranking — the "Reveal the truth" button
/// only appears once every card is placed (`index.html:910`), which is also why
/// the prototype can divide by the pair count without checking it.
ChallengeGrade gradeChallenge({
  required List<Asteroid> cards,
  required List<int> picks,
}) {
  assert(
    picks.length == cards.length,
    'a round is only graded once every card is ranked (index.html:909-911)',
  );

  final List<int> order = challengeTruthOrder(cards);
  final List<int> truthRank = List<int>.filled(cards.length, 0);
  for (int position = 0; position < order.length; position++) {
    truthRank[order[position]] = position;
  }

  // Pairwise concordance over the child's ranking (`index.html:922-925`): every
  // pair the child put in the right relative order counts, however far the
  // cards are from their exact slots.
  int concordant = 0;
  int pairs = 0;
  for (int i = 0; i < picks.length; i++) {
    for (int j = i + 1; j < picks.length; j++) {
      pairs++;
      if (truthRank[picks[i]] < truthRank[picks[j]]) concordant++;
    }
  }
  // `pairs` is 6 for every real round (4 cards); the guard is the divide-by-zero
  // the prototype's `Math.round(0/0)` would answer `NaN` to, kept unreachable
  // by the assert above rather than relied on.
  final int accuracy = pairs == 0 ? 0 : (concordant / pairs * 100).round();

  int exactlyCorrect = 0;
  for (int i = 0; i < cards.length; i++) {
    if (picks.indexOf(i) == truthRank[i]) exactlyCorrect++;
  }

  return ChallengeGrade(
    truthRank: truthRank,
    accuracy: accuracy,
    exactlyCorrect: exactlyCorrect,
    gain: exactlyCorrect * 15 + (accuracy == 100 ? 40 : 0),
  );
}
