/// The app's one persistent store: everything Rockimals remembers between
/// launches.
///
/// A port of the prototype's `localStorage` layer (`index.html:954-955,
/// 956-999`) onto Hive, plus the four fields the prototype never had a home for
/// (follows, the day streak, and the two accessibility toggles — plan decisions
/// 3, 4 and 7), plus [cachedFeed].
///
/// **This is a field store, deliberately.** It reads and writes values; it owns
/// no rules. "Points never decrease" (spec 05), "the streak counts consecutive
/// days played" (decision 3), and "a badge is earned once its condition holds"
/// all belong to the features that own those behaviours — the store would only
/// be a second place for them to disagree. [cachedFeed] is held to the same
/// line: the store keeps the string, and `CachingFeedSource` owns every rule
/// about what is in it and when it has gone off.
///
/// **Nothing here is personal data** and nothing may become so: `CLAUDE.md:60`
/// forbids collecting anything that identifies a child. Every field below is a
/// score, a toggle, an asteroid designation the child chose to follow, or — in
/// [cachedFeed]'s case — a copy of what NASA published to the whole world.
/// There is no name, no device id, no timestamp finer than a calendar day, and
/// no network path out of this box.
///
/// One thing worth saying out loud, because the class summary used to promise
/// otherwise: [cachedFeed] is **not** about a child at all. It is a disposable
/// copy of a public feed, and it is the one field here that could be deleted
/// without taking anything away from them. It lives in this box regardless,
/// because a second box would mean a second open on the launch path and a
/// second thing that can fail there — see [boxName].
library;

import 'package:hive/hive.dart';

/// Typed access to the persisted box.
///
/// Construct with [open], which is also what the tests use — the box is opened
/// through the same path the app takes, so "it reads back after a restart" is a
/// property the suite can actually check rather than assume.
class Store {
  Store._(this._box);

  /// Opens (and creates on first launch) the app's box.
  ///
  /// The caller is responsible for having initialised Hive first —
  /// `Hive.initFlutter()` in the app, `Hive.init(dir)` in a test. That split is
  /// why this class takes no path: `initFlutter` needs Flutter bindings and
  /// `path_provider`, and requiring them here would make the store untestable
  /// on the host VM for no gain.
  static Future<Store> open() async =>
      Store._(await Hive.openBox<Object>(boxName));

  /// One box, not one per concern. The whole store is a few dozen small values
  /// read at launch and written a handful of times a session; splitting it
  /// would buy nothing and add open/close paths that can fail independently.
  static const String boxName = 'rockimals';

  final Box<Object> _box;

  // --- Keys ------------------------------------------------------------------
  //
  // The `aw_` prefix is inherited from the prototype (`index.html:954-999`),
  // where it stood for "asteroid watch" — a brand plan decision 5 retired in
  // favour of ROCKIMALS. It is kept anyway, and it is worth saying why, because
  // the reason is *not* migration: these keys named entries in a browser's
  // localStorage, and no child's data crosses from that prototype into this
  // app's Hive box. They are kept because reviewing this port means diffing it
  // against `index.html`, and a shared key name is what makes each field's
  // counterpart findable there by grep. The prefix carries no meaning beyond
  // that — do not read a product name into it, and do not rename these without
  // a migration once a build has shipped.
  //
  // The five keys with no prototype counterpart take the same prefix, so the
  // box has one convention rather than two.

  static const String _pointsKey = 'aw_points';
  static const String _playedKey = 'aw_played';
  static const String _bestStreakKey = 'aw_bstreak';
  static const String _perfectKey = 'aw_perfect';
  static const String _badgesKey = 'aw_badges';
  static const String _bestDuelKey = 'aw_duel';
  static const String _bestCloserKey = 'aw_closer';
  static const String _bestSizeKey = 'aw_size';
  static const String _soundOnKey = 'aw_sound';
  static const String _followsKey = 'aw_follows';
  static const String _dayStreakKey = 'aw_daystreak';
  static const String _lastPlayedDateKey = 'aw_lastplayed';
  static const String _reducedMotionKey = 'aw_motion';
  static const String _littleKidsModeKey = 'aw_littlekids';
  static const String _cachedFeedKey = 'aw_feedcache';
  static const String _gameTutorialProgressKey = 'aw_gameintro';
  static const String _dailyQuestPatchesKey = 'aw_questpatches';

