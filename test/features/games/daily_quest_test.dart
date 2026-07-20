import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/data/fallback_asteroids.dart';
import 'package:rockimals/features/games/daily_quest.dart';

void main() {
  group('generateDailyQuest', () {
    test(
      'is deterministic for a fixed day and feed regardless of feed order',
      () {
        final DailyQuest first = generateDailyQuest(
          asteroids: kFallbackAsteroids,
          dayKey: '2026-07-20',
        );
        final DailyQuest reordered = generateDailyQuest(
          asteroids: kFallbackAsteroids.reversed,
          dayKey: '2026-07-20',
        );

        expect(first.target.name, reordered.target.name);
        expect(first.challenge, reordered.challenge);
        expect(first.action, reordered.action);
        expect(first.actionTapGoal, reordered.actionTapGoal);
        expect(
          first.radarChoices.map((asteroid) => asteroid.name),
          reordered.radarChoices.map((asteroid) => asteroid.name),
        );
      },
    );

    test('rotates the final game type across days', () {
      final Set<DailyQuestAction> actions = <DailyQuestAction>{
        for (int day = 20; day < 25; day++)
          generateDailyQuest(
            asteroids: kFallbackAsteroids,
            dayKey: '2026-07-$day',
          ).action,
      };

      expect(actions, hasLength(DailyQuestAction.values.length));
    });

    test('needs enough animals to make a real choice', () {
      expect(
        () => generateDailyQuest(
          asteroids: kFallbackAsteroids.take(2),
          dayKey: '2026-07-20',
        ),
        throwsArgumentError,
      );
    });
  });

  test('a missed day never removes an earned patch', () {
    final List<String> afterMiss = recordDailyQuestPatch(<String>[
      '2026-07-18',
    ], '2026-07-20');

    expect(afterMiss, <String>['2026-07-18', '2026-07-20']);
    expect(recordDailyQuestPatch(afterMiss, '2026-07-20'), afterMiss);
  });
}
