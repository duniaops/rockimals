/// One near-Earth object, as the app uses it.
///
/// A direct port of the prototype's `normalize()` (`index.html:384-395`). The
/// field names are deliberately the prototype's (`diaMax`, `missLunar`, `jpl`)
/// rather than spec 01's longer spellings: every downstream formula in the
/// plan — the size ladder, `danger()`, `radiusFor()` — is cited against these
/// names, and keeping them makes each port readable side-by-side with its
/// source.
///
/// Two fields the prototype parses are deliberately absent:
///
///  * `sentry` — parsed at `index.html:389` but only ever feeds a badge set
///    that is written and never read, so it has no consumer in any version of
///    this app.
///  * `id` — spec 01 lists it, but the prototype never captures one and keys
///    dedupe, radar seeds, follows, and badges off [name]. The designation is
///    the identity here; a second one would just be a second thing to keep in
///    sync.
class Asteroid {
  const Asteroid({
    required this.name,
    required this.diaMax,
    required this.diaMin,
    required this.hazardous,
    required this.missLunar,
    required this.missKm,
    required this.velKps,
    required this.mag,
    required this.jpl,
    required this.date,
  });

  /// Parses one NEO plus the close-approach entry it is being listed under.
  ///
  /// The close approach is a parameter rather than something this factory digs
  /// out because the caller has to decide what to do with a NEO that has none:
  /// the prototype skips it (`index.html:372`). Use [firstCloseApproach] to get
  /// it, which is the only entry the app ever reads — a NEO can carry dozens
  /// (the live feed returns 98 for Apophis), but they are alternate approach
  /// dates, and the one that matters is the one for the day being listed.
  ///
  /// Throws a [FormatException] on a malformed record. This is the one
  /// deliberate deviation from the prototype, which uses `parseFloat` and so
  /// yields `NaN` for an unparseable number. `NaN` would flow silently into
  /// `danger()` and the radar's geometry and surface to a child as "power ⭐
  /// NaN"; throwing instead routes a broken feed to the sample dataset, which
  /// is the designed answer for a feed the app cannot use (spec 01 §3).
  factory Asteroid.fromNeoWs(
    Map<String, Object?> neo,
    Map<String, Object?> closeApproach,
    String date,
  ) {
    final Map<String, Object?> meters = _objectAt(
      _objectAt(neo, 'estimated_diameter'),
      'meters',
    );
    final Map<String, Object?> missDistance = _objectAt(
      closeApproach,
      'miss_distance',
    );
    final Map<String, Object?> velocity = _objectAt(
      closeApproach,
      'relative_velocity',
    );

    return Asteroid(
      name: _cleanName(_stringAt(neo, 'name')),
      diaMax: _doubleAt(meters, 'estimated_diameter_max'),
      diaMin: _doubleAt(meters, 'estimated_diameter_min'),
      hazardous: _boolAt(neo, 'is_potentially_hazardous_asteroid'),
      missLunar: _doubleAt(missDistance, 'lunar'),
      missKm: _doubleAt(missDistance, 'kilometers'),
      velKps: _doubleAt(velocity, 'kilometers_per_second'),
      mag: _doubleAt(neo, 'absolute_magnitude_h'),
      jpl: _stringAt(neo, 'nasa_jpl_url'),
      date: date,
    );
  }

  /// The real designation, e.g. `2011 EW`.
  ///
  /// Kid-facing surfaces never show this — it appears only behind the
  /// grown-up-facts parent gate. Everything else keys off it: it is the dedupe
  /// key, the hash seed that makes an asteroid's animal deterministic, and the
  /// id follows are stored under.
  final String name;

  /// Estimated diameter in metres. [diaMax] drives the whole animal system —
  /// species, size label, and the size half of `power()` all key on it.
  final double diaMax;

  /// Only consumer is the detail screen's "How wide" tile, which shows the
  /// range `{diaMin}–{diaMax} m` rather than a single number.
  final double diaMin;

