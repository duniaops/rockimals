import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rockimals/core/audio/sound_cues.dart';
import 'package:rockimals/core/theme/palette.dart';
import 'package:rockimals/features/games/challenge_game.dart';
import 'package:rockimals/features/games/closer_game.dart';
import 'package:rockimals/features/games/duel_game.dart';
import 'package:rockimals/features/games/games_providers.dart';
import 'package:rockimals/features/games/match_game.dart';
import 'package:rockimals/features/rewards/sound_controller.dart';

/// The Play hub — a port of the prototype's `openGames` (`index.html:1002-1021`),
/// the screen the radar's "🎮 Play" CTA opens.
///
/// It shows the points total, a persisted sound toggle, and the four game cards
/// (Today's Challenge featured, then Power Duel / Closer or Farther / Animal
/// Match, each with its personal best). This is `specs/04`'s "Play hub" item;
/// the four games it launches were their own items after it, and all four have
/// now landed — [_destinationFor] is the one seam each of them edited.
class GamesHub extends ConsumerWidget {
  const GamesHub({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GamesHubStats stats = ref.watch(gamesHubStatsProvider);
    final bool soundOn = ref.watch(soundOnProvider);

    // The four cards, in the prototype's order (`index.html:1003-1006`). Copy is
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
      ),
      _GameCard(
        id: _GameId.closer,
        icon: '📏',
        title: 'Closer or Farther',
        description:
            'Will the next animal fly closer to Earth, or farther away? You decide!',
        badge: 'Best ${stats.bestCloser}',
      ),
      _GameCard(
        id: _GameId.size,
        icon: '🐾',
        title: 'Animal Match',
        description:
            'A space rock zooms by — can you guess which animal it is? 8 rounds.',
        badge: 'Best ${stats.bestSize}/8',
      ),
    ];

