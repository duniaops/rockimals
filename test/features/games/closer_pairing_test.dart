import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/features/games/closer_pairing.dart';

/// The rules of Closer or Farther with no widget in sight (`specs/04`, game 3) —
/// the deal's retry loop and the closer/farther comparison.
///
/// **The give-up count is the thing this suite exists for**, exactly as in
/// `duel_pairing_test.dart`: a deal that loops until it finds a well-separated
/// challenger is correct on any real sky and hangs the UI thread forever on one
/// where every rock flies at the same distance. That is rare but reachable — a
/// tight cluster on one pass — and it fails as a *hang*, not a failure, so the
/// cap is asserted by counting draws rather than by hoping a test times out.
void main() {
  group('dealCloserRound', () {
    test('draws a different animal, separated by the distance gap', () {
      // A spread of distances, so the gap rule is satisfiable and the loop
      // should find a challenger almost immediately. Repeated, because the deal
      // is random: one pass proves nothing about a rule that only bites on some
      // draws.
      final List<Asteroid> sky = <Asteroid>[
        _rock('2020 AAA', missLunar: 0.2),
        _rock('2020 BBB', missLunar: 1.4),
        _rock('2020 CCC', missLunar: 9),
        _rock('2020 DDD', missLunar: 40),
      ];
      final Random random = Random(11);

      for (int i = 0; i < 200; i++) {
        final Asteroid anchor = pickCloserAnchor(sky, random);
        final CloserRound round = dealCloserRound(sky, anchor, random);

        expect(
          identical(round.anchor, round.challenger),
          isFalse,
          reason: 'an animal cannot be closer or farther than itself',
        );
        expect(
          (round.challenger.missLunar - round.anchor.missLunar).abs(),
          greaterThanOrEqualTo(kCloserMinLunarGap),
          reason:
              'two distances a child cannot tell apart is not a fair '
              'question',
        );
      }
    });

    test('gives up after 60 attempts on a sky it cannot satisfy, rather than '
        'looping forever', () {
      // Every rock at the same distance: no draw can ever clear the gap, so the
      // loop can only end by hitting its cap.
      final List<Asteroid> flatSky = <Asteroid>[
        _rock('2020 AAA', missLunar: 5),
        _rock('2020 BBB', missLunar: 5),
        _rock('2020 CCC', missLunar: 5),
      ];
      final _CountingRandom random = _CountingRandom(Random(1));

      final CloserRound round = dealCloserRound(flatSky, flatSky.first, random);

      // One draw per attempt, and not one attempt more than the cap.
      expect(random.draws, kCloserMaxDealAttempts);
      // The child still gets a question — a poor one beats a frozen app.
      expect(flatSky, contains(round.challenger));
    });

    test(
      'accepts a challenger exactly at the gap, and redraws just inside it',
      () {
        // 0.05 apart is acceptable (the rule is strictly `<`); 0.049 is not. With
        // only these two rocks the deal must take the far one every time or spin
        // out its cap on the near one.
        final Asteroid anchor = _rock('2020 AAA', missLunar: 1);
        final Asteroid atGap = _rock('2020 BBB', missLunar: 1.05);
        final Random random = Random(3);

        for (int i = 0; i < 20; i++) {
          expect(
            dealCloserRound(
              <Asteroid>[anchor, atGap],
              anchor,
              random,
            ).challenger,
            same(atGap),
          );
        }

        final Asteroid insideGap = _rock('2020 CCC', missLunar: 1.049);
        final _CountingRandom counting = _CountingRandom(Random(3));
        dealCloserRound(<Asteroid>[anchor, insideGap], anchor, counting);
        // It never settled: it exhausted the cap looking for something better.
        expect(counting.draws, kCloserMaxDealAttempts);
      },
    );
  });

  group('challengerIsCloser', () {
    test('is true only when the challenger passes nearer to Earth', () {
      final Asteroid near = _rock('2020 AAA', missLunar: 0.4);
      final Asteroid far = _rock('2020 BBB', missLunar: 12);

      expect(
        CloserRound(anchor: far, challenger: near).challengerIsCloser,
        isTrue,
      );
      expect(
        CloserRound(anchor: near, challenger: far).challengerIsCloser,
        isFalse,
      );
    });

    test('reads a dead tie as farther, and still leaves exactly one right '
        'button', () {
      // Only reachable once the deal has given up (see above). Unlike the
      // duel's tie — where `>` would have graded *both* cards wrong — the answer
      // here is one boolean compared against the guess, so a tie simply means
      // "⬆ Farther" is the right answer. A child can never be told they are
      // wrong whichever way they tapped.
      final Asteroid a = _rock('2020 AAA', missLunar: 3);
      final Asteroid b = _rock('2020 BBB', missLunar: 3);
      final CloserRound round = CloserRound(anchor: a, challenger: b);

      expect(round.challengerIsCloser, isFalse);
      // Restated as the game grades it: exactly one of the two guesses wins.
      final bool closerWins = round.challengerIsCloser;
      final bool fartherWins = !round.challengerIsCloser;
      expect(closerWins != fartherWins, isTrue);
    });
  });

  test('pickCloserAnchor draws from the pool', () {
    final List<Asteroid> sky = <Asteroid>[
      _rock('2020 AAA', missLunar: 1),
      _rock('2020 BBB', missLunar: 2),
    ];
    final Random random = Random(5);
    final Set<Asteroid> seen = <Asteroid>{};

    for (int i = 0; i < 60; i++) {
      seen.add(pickCloserAnchor(sky, random));
    }

    // Unconstrained (`rand(asteroids)`, `index.html:1061`) — there is nothing
    // yet for the opening anchor to be too close to, so every rock is eligible.
    expect(seen, hasLength(2));
  });
}

/// A [Random] that counts how many draws the deal makes, so the give-up cap is
/// asserted rather than assumed — a missing cap fails as a hang, which no
/// ordinary expectation can catch.
class _CountingRandom implements Random {
  _CountingRandom(this._inner);

  final Random _inner;
  int draws = 0;

  @override
  int nextInt(int max) {
    draws++;
    return _inner.nextInt(max);
  }

  @override
  bool nextBool() => _inner.nextBool();

  @override
  double nextDouble() => _inner.nextDouble();
}

Asteroid _rock(String name, {required double missLunar}) {
  return Asteroid(
    name: name,
    diaMax: 120,
    diaMin: 60,
    hazardous: false,
    missLunar: missLunar,
    missKm: missLunar * 384400,
    velKps: 15,
    mag: 20,
    jpl: 'https://ssd.jpl.nasa.gov/tools/sbdb_lookup.html',
    date: '2026-07-16',
  );
}