  // --- Rewards ---------------------------------------------------------------

  /// The lifetime points total (`aw_points`, `index.html:971`). Defaults to 0.
  int get points => _readInt(_pointsKey);

  Future<void> setPoints(int value) => _box.put(_pointsKey, value);

  /// How many games have been played, ever (`aw_played`, `index.html:972`).
  /// Defaults to 0. The Lift Off badge is `played > 0`.
  int get played => _readInt(_playedKey);

  Future<void> setPlayed(int value) => _box.put(_playedKey, value);

  /// The best run of correct answers in a row, across every game
  /// (`aw_bstreak`, `index.html:972`). Defaults to 0.
  ///
  /// Distinct from [dayStreak], which counts days rather than answers. The
  /// prototype conflated the two under one flame icon; decision 3 separates
  /// them.
  int get bestStreak => _readInt(_bestStreakKey);

  Future<void> setBestStreak(int value) => _box.put(_bestStreakKey, value);

  /// How many times Animal Match has been finished 8/8 (`aw_perfect`,
  /// `index.html:972`). Defaults to 0. A counter rather than a flag because
  /// that is what the prototype persists; the Perfect Match badge only asks
  /// whether it is above zero.
  int get perfect => _readInt(_perfectKey);

  Future<void> setPerfect(int value) => _box.put(_perfectKey, value);

  /// The ids of every badge earned (`aw_badges`, `index.html:973`). Defaults to
  /// empty.
  ///
  /// Ids, not badge objects: the copy, emoji, and unlock condition live in
  /// `ZBADGES` in code, so persisting them would freeze a child's shelf at
  /// whatever the wording was on the day they earned it.
  List<String> get badges => _readStringList(_badgesKey);

  Future<void> setBadges(Iterable<String> value) =>
      _box.put(_badgesKey, value.toList(growable: false));

  // --- Game bests ------------------------------------------------------------

  /// Best Power Duel streak (`aw_duel`, `index.html:956`). Defaults to 0.
  int get bestDuel => _readInt(_bestDuelKey);

  Future<void> setBestDuel(int value) => _box.put(_bestDuelKey, value);

  /// Best Closer or Farther streak (`aw_closer`, `index.html:956`). Defaults
  /// to 0.
  int get bestCloser => _readInt(_bestCloserKey);

  Future<void> setBestCloser(int value) => _box.put(_bestCloserKey, value);

  /// Best Animal Match score out of 8 (`aw_size`, `index.html:956`). Defaults
  /// to 0.
  int get bestSize => _readInt(_bestSizeKey);

  Future<void> setBestSize(int value) => _box.put(_bestSizeKey, value);

  // --- Collection ------------------------------------------------------------

  /// The designations of every followed animal (`follows`, decision 4).
  /// Defaults to empty.
  ///
  /// **Keyed by real designation** (`2011 EW`), which is the identity of an
  /// asteroid everywhere in this app — the dedupe key, the `hashStr` seed, and
  /// so the thing that makes "Milo the Fox" the same animal next launch (plan
  /// decision 12). Never store the animal's name: it is derived, and storing a
  /// derived value is how a follow survives into a build where the pool changed
  /// and quietly points at a different creature.
  ///
  /// The prototype's `watch` Set (`index.html:344`) was in-memory only, which
  /// left it able to restore the Zoo Keeper badge — badges *are* persisted —
  /// onto an empty My Animals list. `CLAUDE.md:33` lists follows among what
  /// local storage holds; this is that.
  ///
  /// Order is insertion order, and is preserved rather than sorted: My Animals
  /// sorts by distance at render time (spec 05), so this list's order is not a
  /// display order and nothing should read it as one.
  List<String> get follows => _readStringList(_followsKey);

  Future<void> setFollows(Iterable<String> value) =>
      _box.put(_followsKey, value.toList(growable: false));

  // --- Day streak (decision 3) -----------------------------------------------

