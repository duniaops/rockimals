import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rockimals/core/a11y/tap_target.dart';
import 'package:rockimals/core/chrome/obar.dart';
import 'package:rockimals/core/chrome/panel.dart';
import 'package:rockimals/core/theme/featured_gradient.dart';
import 'package:rockimals/core/theme/palette.dart';
import 'package:rockimals/features/games/challenge_game.dart';
import 'package:rockimals/features/games/closer_game.dart';
import 'package:rockimals/features/games/daily_quest_screen.dart';
import 'package:rockimals/features/games/duel_game.dart';
import 'package:rockimals/features/games/flyby_snap_screen.dart';
import 'package:rockimals/features/games/games_providers.dart';
import 'package:rockimals/features/games/match_game.dart';
import 'package:rockimals/features/games/moon_lanes_screen.dart';
import 'package:rockimals/features/games/safari_game.dart';
import 'package:rockimals/features/games/size_stack_screen.dart';
import 'package:rockimals/features/games/tutorial/game_tutorial.dart';
import 'package:rockimals/features/games/zoo_memory_screen.dart';
import 'package:rockimals/features/settings/little_kids_mode.dart';
import 'package:rockimals/features/settings/sound.dart';

/// The Play hub — a port of the prototype's `openGames` (`index.html:1002-1021`),
/// the screen the radar's "🎮 Play" CTA opens.
///
/// It shows the points total, a persisted sound toggle, and the game cards
/// (Today's Challenge featured, then Power Duel / Closer or Farther / Animal
/// Match, each with its personal best). This is `specs/04`'s "Play hub" item;
/// the original four games it launches were their own items, and all have
/// now landed — [_destinationFor] is the one seam each of them edited.
///
/// **This screen is also the only door to any game**, which is what lets 🧸
/// Little Kids mode narrow the offering here and nowhere else: no other widget
/// in the app constructs a game, so a card that is not drawn is a game that
/// cannot be reached. See [_GameCard.simplest].
class GamesHub extends ConsumerWidget {
  const GamesHub({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GamesHubStats stats = ref.watch(gamesHubStatsProvider);
    final bool soundOn = ref.watch(soundOnProvider);

    // The four original cards retain the prototype's order (`index.html:1003-1006`). Copy is
    // ported verbatim, curly apostrophes and em dashes included.
    final List<_GameCard> cards = <_GameCard>[
      const _GameCard(
        id: _GameId.daily,
        icon: '🎯',
        title: "Today's Challenge",
        description:
            'Line up today’s space animals from strongest to weakest power.',
        badge: 'Daily',
        featured: true,
      ),
      _GameCard(
        id: _GameId.duel,
        icon: '⚔️',
        title: 'Power Duel',
        description:
            'Two space animals — tap the one with more power! Keep your streak going.',
        badge: 'Best ${stats.bestDuel}',
        simplest: true,
      ),
      _GameCard(
        id: _GameId.closer,
        icon: '📏',
        title: 'Closer or Farther',
        description:
            'Will the next animal fly closer to Earth, or farther away? You decide!',
        badge: 'Best ${stats.bestCloser}',
        simplest: true,
      ),
      _GameCard(
        id: _GameId.size,
        icon: '🐾',
        title: 'Animal Match',
        description:
            'A space rock zooms by — can you guess which animal it is? 8 rounds.',
        badge: 'Best ${stats.bestSize}/8',
      ),
      const _GameCard(
        id: _GameId.dailyQuest,
        icon: '🗓️',
        title: 'Daily Data Quest',
        description:
            'A fresh three-part mission using today’s real space-animal data.',
        badge: 'Daily quest',
      ),
      const _GameCard(
        id: _GameId.safari,
        icon: '🧭',
        title: 'Radar Safari',
        description:
            'Follow real space clues and find the right animal on the live radar.',
        badge: 'Explore',
      ),
      const _GameCard(
        id: _GameId.moonLanes,
        icon: '🌙',
        title: 'Moon Lanes',
        description:
            'Drag space animals into lanes by their real Moon-distance flyby.',
        badge: 'Sort',
      ),
      const _GameCard(
        id: _GameId.flybySnap,
        icon: '📸',
        title: 'Flyby Snap',
        description:
            'Tap the camera window as an animal flies by at real-speed-inspired pace.',
        badge: 'Speed',
      ),
      const _GameCard(
        id: _GameId.sizeStack,
        icon: '🧱',
        title: 'Size Stack',
        description:
            'Build a steady tower with the biggest real space animals at the bottom.',
        badge: 'Build',
      ),
      const _GameCard(
        id: _GameId.zooMemory,
        icon: '🧠',
        title: 'Space Zoo Memory',
        description:
            'Remember each animal’s real space fact, then reconnect the pairs.',
        badge: 'Remember',
      ),
    ];

    // 🧸 Little Kids mode offers the two simplest games only
    // (`specs/06-title-polish-safety.md:26`). The hub asks the experience *what
    // to do* and never what the child chose — the split `little_kids_mode.dart`
    // exists for.
    final bool simplestOnly = ref
        .watch(littleKidsExperienceProvider)
        .simplestGamesOnly;
    // At a larger text scale the two cards cannot share the narrow header
    // without compressing the points card. Stack them rather than shrinking or
    // clipping the sound control's visible words.
    final bool stackedHeader = MediaQuery.textScalerOf(context).scale(12) > 12;

    return Scaffold(
      backgroundColor: Palette.pageBackground,
      // `.obar` + `.obody` (`index.html:322-324`): the flat back-bar over a
      // scrolling body, matching the detail screen's chrome rather than a
      // Material [AppBar].
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Obar(title: 'Play'),
          Expanded(
            child: SingleChildScrollView(
              // `.obody{padding:16px 16px 30px}` (`index.html:95`).
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // The points card + sound toggle row (`index.html:1009-1013`);
                  // `margin-bottom:14`.
                  stackedHeader
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            _PointsCard(points: stats.points),
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerRight,
                              child: _SoundButton(
                                on: soundOn,
                                onTap: () =>
                                    ref.read(soundOnProvider.notifier).toggle(),
                              ),
                            ),
                          ],
                        )
                      : Row(
                          children: <Widget>[
                            Expanded(child: _PointsCard(points: stats.points)),
                            const SizedBox(width: 10),
                            _SoundButton(
                              on: soundOn,
                              // The confirmation jingle `if(soundOn)playHappy()`
                              // (`index.html:1020`) used to be spelled out here,
                              // because this button was once the only place the toggle
                              // could be flipped. Settings is now a second flip point,
                              // so the rule lives in [SoundOnNotifier.toggle] and both
                              // surfaces inherit it — see the note there.
                              onTap: () =>
                                  ref.read(soundOnProvider.notifier).toggle(),
                            ),
                          ],
                        ),
                  const SizedBox(height: 14),
                  // `.h-sub` (`index.html:1014`); `margin-bottom:12`.
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Play, collect points, and win animal badges! 🏅 '
                      'Every animal is a real asteroid flying past Earth.',
                      style: TextStyle(
                        color: Palette.muted,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ),
                  // Generous game cards deliberately keep their roomy,
                  // easy-to-hit layout. On a short phone the lower cards sit
                  // below the fold, so say both how many there are and how to
                  // reach them before the first card begins.
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      '10 games · Scroll down to explore ↓',
                      style: TextStyle(
                        color: Palette.muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  for (final _GameCard card in cards)
                    if (!simplestOnly || card.simplest)
                      _GameCardTile(
                        card: card,
                        onTap: () => _launch(context, card.id),
                      ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Open a game (`c.onclick=…go()`, `index.html:1019`). The games are still
  /// ahead in `specs/04`, so each id routes to its placeholder for now;
  /// [_destinationFor] is the one seam each game item edits.
  void _launch(BuildContext context, _GameId id) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => _destinationFor(id),
      ),
    );
  }

  /// Where each card goes. The original four games have landed (`specs/04`), so the
  /// kid-toned "coming soon" placeholder each card opened while its game was
  /// still ahead is gone along with the last branch that used it.
  Widget _destinationFor(_GameId id) {
    switch (id) {
      case _GameId.daily:
        return GameTutorialGate(
          game: GameTutorialId.daily,
          builder:
              ({
                required bool practice,
                required VoidCallback onPracticeComplete,
              }) => ChallengeGame(
                practice: practice,
                onPracticeComplete: onPracticeComplete,
              ),
        );
      case _GameId.duel:
        return GameTutorialGate(
          game: GameTutorialId.duel,
          builder:
              ({
                required bool practice,
                required VoidCallback onPracticeComplete,
              }) => DuelGame(
                practice: practice,
                onPracticeComplete: onPracticeComplete,
              ),
        );
      case _GameId.closer:
        return GameTutorialGate(
          game: GameTutorialId.closer,
          builder:
              ({
                required bool practice,
                required VoidCallback onPracticeComplete,
              }) => CloserGame(
                practice: practice,
                onPracticeComplete: onPracticeComplete,
              ),
        );
      case _GameId.size:
        return GameTutorialGate(
          game: GameTutorialId.match,
          builder:
              ({
                required bool practice,
                required VoidCallback onPracticeComplete,
              }) => MatchGame(
                practice: practice,
                onPracticeComplete: onPracticeComplete,
              ),
        );
      case _GameId.safari:
        return const SafariGame();
      case _GameId.moonLanes:
        return const MoonLanesScreen();
      case _GameId.flybySnap:
        return const FlybySnapScreen();
      case _GameId.sizeStack:
        return const SizeStackScreen();
      case _GameId.zooMemory:
        return const ZooMemoryScreen();
      case _GameId.dailyQuest:
        return const DailyQuestScreen();
    }
  }
}

/// The games, used to key [GamesHub._destinationFor].
enum _GameId {
  daily,
  duel,
  closer,
  size,
  safari,
  moonLanes,
  flybySnap,
  sizeStack,
  zooMemory,
  dailyQuest,
}

/// One game card's static content plus its live badge string.
class _GameCard {
  const _GameCard({
    required this.id,
    required this.icon,
    required this.title,
    required this.description,
    required this.badge,
    this.featured = false,
    this.simplest = false,
  });

