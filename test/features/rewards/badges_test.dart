/// The badge table (`ZBADGES`, `index.html:974-984`) and the next-goal
/// derivation (`nextBadgeGoal`, `index.html:513-517`).
///
/// **These nine conditions are the whole meta-game, and every one of them is a
/// boundary.** A `>` written where the prototype has `>=` is a badge a child
/// earns one point late; the reverse is one they earn without meeting the goal.
/// Neither shows up in a play-through, and neither would ever be reported — so
/// each condition is checked at the value below its threshold, at it, and above.
///
/// The other thing pinned here is the *derivation* the plan asked for: the
/// prototype keeps its point thresholds in two tables (the badge's `ok` closure
/// and `nextBadgeGoal`'s own `tiers` array) and nothing makes them agree. Here
/// they cannot disagree, and the tests below say so by asking both questions of
/// the same numbers.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/features/rewards/badges.dart';

/// Progress with nothing achieved, overridden one field at a time so each test
/// changes exactly the number it is about.
BadgeProgress progress({
  int points = 0,
  int gamesPlayed = 0,
  int bestStreak = 0,
  int perfectRuns = 0,
  int followCount = 0,
}) => BadgeProgress(
  points: points,
  gamesPlayed: gamesPlayed,
  bestStreak: bestStreak,
  perfectRuns: perfectRuns,
  followCount: followCount,
);

AnimalBadge badge(String id) => kBadges.firstWhere((AnimalBadge b) => b.id == id);