  /// Consecutive days played (`dayStreak`, decision 3). Defaults to 0 on a
  /// fresh install.
  ///
  /// This replaces the prototype's `streak` (`index.html:345`), which seeded at
  /// a hardcoded `3`, incremented on every Challenge reveal whether the child
  /// was right or wrong (`index.html:941`), and never persisted — a
  /// challenges-completed counter with a fake head start, wearing a flame.
  int get dayStreak => _readInt(_dayStreakKey);

  Future<void> setDayStreak(int value) => _box.put(_dayStreakKey, value);

  /// The calendar day the child last played, as `yyyy-mm-dd`, or null if they
  /// never have.
  ///
  /// **This is a local-calendar day, not a UTC one** — the opposite of the
  /// feed's date keys, and deliberately. `AsteroidRepository` formats in UTC
  /// because its keys must agree with the ones NASA files records under; this
  /// key must agree with the *child's* idea of "yesterday". On a UTC+13 phone a
  /// UTC key would roll the streak over in the middle of the afternoon.
  ///
  /// A date string rather than a `DateTime` because a day is all that is ever
  /// compared, and because the finest timestamp this app keeps about a child
  /// should be the coarsest one that works.
  String? get lastPlayedDate => _read<String>(_lastPlayedDateKey);

  Future<void> setLastPlayedDate(String value) =>
      _box.put(_lastPlayedDateKey, value);

  // --- Settings (decision 7) -------------------------------------------------

  /// Whether sound is on (`aw_sound`, `index.html:959`). Defaults to **true** —
  /// a game that starts silent reads as broken.
  ///
  /// **The prototype's default is ported; its persistence is not, because it
  /// does not work.** `gGet` ends in `||d` (`index.html:954`), which coalesces
  /// on *falsy*, not on *missing* — so a stored `0` reads back as the default
  /// `1`. Sound off therefore survives exactly until the page is reloaded, on
  /// every browser, always. It is a real bug and not a behaviour to be faithful
  /// to: specs 05 and 08 both require the toggle to hold across a restart, and
  /// a child who turned sound off and had it turn itself back on would be right
  /// to think the app ignored them.
  ///
  /// This is why [_readInt] and friends key on *absence*, never on falsiness —
  /// the one place a stored zero and a missing key must not be the same answer.
  /// Stored as a real bool, not the prototype's 1/0, which was a workaround for
  /// localStorage holding only strings.
  bool get soundOn => _read<bool>(_soundOnKey) ?? true;

  Future<void> setSoundOn(bool value) => _box.put(_soundOnKey, value);

  /// The Calm motion setting (`reducedMotion`, decision 7), or **null when the
  /// child has never chosen** — which is not the same as "off" and must not be
  /// collapsed into it.
  ///
  /// Spec 08 requires this to default to the OS accessibility flag
  /// (`MediaQuery.disableAnimations`) on first run and to follow the child's
  /// choice ever after. Only a third state can express that: were this a plain
  /// `bool` defaulting to false, "no choice yet, ask the OS" and "explicitly
  /// off" would be one value, and either the OS flag would be ignored or a
  /// deliberate "off" would be overridden by it at every launch. The reader
  /// resolves null against the OS; everything else is the child's word.
  ///
  /// Its kid-facing label is "🐢 Calm motion". The phrase "reduced motion"
  /// names the key and nothing a child sees (spec 08).
  bool? get reducedMotion => _read<bool>(_reducedMotionKey);

  Future<void> setReducedMotion(bool value) =>
      _box.put(_reducedMotionKey, value);

  /// The Little Kids mode toggle (`littleKidsMode`, decision 7). Defaults to
  /// **off**, and this one is a plain bool on purpose — unlike [reducedMotion]
  /// there is no OS signal to defer to, so "unset" and "off" genuinely are the
  /// same answer.
  bool get littleKidsMode => _read<bool>(_littleKidsModeKey) ?? false;

  Future<void> setLittleKidsMode(bool value) =>
      _box.put(_littleKidsModeKey, value);

  // --- The feed cache (plan decision 13) -------------------------------------