  final _GameId id;
  final String icon;
  final String title;
  final String description;
  final String badge;
  final bool featured;

  /// Whether 🧸 Little Kids mode keeps this card
  /// ([LittleKidsMode.simplestGamesOnly], `specs/06-title-polish-safety.md:26`).
  ///
  /// **Power Duel and Closer or Farther — and the *rule* is the thing to carry
  /// forward, not the pair.** Neither spec says which two are simplest, so this
  /// is a product judgment, made rather than guessed: the games kept are the two
  /// whose whole interaction is *tap one of two things*, answerable from what is
  /// already on the screen. Today's Challenge asks a child to order four animals
  /// against each other. Animal Match poses its question as a width in metres —
  /// it is the app's best teacher of the size ladder and, for the same reason,
  /// the one game a child who cannot yet read numbers can only guess at.
  ///
  /// A fifth game answers that rule rather than reopening the argument, and a
  /// grown-up reading the Settings row is told the pair by name, so this is not
  /// a hidden choice.
  final bool simplest;
}

/// The points tile (`.ptsCard` with its `openGames` inline overrides,
/// `index.html:1010-1012`): the star, the big accent number, and the "points"
/// caption, laid out in a row.
class _PointsCard extends StatelessWidget {
  const _PointsCard({required this.points});