  /// NASA's "potentially hazardous" flag. Never surfaced as-is — it is an input
  /// to `power()` and `flybyTag()`, which is where it becomes the gentle
  /// "close flyby" wording the guardrails require.
  final bool hazardous;

  /// Miss distance in lunar distances: 1.0 = as far away as the Moon. The unit
  /// the whole app speaks in, via `distLabel()` / `moonCompare()`.
  final double missLunar;

  /// Miss distance in kilometres. Parsed because spec 01 lists it; no v1
  /// consumer, because a raw kilometre count is exactly the "giant raw number"
  /// the guardrails keep out of the main flow.
  final double missKm;

  /// Relative velocity in km/s. Shown as "zooms {n} km/s" and feeds `power()`.
  final double velKps;

  /// Absolute magnitude (H). Parsed because spec 01 lists it; no v1 consumer —
  /// it is an astronomer's brightness scale with no kid-facing meaning.
  final double mag;

  /// JPL Small-Body Database URL. The app's only outbound link, and only from
  /// behind the parent gate.
  final String jpl;

  /// The feed date key this approach was listed under (`2026-07-16`), or
  /// `sample` for the bundled offline records. Compared against today's key to
  /// pick the animals visiting today, so it stays the feed's raw string rather
  /// than a [DateTime] — `sample` has to survive that comparison by never
  /// matching.
  final String date;

  /// The close approach the app reads: the first entry, or null if the NEO has
  /// none, which the prototype treats as "skip this rock" (`index.html:372`).
  static Map<String, Object?>? firstCloseApproach(Map<String, Object?> neo) {
    final Object? entries = neo['close_approach_data'];
    if (entries is! List<Object?> || entries.isEmpty) return null;

    final Object? first = entries.first;
    return first is Map<String, Object?> ? first : null;
  }

  /// Strips parenthesis *characters* — not the group they delimit.
  ///
  /// That is `index.html:385` literally, and the difference is visible on real
  /// data: the feed returns provisional designations as `(2011 EW)`, which
  /// cleans to `2011 EW`, but numbered asteroids as `433 Eros (A898 PA)`, which
  /// cleans to `433 Eros A898 PA` rather than `433 Eros`. Ported as-is: this
  /// string is the hash seed for an asteroid's name and species, so "improving"
  /// it silently reassigns animals.
  static String _cleanName(String raw) => raw.replaceAll(_parens, '').trim();

  static final RegExp _parens = RegExp(r'[()]');

  static Map<String, Object?> _objectAt(Map<String, Object?> json, String key) {
    final Object? value = json[key];
    if (value is Map<String, Object?>) return value;
    throw FormatException('NeoWs: expected an object at "$key", got: $value');
  }

  static String _stringAt(Map<String, Object?> json, String key) {
    final Object? value = json[key];
    if (value is String) return value;
    throw FormatException('NeoWs: expected a string at "$key", got: $value');
  }

  /// Accepts both shapes the feed actually uses: `miss_distance.lunar` and
  /// `relative_velocity.kilometers_per_second` arrive as strings while
  /// `absolute_magnitude_h` and the diameters arrive as numbers. The prototype
  /// gets this for free from `parseFloat`; Dart has to say it out loud.
  static double _doubleAt(Map<String, Object?> json, String key) {
    final Object? value = json[key];
    if (value is num) return value.toDouble();
    if (value is String) {
      final double? parsed = double.tryParse(value);
      if (parsed != null) return parsed;
    }
    throw FormatException('NeoWs: expected a number at "$key", got: $value');
  }

  /// A missing flag reads as false, mirroring the prototype's `!!undefined`.
  /// Anything present but not a bool is a feed the app does not understand.
  static bool _boolAt(Map<String, Object?> json, String key) {
    final Object? value = json[key];
    if (value is bool) return value;
    if (value == null) return false;
    throw FormatException('NeoWs: expected a bool at "$key", got: $value');
  }

  @override
  String toString() =>
      'Asteroid($name, ${diaMax.toStringAsFixed(1)}m, '
      '${missLunar.toStringAsFixed(2)} LD, $date)';
}
