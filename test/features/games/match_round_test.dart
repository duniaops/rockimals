import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/data/fallback_asteroids.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/features/games/match_round.dart';

/// The deal behind Animal Match (`specs/04`, game 4) — `index.html:1095-1096`.
///
/// **The option set is the whole risk here.** This deal has no retry loop to
/// hang, but it has three set properties a child would feel immediately if they
/// broke: the right answer must be present (or the round is unwinnable), it must
/// be present *once* (or a duplicate gives the game away), and the distractors
/// must differ from each other. None of those are visible in a single deal, so
/// the tests sweep many deals over a seeded [Random] rather than asserting one.
void main() {
  group('dealMatchRound', () {
    test('offers three species: the answer plus two distinct others', () {
      final Random random = Random(7);

      // 200 deals over the real fallback sky — enough to reach every rung the
      // sample data covers, and to catch a set bug that only shows for some
      // answers (the top and bottom rungs have a different neighbourhood of
      // distractors than the middle ones).
      for (int i = 0; i < 200; i++) {
        final MatchRound round = dealMatchRound(kFallbackAsteroids, random);

        expect(round.options, hasLength(kMatchOptions));
        // Present exactly once — a duplicated answer would let a child pick the
        // species they see twice.
        expect(
          round.options.where(round.isCorrect),
          hasLength(1),
          reason: 'the answer must be offered exactly once',
        );
        // All three distinct: two identical distractors would waste a button
        // and shorten the guess to a coin flip.
        expect(
          round.options.map((Animal a) => a.species).toSet(),
          hasLength(kMatchOptions),
        );
        // Every option is a real rung, not something invented for the round.
        for (final Animal option in round.options) {
          expect(kAnimals, contains(option));
        }
      }
    });

    test('the answer is the ladder\'s, derived from the rock itself', () {
      final Random random = Random(11);

      for (int i = 0; i < 50; i++) {
        final MatchRound round = dealMatchRound(kFallbackAsteroids, random);

        // The round holds the rock and asks the same ladder every other screen
        // asks, so the quiz can never disagree with the animal card.
        expect(round.answer, same(animalFor(round.rock)));
        expect(round.isCorrect(round.answer), isTrue);
      }
    });

    test('does not park the answer in a fixed slot', () {
      final Random random = Random(3);
      final Set<int> answerSlots = <int>{};

      for (int i = 0; i < 60; i++) {
        final MatchRound round = dealMatchRound(kFallbackAsteroids, random);
        answerSlots.add(round.options.indexWhere(round.isCorrect));
      }

      // The prototype shuffles *after* prepending the answer
      // (`shuffle([an, ...])`, `index.html:1096`); dropping that second shuffle
      // would pin the answer to slot 0 and a child would win 8/8 by tapping the
      // top button every time.
      expect(answerSlots, <int>{0, 1, 2});
    });

    test('draws its rock from the pool', () {
      final Random random = Random(5);

      for (int i = 0; i < 30; i++) {
        expect(
          kFallbackAsteroids,
          contains(dealMatchRound(kFallbackAsteroids, random).rock),
        );
      }
    });

    test('can ask about a sky of one', () {
      // The narrowest legal pool: the repository never yields fewer than six,
      // but the deal must not assume variety it is not promised, and the
      // distractors come from the ladder rather than the sky so a one-rock sky
      // still makes a real question.
      final List<Asteroid> sky = <Asteroid>[kFallbackAsteroids.first];
      final MatchRound round = dealMatchRound(sky, Random(1));

      expect(round.rock, same(sky.single));
      expect(round.options.where(round.isCorrect), hasLength(1));
    });

    test('the options list cannot be mutated by a caller', () {
      final MatchRound round = dealMatchRound(kFallbackAsteroids, Random(2));

      // The board renders straight off this list; a stray `sort` in a widget
      // would reorder the buttons under a child's finger.
      expect(() => round.options.add(kAnimals.first), throwsUnsupportedError);
    });
  });

  group('kMatchRounds', () {
    test('is the prototype\'s eight', () {
      // `SIZE_ROUNDS` (`index.html:1087`) — it is both the run length and the
      // perfect score, so a drift here changes the Perfect Match badge too.
      expect(kMatchRounds, 8);
      expect(kMatchOptions, 3);
    });
  });
}
