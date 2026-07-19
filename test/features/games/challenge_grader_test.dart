import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/features/games/challenge_grader.dart';

/// The rules of Today's Challenge (`specs/04`, game 1) — the item's Done-when is
/// "a unit test on the grader asserts a perfect order scores 60+40, a reversed
/// order scores 0, and one swap scores as the prototype does".
///
/// **The scores below are not hand-reasoned, they are the prototype's own
/// output.** `index.html`'s `danger()` and the grading body of
/// `revealChallenge()` were sliced out by line range and `eval`-ed over the four
/// fixtures here, the way this plan's FALLBACK / size-ladder / naming items each
/// verified their tables. The four rocks are built with power values far apart
/// so the true order is unambiguous, and the expected accuracy/points are what
/// the prototype computes for each permutation.
void main() {
  // Four animals with deliberately separated power, weakest to strongest by
  // construction: bigger, closer and faster each score higher. Listed here in a
  // *scrambled* order on purpose — if the grader ever confused "card index"
  // with "true rank" a list already in rank order would hide it.
  final Asteroid strongest = _rock(
    name: '2020 AAA',
    diaMax: 3000,
    missLunar: 0.3,
    velKps: 30,
  );
  final Asteroid strong = _rock(
    name: '2020 BBB',
    diaMax: 500,
    missLunar: 2,
    velKps: 20,
  );
  final Asteroid weak = _rock(
    name: '2020 CCC',
    diaMax: 60,
    missLunar: 12,
    velKps: 12,
  );
  final Asteroid weakest = _rock(
    name: '2020 DDD',
    diaMax: 5,
    missLunar: 40,
    velKps: 6,
  );

  // Card order as dealt: indices 0..3 are strong, weakest, strongest, weak.
  final List<Asteroid> cards = <Asteroid>[strong, weakest, strongest, weak];
  // So the true ranking, strongest first, is cards 2, 0, 3, 1.
  const List<int> perfect = <int>[2, 0, 3, 1];

  group('challengeTruthOrder', () {
    test('orders card indices strongest power first', () {
      expect(challengeTruthOrder(cards), perfect);
      // Guard the fixture itself: the whole suite is meaningless if these four
      // are not actually separated in power.
      expect(power(strongest), greaterThan(power(strong)));
      expect(power(strong), greaterThan(power(weak)));
      expect(power(weak), greaterThan(power(weakest)));
    });

    test(
      'ties break by card order, so equal-power rocks keep a stable truth',
      () {
        // Two identical rocks, ranked either way round: the tie must resolve by
        // position, so the same four cards always reveal the same "truth" rather
        // than one that can change between runs of the same daily set.
        final Asteroid twinA = _rock(
          name: '2020 EEE',
          diaMax: 100,
          missLunar: 5,
          velKps: 15,
        );
        final Asteroid twinB = _rock(
          name: '2020 FFF',
          diaMax: 100,
          missLunar: 5,
          velKps: 15,
        );
        expect(power(twinA), power(twinB));

        expect(
          challengeTruthOrder(<Asteroid>[strongest, twinA, twinB, weakest]),
          <int>[0, 1, 2, 3],
        );
        expect(
          challengeTruthOrder(<Asteroid>[strongest, twinB, twinA, weakest]),
          <int>[0, 1, 2, 3],
        );
      },
    );

    test('ties still break by card order past the size where Dart stops '
        'sorting stably', () {
      // **The four-card case above cannot fail.** Dart's `List.sort` insertion-
      // sorts up to 32 elements, which *is* stable, so a challenge-sized board
      // resolves ties in card order whether or not the comparator says to —
      // verified by probe (stable at n=32, not at n=40). Dropping the tiebreak
      // therefore breaks no test up there, which makes the guarantee look
      // pinned when it is only being borrowed from an undocumented threshold.
      //
      // So the contract is asserted where the sort genuinely reorders: 40
      // equal-power rocks must still come back in card order.
      final List<Asteroid> tied = List<Asteroid>.generate(
        40,
        (int i) => _rock(name: 'tie $i', diaMax: 100, missLunar: 5, velKps: 15),
      );
      expect(
        challengeTruthOrder(tied),
        List<int>.generate(40, (int i) => i),
        reason: 'equal power must resolve by card order at any board size',
      );
    });
  });

  group('gradeChallenge', () {
    test(
      'a perfect order is 100% — 4 exact placements (60) plus the 40 bonus',
      () {
        final ChallengeGrade grade = gradeChallenge(
          cards: cards,
          picks: perfect,
        );

        expect(grade.accuracy, 100);
        expect(grade.exactlyCorrect, 4);
        // The Done-when's "60+40": `4 * 15` for the placements, `+40` for the
        // flawless order (`index.html:941`).
        expect(grade.gain, 100);
        expect(grade.isWin, isTrue);
        expect(grade.banner, '🎯 Amazing! — 100% right · +100 ⭐');
        // Truth rank is per *card*, not per pick: card 0 (strong) is really #2.
        expect(grade.truthRank, <int>[1, 3, 0, 2]);
      },
    );

    test('a reversed order scores 0 — no pair concordant, no card in place', () {
      final ChallengeGrade grade = gradeChallenge(
        cards: cards,
        picks: perfect.reversed.toList(),
      );

      expect(grade.accuracy, 0);
      // With an even number of cards a full reversal leaves no fixed point, so
      // the two measures agree here — the one case where they do.
      expect(grade.exactlyCorrect, 0);
      expect(grade.gain, 0);
      expect(grade.isWin, isFalse);
      // Even a total miss is encouragement, never a telling-off (`CLAUDE.md:70`).
      expect(grade.banner, 'Good try — keep going! — 0% right · +0 ⭐');
    });

    test('one adjacent swap: 5 of 6 pairs right (83%) but only 2 cards in '
        'place, so 30 points and no bonus', () {
      // Swap the middle two of the perfect order — the case that separates the
      // game's two notions of correct, and the one an agent is most likely to
      // port wrong by scoring the banner off the placements.
      final ChallengeGrade grade = gradeChallenge(
        cards: cards,
        picks: <int>[2, 3, 0, 1],
      );

      expect(grade.accuracy, 83);
      expect(grade.exactlyCorrect, 2);
      expect(grade.gain, 30);
      // 83% is "Amazing!" — and still no 40-point bonus, because that needs a
      // flawless 100.
      expect(grade.isWin, isTrue);
      expect(grade.banner, '🎯 Amazing! — 83% right · +30 ⭐');
    });

    test('demoting the strongest two places: 67% is a "Nice job!" win worth '
        'only one placement', () {
      // 4 of 6 pairs survive, but just one card lands on its exact slot — the
      // widest the two measures spread on a 4-card board, and the clearest
      // demonstration that the banner and the points are not the same grade.
      final ChallengeGrade grade = gradeChallenge(
        cards: cards,
        picks: <int>[0, 3, 2, 1],
      );

      expect(grade.accuracy, 67);
      expect(grade.exactlyCorrect, 1);
      expect(grade.gain, 15);
      expect(grade.banner, '✓ Nice job! — 67% right · +15 ⭐');
    });

    test('50% falls just under the win line and stays encouraging', () {
      // 3 of 6 pairs concordant — the threshold is `>= 60`, so this is the
      // sad-cue side of it (`index.html:939`).
      final ChallengeGrade grade = gradeChallenge(
        cards: cards,
        picks: <int>[0, 3, 1, 2],
      );

      expect(grade.accuracy, 50);
      expect(grade.isWin, isFalse);
      expect(grade.banner, startsWith('Good try — keep going!'));
    });

    test('the exact banner tiers, at their boundaries', () {
      // The three praise tiers are cut at 80 and 60, and 6 pairs can only land
      // on 0/17/33/50/67/83/100 — so 83 is the lowest "Amazing" a real round
      // can reach and 67 the lowest "Nice job". Pinned through the public
      // surface so a reworded tier fails here rather than in a child's face.
      const List<(int, String)> expected = <(int, String)>[
        (100, '🎯 Amazing!'),
        (83, '🎯 Amazing!'),
        (67, '✓ Nice job!'),
        (50, 'Good try — keep going!'),
        (0, 'Good try — keep going!'),
      ];
      for (final (int accuracy, String praise) in expected) {
        final ChallengeGrade grade = ChallengeGrade(
          truthRank: const <int>[0, 1, 2, 3],
          accuracy: accuracy,
          exactlyCorrect: 0,
          gain: 0,
        );
        expect(grade.banner, startsWith(praise), reason: 'at $accuracy%');
      }
    });

    test('grading an unfinished ranking asserts', () {
      // The Reveal button only exists once every card is placed
      // (`index.html:909-911`); an incomplete ranking would divide by a pair
      // count the prototype never has to guard.
      expect(
        () => gradeChallenge(cards: cards, picks: <int>[2, 0]),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}

/// A minimal rock — only the four fields [power] and the card copy read matter;
/// the rest are plausible filler.
Asteroid _rock({
  required String name,
  required double diaMax,
  required double missLunar,
  required double velKps,
  bool hazardous = false,
}) {
  return Asteroid(
    name: name,
    diaMax: diaMax,
    diaMin: diaMax / 2,
    hazardous: hazardous,
    missLunar: missLunar,
    missKm: missLunar * 384400,
    velKps: velKps,
    mag: 20,
    jpl: 'https://ssd.jpl.nasa.gov/tools/sbdb_lookup.html',
    date: '2026-07-16',
  );
}
