import 'package:rockimals/data/models/asteroid.dart';

/// The bundled sample dataset — a verbatim port of the prototype's `FALLBACK`
/// array (`index.html:398-413`), minus `sentry` (it feeds only dead code).
///
/// This is what makes the app playable with no network, which the guardrails
/// require ("works offline via bundled sample data"). A child on a plane sees a
/// full sky of animals, not an error.
///
/// **Dart source rather than a bundled JSON asset**, though the plan allowed
/// either. This list is the answer to "everything else failed" — the network,
/// the feed, the parse. Making it an asset would give the last line of defence
/// its own async load and its own parse step that can fail in turn, on the one
/// path that must not. As Dart it is compile-time checked, synchronous, and
/// const: a malformed record here is a build error, not a runtime one.
///
/// The values are copied digit-for-digit and kept in the prototype's source
/// order, which is load-bearing in two places. `loadData()`'s offline branch
/// takes `asteroids.slice(0, 7)` for the home strip, so the order decides which
/// seven animals visit today; and the radar seeds each animal's orbit phase and
/// radial offset from its index in this list, so re-ordering silently rearranges
/// the sky. Do not sort, dedupe, or tidy these.
///
/// Every record carries `date: 'sample'` — a deliberate non-date. It can never
/// equal a `YYYY-MM-DD` feed key, so the "visiting today" filter yields nothing
/// offline, which is exactly why the offline path picks its seven by slice
/// instead of by date.
const List<Asteroid> kFallbackAsteroids = <Asteroid>[
  Asteroid(
    name: '2011 EW',
    diaMax: 302,
    diaMin: 135,
    hazardous: true,
    missLunar: 12.4,
    missKm: 4766560,
    velKps: 11.2,
    mag: 20.1,
    jpl: _jpl,
    date: sampleDate,
  ),
  Asteroid(
    name: '2006 QV89',
    diaMax: 60,
    diaMin: 27,
    hazardous: false,
    missLunar: 18.9,
    missKm: 7265160,
    velKps: 9.6,
    mag: 25.4,
    jpl: _jpl,
    date: sampleDate,
  ),
  Asteroid(
    name: '2020 SW',
    diaMax: 9,
    diaMin: 4,
    hazardous: false,
    missLunar: 0.07,
    missKm: 26908,
    velKps: 8.1,
    mag: 28.2,
    jpl: _jpl,
    date: sampleDate,
  ),
  Asteroid(
    name: '433 Eros',
    diaMax: 16800,
    diaMin: 8600,
    hazardous: false,
    missLunar: 52.0,
    missKm: 19988800,
    velKps: 5.6,
    mag: 11.2,
    jpl: _jpl,
    date: sampleDate,
  ),
  Asteroid(
    name: '2004 BL86',
    diaMax: 640,
    diaMin: 290,
    hazardous: true,
    missLunar: 3.1,
    missKm: 1191640,
    velKps: 15.6,
    mag: 19.1,
    jpl: _jpl,
    date: sampleDate,
  ),
  Asteroid(
    name: '2012 DA14',
    diaMax: 40,
    diaMin: 18,
    hazardous: false,
    missLunar: 0.09,
    missKm: 34596,
    velKps: 7.8,
    mag: 24.4,
    jpl: _jpl,
    date: sampleDate,
  ),
  Asteroid(
    name: '99942 Apophis',
    diaMax: 370,
    diaMin: 310,
    hazardous: true,
    missLunar: 0.10,
    missKm: 38440,
    velKps: 7.4,
    mag: 19.7,
    jpl: _jpl,
    date: sampleDate,
  ),
  Asteroid(
    name: '2015 TB145',
    diaMax: 640,
    diaMin: 280,
    hazardous: false,
    missLunar: 1.3,
    missKm: 499720,
    velKps: 35.0,
    mag: 19.9,
    jpl: _jpl,
    date: sampleDate,
  ),
  Asteroid(
    name: '2010 WC9',
    diaMax: 130,
    diaMin: 60,
    hazardous: false,
    missLunar: 0.5,
    missKm: 192200,
    velKps: 12.8,
    mag: 23.5,
    jpl: _jpl,
    date: sampleDate,
  ),
  Asteroid(
    name: '2001 FO32',
    diaMax: 1080,
    diaMin: 480,
    hazardous: true,
    missLunar: 5.2,
    missKm: 1998880,
    velKps: 34.4,
    mag: 17.8,
    jpl: _jpl,
    date: sampleDate,
  ),
  Asteroid(
    name: '2005 YU55',
    diaMax: 400,
    diaMin: 180,
    hazardous: true,
    missLunar: 0.85,
    missKm: 326740,
    velKps: 13.1,
    mag: 21.9,
    jpl: _jpl,
    date: sampleDate,
  ),
  Asteroid(
    name: '2019 OK',
    diaMax: 130,
    diaMin: 57,
    hazardous: false,
    missLunar: 0.19,
    missKm: 73036,
    velKps: 24.5,
    mag: 23.3,
    jpl: _jpl,
    date: sampleDate,
  ),
  Asteroid(
    name: '2018 LF16',
    diaMax: 213,
    diaMin: 95,
    hazardous: false,
    missLunar: 40.0,
    missKm: 15376000,
    velKps: 14.0,
    mag: 21.6,
    jpl: _jpl,
    date: sampleDate,
  ),
  Asteroid(
    name: '2013 TX68',
    diaMax: 47,
    diaMin: 21,
    hazardous: false,
    missLunar: 14.0,
    missKm: 5381600,
    velKps: 10.4,
    mag: 24.6,
    jpl: _jpl,
    date: sampleDate,
  ),
];

/// The [Asteroid.date] every sample record carries, and the value the offline
/// path recognises the sample set by. Named rather than inlined because the
/// repository and the tests both have to compare against it, and a typo in a
/// bare `'sample'` would silently make a record look like live data.
const String sampleDate = 'sample';

/// The prototype points every sample record at the JPL Small-Body Database's
/// bare lookup form (`index.html:398-413`) — no `?sstr=` query, unlike the live
/// feed's per-asteroid deep links. That is honest for invented offline data:
/// the link reaches the real tool without claiming to be a record NASA served.
const String _jpl = 'https://ssd.jpl.nasa.gov/tools/sbdb_lookup.html';
