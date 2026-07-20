import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/data/fallback_asteroids.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/features/games/safari_missions.dart';

/// The fact rules for Radar Safari, with no radar widget in sight.
///
/// The important property is that a mission captures every correct answer from
/// the real feed. NASA data can tie, and choosing one tied animal would make a
/// child who found another correct animal look wrong.
void main() {
  group('generateSafariMissions', () {
    test(
      'is deterministic from the day key and designations, not feed order',
      () {
        final List<SafariMission> first = generateSafariMissions(
          asteroids: kFallbackAsteroids,
          dayKey: '2026-07-20',
        );
        final List<SafariMission> reordered = generateSafariMissions(
          asteroids: kFallbackAsteroids.reversed.toList(),
          dayKey: '2026-07-20',
        );
        final List<SafariMission> repeated = generateSafariMissions(
          asteroids: kFallbackAsteroids,
          dayKey: '2026-07-20',
        );

        expect(_signature(repeated), _signature(first));
        expect(_signature(reordered), _signature(first));
      },
    );

    test('includes a solvable mission for every basic Safari fact offline', () {
      final List<SafariMission> missions = generateSafariMissions(
        asteroids: kFallbackAsteroids,
        dayKey: '2026-07-20',
      );

      expect(
        missions.map((SafariMission mission) => mission.kind).toSet(),
        SafariMissionKind.values.toSet(),
      );
      for (final SafariMission mission in missions) {
        expect(
          mission.correctDesignations,
          isNotEmpty,
          reason: '${mission.kind} must be playable in offline mode',
        );
        expect(
          kFallbackAsteroids.any(mission.accepts),
          isTrue,
          reason: '${mission.kind} must accept an offline animal',
        );
      }
    });

    test(
      'accepts every tied qualifying animal, never just one selected target',
      () {
        final List<Asteroid> sky = <Asteroid>[
          _rock(
            'Fast A',
            date: '2026-07-20',
            diaMax: 30,
            missLunar: 8,
            velKps: 20,
          ),
          _rock(
            'Fast B',
            date: '2026-07-20',
            diaMax: 30,
            missLunar: 10,
            velKps: 20,
          ),
          _rock(
            'Tiny A',
            date: '2026-07-20',
            diaMax: 5,
            missLunar: 0.5,
            velKps: 8,
          ),
          _rock(
            'Tiny B',
            date: '2026-07-20',
            diaMax: 5,
            missLunar: 30,
            velKps: 7,
          ),
          _rock(
            'Waving from afar',
            date: '2026-07-20',
            diaMax: 80,
            missLunar: 30,
            velKps: 6,
            hazardous: true,
          ),
        ];
        final List<SafariMission> missions = generateSafariMissions(
          asteroids: sky,
          dayKey: '2026-07-20',
        );

        final SafariMission fastest = _mission(
          missions,
          SafariMissionKind.fastest,
        );
        expect(fastest.accepts(sky[0]), isTrue);
        expect(fastest.accepts(sky[1]), isTrue);
        expect(fastest.accepts(sky[2]), isFalse);

        final SafariMission insideTen = _mission(
          missions,
          SafariMissionKind.insideTenMoons,
        );
        expect(insideTen.accepts(sky[0]), isTrue);
        expect(insideTen.accepts(sky[2]), isTrue);
        expect(insideTen.accepts(sky[1]), isFalse, reason: '10× is not inside');

        final SafariMission smallest = _mission(
          missions,
          SafariMissionKind.smallestToday,
        );
        expect(smallest.accepts(sky[2]), isTrue);
        expect(smallest.accepts(sky[3]), isTrue);
        expect(smallest.accepts(sky[0]), isFalse);

        final SafariMission closeFlyby = _mission(
          missions,
          SafariMissionKind.closeFlyby,
        );
        expect(closeFlyby.accepts(sky[2]), isTrue, reason: 'inside the Moon');
        expect(
          closeFlyby.accepts(sky[4]),
          isTrue,
          reason: 'NASA marked it close',
        );
        expect(closeFlyby.accepts(sky[3]), isFalse);
      },
    );

    test(
      'uses the real dated subset for today smallest when one is available',
      () {
        final Asteroid yesterdayTiny = _rock(
          'Yesterday tiny',
          date: '2026-07-19',
          diaMax: 1,
          missLunar: 20,
          velKps: 5,
        );
        final Asteroid todaySmall = _rock(
          'Today small',
          date: '2026-07-20',
          diaMax: 10,
          missLunar: 5,
          velKps: 10,
        );
        final List<SafariMission> missions = generateSafariMissions(
          asteroids: <Asteroid>[yesterdayTiny, todaySmall],
          dayKey: '2026-07-20',
        );

        final SafariMission smallest = _mission(
          missions,
          SafariMissionKind.smallestToday,
        );
        expect(smallest.accepts(todaySmall), isTrue);
        expect(smallest.accepts(yesterdayTiny), isFalse);
      },
    );
  });
}

SafariMission _mission(List<SafariMission> missions, SafariMissionKind kind) =>
    missions.singleWhere((SafariMission mission) => mission.kind == kind);

List<String> _signature(List<SafariMission> missions) => missions
    .map(
      (SafariMission mission) =>
          '${mission.kind.name}:${mission.correctDesignations.join(',')}',
    )
    .toList(growable: false);

Asteroid _rock(
  String name, {
  required String date,
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
    date: date,
  );
}