    return Scaffold(
      backgroundColor: Palette.pageBackground,
      // `.obar` + `.obody` (`index.html:322-324`): the flat back-bar over a
      // scrolling body, matching the detail screen's chrome rather than a
      // Material [AppBar].
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _Obar(title: 'Play'),
          Expanded(
            child: SingleChildScrollView(
              // `.obody{padding:16px 16px 30px}` (`index.html:95`).
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // The points card + sound toggle row (`index.html:1009-1013`);
                  // `margin-bottom:14`.
                  Row(
                    children: <Widget>[
                      Expanded(child: _PointsCard(points: stats.points)),
                      const SizedBox(width: 10),
                      _SoundButton(
                        on: soundOn,
                        // `if(soundOn)playHappy()` (`index.html:1020`) — turning
                        // sound back on answers with the happy jingle, so the
                        // child hears that it worked instead of only seeing an
                        // emoji change. Turning it *off* is silent, which is both
                        // the prototype's behaviour and the only coherent one.
                        //
                        // The blip must be fired *after* the flip, not before:
                        // the cue is gated on the flag (`SoundController`), so a
                        // play issued while the flag still reads "off" would be
                        // swallowed by the very gate it is confirming. Re-reading
                        // the provider rather than negating the captured `soundOn`
                        // keeps that true even if the toggle ever gains a reason
                        // to refuse.
                        onTap: () async {
                          await ref.read(soundOnProvider.notifier).toggle();
                          if (ref.read(soundOnProvider)) {
                            await ref
                                .read(soundControllerProvider)
                                .play(SoundCue.happy);
                          }
                        },
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
                  for (final _GameCard card in cards)
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
      MaterialPageRoute<void>(builder: (BuildContext context) => _destinationFor(id)),
    );
  }

  /// Where each card goes. All four games have now landed (`specs/04`), so the
  /// kid-toned "coming soon" placeholder each card opened while its game was
  /// still ahead is gone along with the last branch that used it.
  Widget _destinationFor(_GameId id) {
    switch (id) {
      case _GameId.daily:
        return const ChallengeGame();
      case _GameId.duel:
        return const DuelGame();
      case _GameId.closer:
        return const CloserGame();
      case _GameId.size:
        return const MatchGame();
    }
  }
}

/// The four games, used to key [GamesHub._destinationFor].
enum _GameId { daily, duel, closer, size }

/// One game card's static content plus its live badge string.
class _GameCard {
  const _GameCard({
    required this.id,
    required this.icon,
    required this.title,
    required this.description,
    required this.badge,
    this.featured = false,
  });

  final _GameId id;
  final String icon;
  final String title;
  final String description;
  final String badge;
  final bool featured;
}

/// The featured gradient the points card and the daily card share
/// (`linear-gradient(150deg,#17325c,#0e2244)`, `index.html:210,262`).
///
/// `topLeft → bottomRight` approximates CSS's 150° (a line pointing down and
/// slightly right); the two stops are one-off literals the prototype does not
/// name, so they stay here rather than in [Palette] (see the palette's note on
/// one-off colours).
const LinearGradient _featGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: <Color>[Color(0xFF17325C), Color(0xFF0E2244)],
);

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
        gradient: _featGradient,
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
/// The emoji alone is opaque to a screen reader, so a [Semantics] `toggled`
/// carries the state and a plain label carries the name — the radar chips'
/// precedent.
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
          child: Padding(
            // `padding:8px 12px` (`index.html:244`).
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: ExcludeSemantics(
              child: Text(
                on ? '🔊' : '🔇',
                style: const TextStyle(fontSize: 15, color: Palette.ink),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One game card (`.gcard`, `index.html:204-210`): the icon, the title and
/// description, and the personal-best badge, with the featured card carrying the
/// gradient and accent border (`.gfeat`, `index.html:210`).
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
          color: card.featured ? Colors.transparent : Palette.card,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.all(Radius.circular(16)),
            // `.gfeat` borders in accent, a plain card in `--line`.
            side: BorderSide(color: card.featured ? Palette.accent : Palette.line),
          ),
          child: Ink(
            decoration: card.featured
                ? const BoxDecoration(
                    gradient: _featGradient,
                    borderRadius: BorderRadius.all(Radius.circular(16)),
                  )
                : null,
            child: InkWell(
              borderRadius: const BorderRadius.all(Radius.circular(16)),
              onTap: onTap,
              child: Padding(
                // `.gcard{padding:14px}` (`index.html:204`).
                padding: const EdgeInsets.all(14),
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

/// The overlay back-bar (`.obar`, `index.html:92-94`): a card-pill back button
/// and a plain title over a bottom rule.
///
/// A local copy of the detail screen's `_Obar` — the games hub is its second
/// caller, so extracting one shared back-bar is now warranted, but that is its
/// own refactor across a completed, tested module and is left to its plan item
/// (mirroring how the shared `.panel` header was deferred once it gained a
/// second caller).
class _Obar extends StatelessWidget {
  const _Obar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        // `border-bottom:1px solid var(--line2)` (`index.html:92`).
        border: Border(bottom: BorderSide(color: Palette.line2)),
      ),
      child: Padding(
        // `.obar{padding:36px 14px 10px}` — the 36px clears the status bar; the
        // real device inset is added so it clears the notch too.
        padding: EdgeInsets.fromLTRB(
          14,
          36 + MediaQuery.of(context).padding.top,
          14,
          10,
        ),
        child: Row(
          children: <Widget>[
            const _BackButton(),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Palette.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The `.back` pill (`index.html:93`).
class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Back',
      child: Material(
        color: Palette.card,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(11)),
          side: BorderSide(color: Palette.line),
        ),
        child: InkWell(
          borderRadius: const BorderRadius.all(Radius.circular(11)),
          onTap: () => Navigator.of(context).maybePop(),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: ExcludeSemantics(
              child: Text(
                '‹ Back',
                style: TextStyle(
                  color: Palette.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