  final int points;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: kFeaturedGradient,
        border: Border.all(color: Palette.line),
        // `.ptsCard{border-radius:20px}` (`index.html:262`).
        borderRadius: const BorderRadius.all(Radius.circular(20)),
      ),
      child: Padding(
        // `padding:12px 14px` (`index.html:1010`).
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: <Widget>[
            const Text('⭐', style: TextStyle(fontSize: 26)),
            // `gap:11px` (`index.html:1010`).
            const SizedBox(width: 11),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '$points',
                  style: const TextStyle(
                    color: Palette.accent2,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                const Text(
                  'points',
                  style: TextStyle(color: Palette.muted, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The sound on/off button (`.sndBtn` / `#sndToggle`, `index.html:1012,1020`).
///
/// The emoji is a quick visual cue, not the control's only meaning. A visible
/// state label helps children who do not recognise the glyph, while [Semantics]
/// carries the same toggle state for assistive technology.
class _SoundButton extends StatelessWidget {
  const _SoundButton({required this.on, required this.onTap});

  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: on,
      label: 'Sound',
      child: Material(
        // `background:rgba(19,42,77,.85)` (`index.html:244`).
        color: const Color.fromRGBO(19, 42, 77, 0.85),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          side: BorderSide(color: Palette.line),
        ),
        child: InkWell(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          onTap: onTap,
          // Short on both axes (39×37), so `expandWidth` as well — the same
          // pair of shortfalls the radar's zoom buttons have.
          child: TapTarget(
            expandWidth: true,
            child: Padding(
              // `padding:8px 12px` (`index.html:244`).
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: ExcludeSemantics(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      on ? '🔊' : '🔇',
                      style: const TextStyle(fontSize: 15, color: Palette.ink),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      on ? 'Sound on' : 'Sound off',
                      style: const TextStyle(
                        color: Palette.ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.gfeat` (`index.html:210`) — the featured card keeps `.gcard`'s corners and
/// padding but swaps the card fill for the shared gradient and the hairline
/// border for the accent.
///
/// Stated as a whole decoration so it is interchangeable with [kPanelSurface]:
/// the two branches then differ by *which surface*, not by which of three
/// properties each one sets.
const BoxDecoration _featuredCardSurface = BoxDecoration(
  gradient: kFeaturedGradient,
  borderRadius: kPanelRadius,
  border: Border.fromBorderSide(BorderSide(color: Palette.accent)),
);

/// One game card (`.gcard`, `index.html:204-210`): the icon, the title and
/// description, and the personal-best badge, with the featured card carrying the
/// gradient and accent border (`.gfeat`, `index.html:210`).
///
/// **Deliberately not scaled by 🧸 Little Kids mode.** The whole card is the
/// [InkWell], and its icon, title and description already measure ~154dp tall —
/// two and a half times the 60dp floor the multiplier would raise it to. This is
/// the case `AnimalCard` answered the other way, so the difference is worth
/// naming: that row scales its *padding* because a crowded 72dp row genuinely
/// reads as cramped to a small child, whereas a card this size gains nothing but
/// fewer games per screen — and in 🧸 mode the hub is already down to two.
/// Pinned in `test/a11y/one_off_controls_test.dart`.
class _GameCardTile extends StatelessWidget {
  const _GameCardTile({required this.card, required this.onTap});

  final _GameCard card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // `.gcard{margin-bottom:11px}` (`index.html:204`).
      padding: const EdgeInsets.only(bottom: 11),
      child: Semantics(
        button: true,
        child: Material(
          // The surface is the [Ink] below, not this [Material] — so the plain
          // card can paint [kPanelSurface] itself rather than restating the fill
          // and border through `color`/`shape`, which cannot take a decoration.
          // The radar's toggle chip already carries a splash this way.
          type: MaterialType.transparency,
          child: Ink(
            // A plain `.gcard` *is* a `.panel` that happens to be tappable
            // (`core/chrome/panel.dart`); the featured one is its own surface.
            decoration: card.featured ? _featuredCardSurface : kPanelSurface,
            child: InkWell(
              borderRadius: kPanelRadius,
              onTap: onTap,
              child: Padding(
                // `.gcard{padding:14px}` (`index.html:204`) — the same 14 the
                // shared panel pads by, and read from there.
                padding: kPanelPadding,
                child: Row(
                  children: <Widget>[
                    // `.gi{font-size:26px;width:42px;text-align:center}`.
                    SizedBox(
                      width: 42,
                      child: Text(
                        card.icon,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 26),
                      ),
                    ),
                    // `.gcard{gap:12px}` (`index.html:204`).
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          // `.gt{font-weight:800;font-size:15px}`.
                          Text(
                            card.title,
                            style: const TextStyle(
                              color: Palette.ink,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          // `.gd{color:var(--muted);font-size:12px;margin-top:3px;
                          // line-height:1.4}`.
                          const SizedBox(height: 3),
                          Text(
                            card.description,
                            style: const TextStyle(
                              color: Palette.muted,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // `.gb{margin-left:auto;font-size:11px;color:var(--accent2);
                    // font-weight:800;text-align:right;white-space:nowrap}`.
                    Text(
                      card.badge,
                      textAlign: TextAlign.right,
                      softWrap: false,
                      style: const TextStyle(
                        color: Palette.accent2,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