  /// The last window NASA answered, as one opaque string, or null when nothing
  /// has been cached yet — what lets an offline launch show a real sky instead
  /// of the sample set.
  ///
  /// **Opaque on purpose, and this is the field-store line being held.** The
  /// store does not know that this is JSON, that it holds asteroids, or when it
  /// goes off; `CachingFeedSource` (`lib/data/feed_cache.dart`) owns the format
  /// and every rule about it. Typing this field would put the cache's shape in
  /// two places, and the store is the one that could not tell you when they had
  /// drifted apart.
  ///
  /// **One field rather than the obvious three** (a window key, a timestamp, a
  /// payload), and that is not tidiness — it is the only shape that cannot tear.
  /// Hive has no transaction across separate `put`s, so three fields can be
  /// interrupted after two: a launch that died between writing the key and
  /// writing the payload would leave the *new* window key labelling the *old*
  /// asteroids, and the next launch would serve a stale sky believing it was
  /// today's, with nothing throwing and nothing to notice. One `put` of one
  /// string is atomic, so the entry is either wholly the old one or wholly the
  /// new one.
  String? get cachedFeed => _read<String>(_cachedFeedKey);

  Future<void> setCachedFeed(String value) => _box.put(_cachedFeedKey, value);

  // --- Game introduction -----------------------------------------------------

  /// Completed game-guide steps (`aw_gameintro`).
  ///
  /// One compact list holds the shared guide token plus the four game practice
  /// tokens. It records only which parts of Rockimals have been shown, never a
  /// child's answers, time, or identity. Keeping the related booleans together
  /// avoids turning a first-run teaching aid into several persistent records.
  List<String> get gameTutorialProgress =>
      _readStringList(_gameTutorialProgressKey);

  Future<void> setGameTutorialProgress(Iterable<String> value) =>
      _box.put(_gameTutorialProgressKey, value.toList(growable: false));

  // --- Daily Data Quest -----------------------------------------------------

  /// Calendar-day ids for completed Daily Data Quests.
  ///
  /// A patch is an earned collection item, never a streak. Keeping every id
  /// means missing a day cannot remove a reward or make a later quest harder.
  /// The date is deliberately the same coarse local-day value used by the day
  /// clock, not a time or a record of where a child played.
  List<String> get dailyQuestPatches => _readStringList(_dailyQuestPatchesKey);

  Future<void> setDailyQuestPatches(Iterable<String> value) =>
      _box.put(_dailyQuestPatchesKey, value.toList(growable: false));

  // --- Lifecycle -------------------------------------------------------------

  Future<void> close() => _box.close();

  // --- Reads -----------------------------------------------------------------

  /// Every read is type-checked rather than cast, so a box holding the wrong
  /// shape answers with the default instead of throwing.
  ///
  /// The prototype is defensive in the same way and for the same reason — its
  /// `gGet`/`gSet` and its badge parse are each wrapped in a bare `try/catch`
  /// (`index.html:954-955, 973, 988`). The failure being defended against is a
  /// child losing the whole app to a store they cannot see, cannot clear, and
  /// did nothing to corrupt: a half-written box, or a field that changed type
  /// between two versions of Rockimals. Points reset to zero is a bad day; a
  /// launch that throws is an app that is simply gone.
  T? _read<T>(String key) {
    final Object? raw = _box.get(key);
    return raw is T ? raw : null;
  }

  /// Defaults to 0, which is every counter's fresh-install value
  /// (`index.html:956, 971, 972`).
  int _readInt(String key) => _read<int>(key) ?? 0;

  /// Hive hands back a `List<dynamic>` after a reopen even where a
  /// `List<String>` went in — the element type does not survive the binary
  /// round trip. So this filters by element type rather than casting the list:
  /// a `List<String>` cast would pass in memory and throw on the very next
  /// launch, which is the failure mode least likely to be caught by a test that
  /// does not reopen the box.
  ///
  /// Unmodifiable, and copied: these back the badge shelf and My Animals, and
  /// nothing that reads them should be able to write through to the box without
  /// going past a setter.
  List<String> _readStringList(String key) {
    final Object? raw = _box.get(key);
    if (raw is! List<Object?>) return const <String>[];
    return List<String>.unmodifiable(raw.whereType<String>());
  }
}
