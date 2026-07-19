import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/data/models/asteroid.dart';

/// `test/fixtures/neows_feed.json` is a real, unedited NeoWs response —
/// `GET /feed?start_date=2026-07-14&end_date=2026-07-16&api_key=DEMO_KEY`,
/// captured 2026-07-16, reformatted only by pretty-printing so it diffs.
///
/// It is a capture rather than a hand-written sample on purpose: the two
/// details this parser exists to get right are details a hand-written fixture
/// would have got wrong. NASA sends every name parenthesised (`(2011 UT)`), and
/// it sends distances and velocities as *strings* while diameters and magnitude
/// come as *numbers*. Both are load-bearing here, and neither is documented
/// anywhere the plan could have cited.
void main() {
  final Map<String, Object?> byDate = _loadFeedByDate();

  group('Asteroid.fromNeoWs', () {
    test('parses a captured NeoWs record into every field', () {
      final Map<String, Object?> neo = _neo(byDate, '2026-07-14', '(2011 UT)');

      final Asteroid a = Asteroid.fromNeoWs(
        neo,
        Asteroid.firstCloseApproach(neo)!,
        '2026-07-14',
      );

      expect(a.name, '2011 UT');
      expect(a.diaMax, 41.3085526634);
      expect(a.diaMin, 18.4737463615);
      expect(a.hazardous, isFalse);
      expect(a.missLunar, 67.9418789874);
      expect(a.missKm, 26128432.854274542);
      expect(a.velKps, 15.0684989645);
      expect(a.mag, 25.79);
      expect(
        a.jpl,
        'https://ssd.jpl.nasa.gov/tools/sbdb_lookup.html#/?sstr=3582056',
      );
      expect(a.date, '2026-07-14');
    });

    test('carries the hazardous flag through', () {
      // The only true in the capture. Never shown as "hazardous" to a kid, but
      // it has to survive parsing: it is a term in power() and it is half of
      // what makes an animal a "close flyby".
      final Map<String, Object?> neo = _neo(
        byDate,
        '2026-07-15',
        '(2011 LA19)',
      );

      final Asteroid a = Asteroid.fromNeoWs(
        neo,
        Asteroid.firstCloseApproach(neo)!,
        '2026-07-15',
      );

      expect(a.hazardous, isTrue);
      expect(a.diaMax, 871.043769791);
    });

    test('parses every record in the captured feed', () {
      // Guards the whole schema, not one lucky record: a field NASA sends as a
      // string on one rock and a number on another would surface here.
      final List<Asteroid> all = _parseAll(byDate);

      expect(all, hasLength(13));
      expect(all.map((a) => a.name), everyElement(isNot(contains('('))));
      expect(all.every((a) => a.diaMax >= a.diaMin), isTrue);
    });

    test('strips parenthesis characters rather than the group they delimit', () {
      // index.html:385 is `replace(/[()]/g,"")`, and on real data the two
      // NeoWs name formats land differently: provisional designations clean up,
      // numbered asteroids keep their alternate designation with the brackets
      // gone. Both strings below are verbatim from the live API. This is the
      // prototype's behaviour and the port must match it, because this string
      // is the hash seed that fixes an asteroid's animal and name forever.
      expect(_nameOf('(2011 EW)'), '2011 EW');
      expect(_nameOf('433 Eros (A898 PA)'), '433 Eros A898 PA');
      expect(_nameOf('  (2020 SW)  '), '2020 SW');
    });

    test('reads only the first close approach', () {
      // The feed lists one approach per rock per day, but the same object can
      // carry dozens (the live API returns 98 for Apophis). The prototype takes
      // `close_approach_data[0]` and the rest are other dates entirely — using
      // one would put an animal at a distance it is not at today.
      final Map<String, Object?> neo = _syntheticNeo(
        closeApproaches: <Object?>[
          _closeApproach(lunar: '1.5', km: '576000', kps: '7.7'),
          _closeApproach(lunar: '40.0', km: '15376000', kps: '14.0'),
        ],
      );

      final Asteroid a = Asteroid.fromNeoWs(
        neo,
        Asteroid.firstCloseApproach(neo)!,
        '2026-07-16',
      );

      expect(a.missLunar, 1.5);
      expect(a.velKps, 7.7);
    });

    test('treats a missing hazardous flag as false', () {
      final Map<String, Object?> neo = _syntheticNeo()
        ..remove('is_potentially_hazardous_asteroid');

      final Asteroid a = Asteroid.fromNeoWs(
        neo,
        Asteroid.firstCloseApproach(neo)!,
        '2026-07-16',
      );

      expect(a.hazardous, isFalse);
    });

    test('throws rather than yielding NaN on an unparseable number', () {
      // The prototype's parseFloat would hand NaN to danger() and to the
      // radar's geometry, and a child would read "power ⭐ NaN". Throwing sends
      // a broken feed to the sample data instead, which is the designed answer.
      final Map<String, Object?> neo = _syntheticNeo(
        closeApproaches: <Object?>[_closeApproach(lunar: 'unknown')],
      );

      expect(
        () => Asteroid.fromNeoWs(neo, Asteroid.firstCloseApproach(neo)!, 'x'),
        throwsFormatException,
      );
    });

    test('throws on a structurally broken record', () {
      final Map<String, Object?> neo = _syntheticNeo()
        ..remove('estimated_diameter');

      expect(
        () => Asteroid.fromNeoWs(neo, Asteroid.firstCloseApproach(neo)!, 'x'),
        throwsFormatException,
      );
    });
  });

  group('Asteroid.firstCloseApproach', () {
    test('returns null when a rock has no approach data', () {
      // Not an error — the feed does include these, and the prototype skips the
      // rock. The caller needs to tell "skip" apart from "broken".
      expect(
        Asteroid.firstCloseApproach(
          _syntheticNeo(closeApproaches: <Object?>[]),
        ),
        isNull,
      );
      expect(
        Asteroid.firstCloseApproach(
          _syntheticNeo()..remove('close_approach_data'),
        ),
        isNull,
      );
    });
  });

  group('the cache round trip', () {
    // `toJson`/`fromJson` are the app's own format, written and read only by the
    // disk feed cache. What makes them worth their own tests is that they are
    // the one place an `Asteroid` stops being an object and becomes bytes: a
    // field lost here comes back as an animal that changed species overnight,
    // because `hashStr` seeds on `name` and the ladder keys on `diaMax`.

    test('preserves every real record, field for field', () {
      // Swept over the whole captured feed rather than a probe, because the
      // interesting values are the ones NASA actually sends — long decimals that
      // a naive `toString` would round, and negative-exponent diameters.
      final List<Asteroid> parsed = _parseFixture();
      expect(parsed, isNotEmpty);

      for (final Asteroid original in parsed) {
        final Asteroid restored = Asteroid.fromJson(
          // Through a real encode/decode, not just the map: `jsonEncode` is
          // where a double would lose precision if it ever were to, and testing
          // the map alone would skip exactly that step.
          jsonDecode(jsonEncode(original.toJson())) as Map<String, Object?>,
        );

        expect(restored.name, original.name);
        expect(restored.diaMax, original.diaMax);
        expect(restored.diaMin, original.diaMin);
        expect(restored.hazardous, original.hazardous);
        expect(restored.missLunar, original.missLunar);
        expect(restored.missKm, original.missKm);
        expect(restored.velKps, original.velKps);
        expect(restored.mag, original.mag);
        expect(restored.jpl, original.jpl);
        expect(restored.date, original.date);
      }
    });

    test('rejects a record with a field missing', () {
      // Strict where `fromNeoWs` is lenient, and the asymmetry is deliberate:
      // NASA's feed has genuinely optional fields, this format does not — it is
      // written by this app, so a gap means corruption. The only caller answers
      // a throw by refetching, so strictness costs a request and buys never
      // showing a silently wrong animal.
      final Map<String, Object?> json = _asteroid().toJson();

      for (final String key in json.keys) {
        expect(
          () => Asteroid.fromJson(Map<String, Object?>.of(json)..remove(key)),
          throwsFormatException,
          reason: 'a cache entry missing "$key" must not parse',
        );
      }
    });

    test('rejects a missing hazard flag rather than reading it as false', () {
      // Called out separately because this is the one field where `fromNeoWs`
      // does the opposite — `!!undefined` is false, mirroring the prototype. A
      // cache entry with no hazard flag is not an unflagged asteroid; it is not
      // an asteroid. Read leniently it would silently drop the +2.2 power bump
      // and the "close flyby" tag.
      expect(
        () => Asteroid.fromJson(_asteroid().toJson()..remove('hazardous')),
        throwsFormatException,
      );
      expect(
        () => Asteroid.fromJson(_asteroid().toJson()..['hazardous'] = 1),
        throwsFormatException,
      );
    });

    test('rejects a field of the wrong type', () {
      expect(
        () => Asteroid.fromJson(_asteroid().toJson()..['diaMax'] = 'wide'),
        throwsFormatException,
      );
      expect(
        () => Asteroid.fromJson(_asteroid().toJson()..['name'] = 42),
        throwsFormatException,
      );
    });
  });
}

