import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/data/fallback_asteroids.dart';
import 'package:rockimals/data/models/asteroid.dart';

/// These tests pin the offline dataset against `index.html:398-413`.
///
/// They matter more than "a const list is obviously correct" suggests. This
/// list is the app's offline guarantee, so it is the data every airplane-mode
/// check, every offline test, and — until the NeoWs client lands — every
/// downstream port is read against. A wrong digit here does not throw; it
/// quietly gives an asteroid the wrong animal, and the test that finds it is
/// three items away and phrased as "why is Eros a Bear?".
void main() {
  Asteroid byName(String name) =>
      kFallbackAsteroids.firstWhere((Asteroid a) => a.name == name);

  group('kFallbackAsteroids', () {
    test('bundles exactly the prototype\'s 14 records', () {
      expect(kFallbackAsteroids, hasLength(14));
    });

    test('marks every record as sample data', () {
      // 'sample' can never equal a YYYY-MM-DD feed key, which is what makes the
      // offline path's "visiting today" filter come back empty by design.
      expect(
        kFallbackAsteroids.every((Asteroid a) => a.date == sampleDate),
        isTrue,
      );
      expect(sampleDate, 'sample');
    });

    test('gives every record the JPL lookup URL', () {
      expect(
        kFallbackAsteroids.every(
          (Asteroid a) => a.jpl == 'https://ssd.jpl.nasa.gov/tools/sbdb_lookup.html',
        ),
        isTrue,
      );
    });

    test('carries 2011 EW with its prototype values', () {
      final Asteroid a = byName('2011 EW');

      expect(a.diaMax, 302);
      expect(a.diaMin, 135);
      expect(a.hazardous, isTrue);
      expect(a.missLunar, 12.4);
      expect(a.missKm, 4766560);
      expect(a.velKps, 11.2);
      expect(a.mag, 20.1);
    });

    test('carries 433 Eros with its prototype values', () {
      final Asteroid a = byName('433 Eros');

      expect(a.diaMax, 16800);
      expect(a.diaMin, 8600);
      expect(a.hazardous, isFalse);
      expect(a.missLunar, 52.0);
      expect(a.missKm, 19988800);
      expect(a.velKps, 5.6);
      expect(a.mag, 11.2);
    });

    test('carries 99942 Apophis with its prototype values', () {
      final Asteroid a = byName('99942 Apophis');

      expect(a.diaMax, 370);
      expect(a.diaMin, 310);
      expect(a.hazardous, isTrue);
      expect(a.missLunar, 0.10);
      expect(a.missKm, 38440);
      expect(a.velKps, 7.4);
      expect(a.mag, 19.7);
    });

    test('keeps the prototype\'s source order', () {
      // Order is data, not presentation. The offline path takes the first seven
      // of this list as the animals "visiting today" (index.html:381), and the
      // radar seeds each animal's orbit phase and radial offset from its index
      // here — so sorting this list would rearrange the sky and swap out the
      // home strip, with nothing failing to say so.
      expect(kFallbackAsteroids.map((Asteroid a) => a.name).toList(), <String>[
        '2011 EW',
        '2006 QV89',
        '2020 SW',
        '433 Eros',
        '2004 BL86',
        '2012 DA14',
        '99942 Apophis',
        '2015 TB145',
        '2010 WC9',
        '2001 FO32',
        '2005 YU55',
        '2019 OK',
        '2018 LF16',
        '2013 TX68',
      ]);
    });

    test('has a unique designation per record', () {
      // The designation is this app's identity: the dedupe key, the hash seed
      // behind each animal's species and name, and the key follows persist
      // under. A duplicate here would give two rocks one animal and one
      // follow-state, so the invariant is worth asserting rather than assuming.
      final Set<String> names = kFallbackAsteroids
          .map((Asteroid a) => a.name)
          .toSet();

      expect(names, hasLength(kFallbackAsteroids.length));
    });

    test('states a plausible size range for every record', () {
      // Catches the transcription slip a digit-by-digit read misses: diaMin and
      // diaMax swapped, or a stray zero. The detail screen renders these as the
      // range "{diaMin}–{diaMax} m", which reads as nonsense inverted.
      for (final Asteroid a in kFallbackAsteroids) {
        expect(a.diaMin, lessThan(a.diaMax), reason: '${a.name} diameter range');
        expect(a.diaMin, greaterThan(0), reason: '${a.name} diameter');
        expect(a.missLunar, greaterThan(0), reason: '${a.name} miss distance');
        expect(a.velKps, greaterThan(0), reason: '${a.name} velocity');
      }
    });
  });
}
