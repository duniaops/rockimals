/// Deterministic daily three-part missions built from the shared asteroid feed.
library;

import 'dart:math' show Random;

import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/data/models/asteroid.dart';

/// The real-data comparison in the middle of a Daily Data Quest.
enum DailyQuestChallenge { size, speed, distance }

/// The quick final activity. Its order rotates by calendar day, not streak.
enum DailyQuestAction { radarDash, moonDash, speedDash, stackDash, memoryDash }

class DailyQuest {
  const DailyQuest({
    required this.dayKey,
    required this.target,
    required this.radarChoices,
    required this.challenge,
    required this.challengeChoices,
    required this.action,
    required this.actionTapGoal,
  });

  final String dayKey;
  final Asteroid target;
  final List<Asteroid> radarChoices;
  final DailyQuestChallenge challenge;
  final List<Asteroid> challengeChoices;
  final DailyQuestAction action;
  final int actionTapGoal;

  String get challengePrompt => switch (challenge) {
    DailyQuestChallenge.size => 'Which animal is biggest?',
    DailyQuestChallenge.speed => 'Which animal zooms fastest?',
    DailyQuestChallenge.distance => 'Which animal passes closest to Earth?',
  };

  String get actionTitle => switch (action) {
    DailyQuestAction.radarDash => 'Radar dash',
    DailyQuestAction.moonDash => 'Moon dash',
    DailyQuestAction.speedDash => 'Speed dash',
    DailyQuestAction.stackDash => 'Stack dash',
    DailyQuestAction.memoryDash => 'Memory dash',
  };
}

/// Builds today's quest from a stable, sorted snapshot.
///
/// The quest never sees a day streak. A calendar day selects a new mission;
/// streaks remain an optional, separate celebration elsewhere in the app.
DailyQuest generateDailyQuest({
  required Iterable<Asteroid> asteroids,
  required String dayKey,
}) {
  final List<Asteroid> pool = asteroids.toList()
    ..sort((Asteroid a, Asteroid b) => a.name.compareTo(b.name));
  if (pool.length < 3) {
    throw ArgumentError.value(
      asteroids,
      'asteroids',
      'needs at least 3 animals',
    );
  }

  final String names = pool.map((Asteroid a) => a.name).join('|');
  final Random random = Random(hashStr('daily-quest|$dayKey|$names'));
  final List<Asteroid> shuffled = List<Asteroid>.of(pool)..shuffle(random);
  final DailyQuestChallenge challenge = DailyQuestChallenge
      .values[random.nextInt(DailyQuestChallenge.values.length)];
  final List<Asteroid> choices = shuffled.take(3).toList(growable: false);
  final Asteroid target = _winner(choices, challenge);
  final DailyQuestAction action = DailyQuestAction
      .values[_dayNumber(dayKey) % DailyQuestAction.values.length];
  final List<Asteroid> radarChoices = List<Asteroid>.of(choices)
    ..shuffle(random);
  final List<Asteroid> challengeChoices = List<Asteroid>.of(choices)
    ..shuffle(random);
  final int actionTapGoal = _actionTapGoal(target, action);

  return DailyQuest(
    dayKey: dayKey,
    target: target,
    radarChoices: List<Asteroid>.unmodifiable(radarChoices),
    challenge: challenge,
    challengeChoices: List<Asteroid>.unmodifiable(challengeChoices),
    action: action,
    actionTapGoal: actionTapGoal,
  );
}

/// Adds a patch once while preserving every earlier reward.
List<String> recordDailyQuestPatch(Iterable<String> existing, String dayKey) {
  final List<String> patches = existing.toList(growable: true);
  if (!patches.contains(dayKey)) patches.add(dayKey);
  return List<String>.unmodifiable(patches);
}

Asteroid _winner(List<Asteroid> choices, DailyQuestChallenge challenge) {
  return choices.reduce((Asteroid best, Asteroid candidate) {
    final bool candidateWins = switch (challenge) {
      DailyQuestChallenge.size => candidate.diaMax > best.diaMax,
      DailyQuestChallenge.speed => candidate.velKps > best.velKps,
      DailyQuestChallenge.distance => candidate.missLunar < best.missLunar,
    };
    return candidateWins ? candidate : best;
  });
}

int _dayNumber(String dayKey) =>
    DateTime.tryParse(dayKey)?.difference(DateTime(2000)).inDays ??
    (hashStr(dayKey) & 0x7fffffff);

int _actionTapGoal(Asteroid target, DailyQuestAction action) {
  final double value = switch (action) {
    DailyQuestAction.radarDash => target.missLunar,
    DailyQuestAction.moonDash => target.missLunar,
    DailyQuestAction.speedDash => target.velKps,
    DailyQuestAction.stackDash => target.diaMax,
    DailyQuestAction.memoryDash => target.velKps,
  };
  // A 2–4 beat dash is short, reachable, and visibly derived from NASA data.
  return 2 + (value.round().abs() % 3);
}