Asteroid _asteroid() => const Asteroid(
  name: '2011 EW',
  diaMax: 302.3,
  diaMin: 135.2,
  hazardous: false,
  missLunar: 12.4,
  missKm: 4768123.5,
  velKps: 7.13,
  mag: 21.2,
  jpl: 'https://ssd.jpl.nasa.gov/tools/sbdb_lookup.html',
  date: '2026-07-16',
);

/// Every asteroid in the captured feed, parsed the way the client parses them.
List<Asteroid> _parseFixture() {
  final Map<String, Object?> byDate = _loadFeedByDate();
  final List<Asteroid> parsed = <Asteroid>[];

  for (final MapEntry<String, Object?> day in byDate.entries) {
    for (final Object? neo in day.value! as List<Object?>) {
      final Map<String, Object?> record = neo! as Map<String, Object?>;
      final Map<String, Object?>? approach = Asteroid.firstCloseApproach(
        record,
      );
      if (approach == null) continue;
      parsed.add(Asteroid.fromNeoWs(record, approach, day.key));
    }
  }
  return parsed;
}

Map<String, Object?> _loadFeedByDate() {
  final String raw = File('test/fixtures/neows_feed.json').readAsStringSync();
  final Map<String, Object?> feed = jsonDecode(raw) as Map<String, Object?>;
  return feed['near_earth_objects']! as Map<String, Object?>;
}

