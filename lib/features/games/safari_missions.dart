/// The deterministic mission rules behind Radar Safari.
///
/// A Safari screen will turn these missions into taps on the radar. Keeping the
/// rules here means it can ask one important question without owning a hidden
/// answer: whether a tapped asteroid is one of *every* real asteroid that
/// satisfies the mission. That makes tied facts fair — two equally-fast
/// animals are both right — and keeps the offline fallback playable.
library;

import 'dart:math';

import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/data/models/asteroid.dart';

/// The first set of fact-led Safari missions.
///
/// Combined criteria belong in a later mission set. [SafariMission] deliberately
/// carries the complete accepted designation list rather than one chosen target,
/// so that extension cannot accidentally turn a tied real-world fact into a
/// single-answer quiz.
enum SafariMissionKind { fastest, insideTenMoons, smallestToday, closeFlyby }

/// One Radar Safari mission and every real asteroid that completes it.
class SafariMission {
  const SafariMission({required this.kind, required this.correctDesignations});

  final SafariMissionKind kind;

  /// Designations rather than list indices: a radar's drawing order is not a
  /// fact about the animal and must never decide a mission's answer.
  final List<String> correctDesignations;

  /// The kid-facing instruction shown before the Safari screen reveals a fact.
  String get prompt => switch (kind) {
    SafariMissionKind.fastest => 'Find the fastest animal!',
    SafariMissionKind.insideTenMoons =>
      'Find an animal visiting inside 10× the Moon!',
    SafariMissionKind.smallestToday => "Find today's smallest visitor!",
    SafariMissionKind.closeFlyby => 'Find a close-flyby animal waving hello!',
  };

  /// Whether [asteroid] is a correct answer for this generated mission.
  ///
  /// The complete list, rather than a single chosen winner, is the tie-safe
  /// grader required for facts such as "fastest" and "smallest".
  bool accepts(Asteroid asteroid) =>
      correctDesignations.contains(asteroid.name);

  /// The NASA-backed fact the screen repeats after a correct tap.
  ///
  /// Callers use this for an asteroid that [accepts]; it intentionally speaks
  /// only in the kid-facing units already used throughout the app.
  String supportingFact(Asteroid asteroid) => switch (kind) {
    SafariMissionKind.fastest =>
      '${critter(asteroid).first} zooms ${speedLabel(asteroid.velKps)} — '
          'fastest in this sky!',
    SafariMissionKind.insideTenMoons =>
      '${critter(asteroid).first} passes ${distLabel(asteroid.missLunar)} '
          'away — inside 10× the Moon!',
    SafariMissionKind.smallestToday =>
      '${critter(asteroid).first} is ${asteroid.diaMax.round()} m wide — '
          "today's smallest visitor!",
    SafariMissionKind.closeFlyby =>
      '${critter(asteroid).first} is waving hello on a close flyby!',
  };
}

/// Generate the initial Safari mission set from a feed snapshot and a day key.
///
/// [dayKey] is passed in from the app's shared clock boundary rather than read
/// here: this remains a pure, repeatable function for the same date and feed.
/// The seed uses sorted designations, so reordering a radar list cannot change
/// the mission order. The rules themselves always inspect the unmodified feed.
///
/// When the bundled offline feed is in use, every asteroid has `date: sample`.
/// There is no literal "today" subset in that data, so [smallestToday] uses the
/// whole fallback sky; that is what keeps the offline game solvable.
List<SafariMission> generateSafariMissions({
  required List<Asteroid> asteroids,
  required String dayKey,
}) {
  if (asteroids.isEmpty) {
    throw ArgumentError.value(
      asteroids,
      'asteroids',
      'Radar Safari needs at least one asteroid.',
    );
  }

  final List<Asteroid> today = asteroids
      .where((Asteroid asteroid) => asteroid.date == dayKey)
      .toList(growable: false);
  final List<Asteroid> smallestPool = today.isEmpty ? asteroids : today;

  final double fastestSpeed = asteroids
      .map((Asteroid asteroid) => asteroid.velKps)
      .reduce(max);
  final double smallestDiameter = smallestPool
      .map((Asteroid asteroid) => asteroid.diaMax)
      .reduce(min);

  final Map<SafariMissionKind, List<String>> targets =
      <SafariMissionKind, List<String>>{
        SafariMissionKind.fastest: _designationsWhere(
          asteroids,
          (Asteroid asteroid) => asteroid.velKps == fastestSpeed,
        ),
        SafariMissionKind.insideTenMoons: _designationsWhere(
          asteroids,
          (Asteroid asteroid) => asteroid.missLunar < 10,
        ),
        SafariMissionKind.smallestToday: _designationsWhere(
          smallestPool,
          (Asteroid asteroid) => asteroid.diaMax == smallestDiameter,
        ),
        SafariMissionKind.closeFlyby: _designationsWhere(
          asteroids,
          (Asteroid asteroid) => flybyTag(asteroid) == FlybyTag.closeFlyby,
        ),
      };

  // Each basic kind must be playable. A live feed can be unusual, so a mission
  // that has no answer is omitted rather than asking a child an impossible
  // question. The bundled fallback has answers for all four kinds.
  final List<SafariMissionKind> kinds = SafariMissionKind.values
      .where((SafariMissionKind kind) => targets[kind]!.isNotEmpty)
      .toList(growable: false);
  final List<String> designations =
      asteroids.map((Asteroid asteroid) => asteroid.name).toList()..sort();
  final Random seededOrder = Random(
    hashStr('$dayKey|${designations.join('|')}'),
  );
  kinds.shuffle(seededOrder);

  return List<SafariMission>.unmodifiable(
    kinds.map(
      (SafariMissionKind kind) =>
          SafariMission(kind: kind, correctDesignations: targets[kind]!),
    ),
  );
}

List<String> _designationsWhere(
  List<Asteroid> asteroids,
  bool Function(Asteroid asteroid) predicate,
) {
  final List<String> designations =
      asteroids
          .where(predicate)
          .map((Asteroid asteroid) => asteroid.name)
          .toSet()
          .toList()
        ..sort();
  return List<String>.unmodifiable(designations);
}