void main() {
  group('the table', () {
    test('is the prototype\'s nine, in its order, with its ids', () {
      // Ids are persisted (`Store.badges`), so this list is on children's disks:
      // renaming one un-earns that badge for everyone who had it. Order is
      // load-bearing for the shelf and for `nextBadgeGoal`.
      expect(kBadges.map((AnimalBadge b) => b.id), <String>[
        'play',
        'mouse',
        'fox',
        'bear',
        'ele',
        'whale',
        'fire',
        'keep',
        'star',
      ]);
    });

    test('carries the prototype\'s emoji, titles, and copy verbatim', () {
      expect(
        kBadges.map((AnimalBadge b) => '${b.emoji} ${b.title} — ${b.description}'),
        <String>[
          '🚀 Lift Off — Play your first game',
          '🐭 Mouse Scout — Earn 50 points',
          '🦊 Fox Explorer — Earn 150 points',
          '🐻 Bear Ranger — Earn 300 points',
          '🐘 Elephant Expert — Earn 600 points',
          '🐋 Whale Master — Earn 1000 points',
          '🔥 On Fire — Get 5 correct in a row',
          '🐾 Zoo Keeper — Follow 3 space animals',
          '⭐ Perfect Match — Score 8/8 in Animal Match',
        ],
      );
    });

    test('has no duplicate ids', () {
      // A duplicate would make one of the two unreachable forever: the earned
      // set is keyed by id, so awarding either marks both.
      final Set<String> ids = kBadges.map((AnimalBadge b) => b.id).toSet();
      expect(ids.length, kBadges.length);
    });

    test('cannot be added to at runtime', () {
      expect(
        () => kBadges.add(badge('play')),
        throwsUnsupportedError,
        reason: 'the ladder is fixed; a tenth rung would break the shelf order',
      );
    });

    test('every badge\'s label is its emoji and title', () {
      // The Profile's next-goal line names a badge this way
      // (`'🐭 Mouse Scout'`, `index.html:514`).
      expect(badge('mouse').label, '🐭 Mouse Scout');
      expect(badge('star').label, '⭐ Perfect Match');
    });
  });

  group('the five point tiers', () {
    test('ascend, which is what makes nextBadgeGoal\'s walk correct', () {
      final List<int> goals = kBadges
          .map((AnimalBadge b) => b.pointsGoal)
          .whereType<int>()
          .toList();

      expect(goals, <int>[50, 150, 300, 600, 1000]);
      for (int i = 1; i < goals.length; i++) {
        expect(goals[i], greaterThan(goals[i - 1]));
      }
    });

    test('are exactly the five badges with a goal', () {
      final Iterable<String> tiers = kBadges
          .where((AnimalBadge b) => b.pointsGoal != null)
          .map((AnimalBadge b) => b.id);

      expect(tiers, <String>['mouse', 'fox', 'bear', 'ele', 'whale']);
    });

    test('unlock at the threshold, not a point before or after', () {
      for (final AnimalBadge tier in kBadges.where(
        (AnimalBadge b) => b.pointsGoal != null,
      )) {
        final int goal = tier.pointsGoal!;
        expect(
          tier.isEarnedBy(progress(points: goal - 1)),
          isFalse,
          reason: '${tier.title} must not unlock at ${goal - 1}',
        );
        expect(
          tier.isEarnedBy(progress(points: goal)),
          isTrue,
          reason: '${tier.title} must unlock at exactly $goal',
        );
        expect(tier.isEarnedBy(progress(points: goal + 1)), isTrue);
      }
    });

    test('describe themselves from the same number they test', () {
      // The derivation the plan asked for, stated as an assertion: one
      // threshold, three consumers. A second table could not survive this.
      for (final AnimalBadge tier in kBadges.where(
        (AnimalBadge b) => b.pointsGoal != null,
      )) {
        expect(tier.description, 'Earn ${tier.pointsGoal} points');
      }
    });
  });

  group('the four non-points conditions', () {
    test('Lift Off is the first game begun', () {
      expect(badge('play').isEarnedBy(progress()), isFalse);
      expect(badge('play').isEarnedBy(progress(gamesPlayed: 1)), isTrue);
    });

    test('On Fire is five correct in a row, not four', () {
      expect(badge('fire').isEarnedBy(progress(bestStreak: 4)), isFalse);
      expect(badge('fire').isEarnedBy(progress(bestStreak: 5)), isTrue);
    });

    test('Zoo Keeper is three follows, not two', () {
      expect(badge('keep').isEarnedBy(progress(followCount: 2)), isFalse);
      expect(badge('keep').isEarnedBy(progress(followCount: 3)), isTrue);
    });

    test('Perfect Match is one flawless run of Animal Match', () {
      expect(badge('star').isEarnedBy(progress()), isFalse);
      expect(badge('star').isEarnedBy(progress(perfectRuns: 1)), isTrue);
    });

    test('each reads only its own number', () {
      // A condition that accidentally read the points total would unlock the
      // whole shelf at 1000 points. Every badge is checked against progress in
      // which *only* the points have moved, and only the tiers may fire.
      final BadgeProgress rich = progress(points: 100000);
      final Iterable<String> fired = kBadges
          .where((AnimalBadge b) => b.isEarnedBy(rich))
          .map((AnimalBadge b) => b.id);

      expect(fired, <String>['mouse', 'fox', 'bear', 'ele', 'whale']);
    });
  });

  group('nextBadgeGoal', () {
    test('points at the first tier from a standing start', () {
      final BadgeGoal? goal = nextBadgeGoal(0);

      expect(goal!.badge.id, 'mouse');
      expect(goal.need, 50);
      expect(goal.have, 0);
      expect(goal.remaining, 50);
      expect(goal.progress, 0);
    });

    test('moves to the next tier the moment one is reached', () {
      // At exactly 50 the child has *earned* Mouse Scout, so the bar must
      // already be measuring the climb to Fox Explorer rather than sitting full.
      expect(nextBadgeGoal(49)!.badge.id, 'mouse');
      expect(nextBadgeGoal(50)!.badge.id, 'fox');
      expect(nextBadgeGoal(50)!.remaining, 100);
    });

    test('skips every tier already passed, not just the last one', () {
      // A child who scores 700 in one Challenge run passes four tiers at once.
      expect(nextBadgeGoal(700)!.badge.id, 'whale');
      expect(nextBadgeGoal(700)!.remaining, 300);
    });

    test('is null once all five are collected', () {
      // `renderProfile` swaps the bar for "🏆 All animal badges collected"
      // on exactly this (`index.html:532`).
      expect(nextBadgeGoal(1000), isNull);
      expect(nextBadgeGoal(5000), isNull);
    });

    test('names the goal the way the Profile line does', () {
      expect(nextBadgeGoal(10)!.badge.label, '🐭 Mouse Scout');
    });

    test('reports a fraction the progress bar can be given directly', () {
      expect(nextBadgeGoal(25)!.progress, 0.5);
      expect(nextBadgeGoal(100)!.progress, closeTo(100 / 150, 1e-9));
    });

    test('agrees with the badge it points at about whether it is earned', () {
      // The two halves of the derivation, asked of the same number: if the goal
      // says "not yet", the badge must say "not earned", at every tier boundary.
      for (final int points in <int>[0, 49, 50, 149, 150, 999, 1000]) {
        final BadgeGoal? goal = nextBadgeGoal(points);
        if (goal == null) {
          expect(
            kBadges
                .where((AnimalBadge b) => b.pointsGoal != null)
                .every((AnimalBadge b) => b.isEarnedBy(progress(points: points))),
            isTrue,
          );
        } else {
          expect(goal.badge.isEarnedBy(progress(points: points)), isFalse);
        }
      }
    });
  });
}
