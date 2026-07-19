import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/features/radar/radar_capacity.dart';

/// The busy-day guard (`specs/06-title-polish-safety.md:39`).
///
/// The frame rate it protects needs a device this machine does not have, so what
/// is pinned here is the arithmetic underneath it: how many animals survive, and
/// — the half that would break the screen rather than slow it — *which*.
void main() {
  group('capRadarAnimals', () {
    test('leaves an ordinary day completely alone', () {
      // The cap must be invisible on almost every real day. A three-day NeoWs
      // window is normally well under sixty, and on those days the radar has to
      // be exactly the prototype's.
      final List<Asteroid> ordinary = _rocks(12);

      expect(capRadarAnimals(ordinary), same(ordinary));
    });

    test(
      'keeps the whole sky at exactly the cap — the boundary is not off by one',
      () {
        final List<Asteroid> full = _rocks(kMaxRadarAnimals);

        expect(capRadarAnimals(full), hasLength(kMaxRadarAnimals));
        expect(capRadarAnimals(full), same(full));
      },
    );

    test('trims a busy day to the cap', () {
      expect(capRadarAnimals(_rocks(200)), hasLength(kMaxRadarAnimals));
    });

    test('keeps a prefix, so no animal moves when the cap engages', () {
      // **The half that matters more than the count.** An animal's index in this
      // list seeds its orbit phase (`RadarOrbits.seed`, plan decision 9), so a
      // cap that reordered — keeping the sixty closest, say — would put every
      // animal on the field somewhere different. Taking a prefix means the sixty
      // that survive are in the same places they were in.
      final List<Asteroid> busy = _rocks(200);

      final List<Asteroid> capped = capRadarAnimals(busy);

      expect(
        capped.map((Asteroid a) => a.name),
        busy.take(kMaxRadarAnimals).map((Asteroid a) => a.name),
      );
    });

    test('is stable — the same sky twice yields the same animals', () {
      // Nothing here may depend on a clock or a hash seed: a radar that drew a
      // different sixty on every rebuild would shuffle the field under a child's
      // thumb mid-tap.
      final List<Asteroid> busy = _rocks(200);

      expect(
        capRadarAnimals(busy).map((Asteroid a) => a.name),
        capRadarAnimals(busy).map((Asteroid a) => a.name),
      );
    });
  });
}

List<Asteroid> _rocks(int count) => <Asteroid>[
  for (int i = 0; i < count; i++)
    Asteroid(
      name: '2026 A$i',
      diaMax: 4.0 + i * 40,
      diaMin: 2.0 + i * 20,
      hazardous: false,
      // Spread across the field rather than stacked, so a cap that quietly
      // sorted by distance would produce a visibly different list here.
      missLunar: 0.2 + i * 0.5,
      missKm: (0.2 + i * 0.5) * 384400,
      velKps: 12,
      mag: 22,
      jpl: 'https://ssd.jpl.nasa.gov/tools/sbdb_lookup.html',
      date: '2026-07-17',
    ),
];