Map<String, Object?> _neo(
  Map<String, Object?> byDate,
  String date,
  String name,
) {
  final List<Object?> day = byDate[date]! as List<Object?>;
  return day.cast<Map<String, Object?>>().firstWhere(
    (neo) => neo['name'] == name,
  );
}

List<Asteroid> _parseAll(Map<String, Object?> byDate) {
  final List<Asteroid> out = <Asteroid>[];
  byDate.forEach((date, objects) {
    for (final Map<String, Object?> neo
        in (objects! as List<Object?>).cast<Map<String, Object?>>()) {
      final Map<String, Object?>? cad = Asteroid.firstCloseApproach(neo);
      if (cad == null) continue;
      out.add(Asteroid.fromNeoWs(neo, cad, date));
    }
  });
  return out;
}

String _nameOf(String rawName) {
  final Map<String, Object?> neo = _syntheticNeo()..['name'] = rawName;
  return Asteroid.fromNeoWs(
    neo,
    Asteroid.firstCloseApproach(neo)!,
    '2026-07-16',
  ).name;
}

/// Mirrors the capture's shape, trimmed to the keys the parser reads.
Map<String, Object?> _syntheticNeo({List<Object?>? closeApproaches}) {
  return <String, Object?>{
    'name': '(2020 SW)',
    'nasa_jpl_url': 'https://ssd.jpl.nasa.gov/tools/sbdb_lookup.html',
    'absolute_magnitude_h': 28.2,
    'estimated_diameter': <String, Object?>{
      'meters': <String, Object?>{
        'estimated_diameter_min': 4.1,
        'estimated_diameter_max': 9.3,
      },
    },
    'is_potentially_hazardous_asteroid': false,
    'close_approach_data': closeApproaches ?? <Object?>[_closeApproach()],
  };
}

Map<String, Object?> _closeApproach({
  String lunar = '0.07',
  String km = '26908',
  String kps = '8.1',
}) {
  return <String, Object?>{
    'relative_velocity': <String, Object?>{'kilometers_per_second': kps},
    'miss_distance': <String, Object?>{'lunar': lunar, 'kilometers': km},
  };
}
