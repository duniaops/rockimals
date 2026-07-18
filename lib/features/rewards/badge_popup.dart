/// The celebration popup (`specs/05`: *"a celebration popup (bouncing badge +
/// fanfare, tap to continue)"*) — a port of the prototype's `.badgePop`
/// (`index.html:246-255,331-337`).
///
/// **It mounts above the whole app, not inside a screen, and the placement is
/// the behaviour.** `.badgePop` is `position:absolute; inset:0; z-index:60`
/// (`index.html:247`) — higher than the game overlay (40), the detail screen
/// (45), and even the loading gate (50), i.e. above everything the prototype can
/// show. That is what makes the popup correct at the moment it actually fires:
/// a badge is nearly always earned *mid-game*, with `ov-game` covering the
/// screen, so a popup mounted inside a tab would be celebrated underneath the
/// game the child is looking at. Here it is [RockimalsApp]'s `MaterialApp
/// .builder`, which wraps the `Navigator` and so sits above every pushed route.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rockimals/core/theme/palette.dart';
import 'package:rockimals/features/rewards/badge_controller.dart';
import 'package:rockimals/features/rewards/badges.dart';
import 'package:rockimals/features/rewards/reaction.dart';

/// `transition:transform .3s` on the card (`index.html:249`) — the longer of the
/// two, so it is the whole animation's length and the fade is an interval
/// inside it.
const Duration kBadgePopupDuration = Duration(milliseconds: 300);

/// `transition:opacity .25s` on the scrim (`index.html:247`).
const Duration kBadgePopupFade = Duration(milliseconds: 250);

/// `animation:hop 1.1s ease infinite` on the emoji (`index.html:251`) — slower
/// than the 0.85s answer hop, and endless.
const Duration kBadgeHopDuration = Duration(milliseconds: 1100);

/// `rgba(5,13,28,.72)` (`index.html:247`) — .72 alpha is 183.6, which rounds to
/// 184 (`0xB8`).
const Color _scrim = Color(0xB8050D1C);

/// `backdrop-filter:blur(3px)`. CSS's `blur(<length>)` names the Gaussian's
/// standard deviation, which is what [ui.ImageFilter.blur] takes, so the 3 is
/// carried across unchanged rather than converted.
const double _scrimBlur = 3;

/// `.bcard` (`index.html:249`): `width:260px`, `padding:26px 30px`,
/// `border-radius:22px`, a 1px `--accent` border, and the same
/// `linear-gradient(150deg,#17325c,#0e2244)` the Play hub's points card and
/// featured tile wear.
///
/// **A third local copy of that gradient** (`games_hub.dart` holds the other
/// two, as `_featGradient`). Left duplicated rather than hoisted, for the reason
/// this codebase leaves `_Obar` copied three times: the natural home would be
/// `Palette`, whose membership test is "the prototype named it", and the
/// prototype does not name this — it restates the two hex values at every use
/// (`index.html:210,249,262`). The Profile's `.ptsCard` is the fourth and lands
/// with the next item; extracting it is an appended plan item rather than a
/// reach across two features from here.
const double _cardWidth = 260;
const LinearGradient _cardGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: <Color>[Color(0xFF17325C), Color(0xFF0E2244)],
);

/// Wraps the app and lays the celebration popup over it. See the library doc for
/// why this is a wrapper rather than a widget on a screen.
class BadgePopupHost extends ConsumerStatefulWidget {
  const BadgePopupHost({required this.child, super.key});

  /// The app itself — the `Navigator` [MaterialApp] hands its builder.
  final Widget child;

  @override
  ConsumerState<BadgePopupHost> createState() => _BadgePopupHostState();
}

class _BadgePopupHostState extends ConsumerState<BadgePopupHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: kBadgePopupDuration,
    reverseDuration: kBadgePopupDuration,
  );

  /// The badge whose face is currently in the popup — which outlives
  /// [BadgeState.celebrating] by one fade.
  ///
  /// **This is the DOM the prototype keeps.** `drainBadges` writes the emoji and
  /// the copy into `#bpEmoji`/`#bpTitle`/`#bpDesc` and then toggles a class
  /// (`index.html:994-995`); closing the popup removes the class and leaves the
  /// text exactly where it was, so the card fades out still showing the badge
  /// that was won. A widget rebuilt straight off `celebrating` would blank its
  /// own content on the first frame of the fade and animate an empty card away.
  AnimalBadge? _shown;

  @override
  void initState() {
    super.initState();
    // A popup already open when this mounts (a hot reload, or a test that seeds
    // one) opens fully rather than animating in from nothing.
    final AnimalBadge? already = ref.read(badgesProvider).celebrating;
    if (already != null) {
      _shown = already;
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AnimalBadge?>(
      badgesProvider.select((BadgeState state) => state.celebrating),
      (AnimalBadge? _, AnimalBadge? next) {
        if (next == null) {
          _controller.reverse();
        } else {
          setState(() => _shown = next);
          _controller.forward();
        }
      },
    );

    return Stack(
      children: <Widget>[
        widget.child,
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (BuildContext context, Widget? _) {
              final AnimalBadge? badge = _shown;
              // Nothing at all while closed — not a transparent overlay. The
              // scrim carries a [BackdropFilter], which is one of the more
              // expensive things in a Flutter tree and would otherwise be
              // blurring the whole app for the 99% of the time no badge is being
              // celebrated.
              if (badge == null || _controller.value == 0) {
                return const SizedBox.shrink();
              }
              return _BadgeCelebration(
                badge: badge,
                t: _controller.value,
                onDismiss: () => ref.read(badgesProvider.notifier).dismiss(),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// The scrim and the card, at animation position [t] (0 closed, 1 open).
class _BadgeCelebration extends StatelessWidget {
  const _BadgeCelebration({
    required this.badge,
    required this.t,
    required this.onDismiss,
  });

  final AnimalBadge badge;
  final double t;
  final VoidCallback onDismiss;

  /// `transition:opacity .25s` with CSS's default `ease` timing, over an
  /// animation that runs for 300ms — so the fade finishes five-sixths of the way
  /// through, and the card is still springing when the scrim is already solid.
  static final Animatable<double> _fade = CurveTween(
    curve: Interval(
      0,
      kBadgePopupFade.inMilliseconds / kBadgePopupDuration.inMilliseconds,
      curve: Curves.ease,
    ),
  );

  /// `transform:scale(.8)` → `scale(1)` on
  /// `cubic-bezier(.2,1.5,.4,1)` (`index.html:249-250`) — a control point above
  /// 1 on the y axis, so the card overshoots its final size and settles back.
  /// That overshoot *is* the "pop"; [Curves.easeOut] would land the same size
  /// with none of it.
  static final Animatable<double> _cardScale = Tween<double>(
    begin: 0.8,
    end: 1,
  ).chain(CurveTween(curve: const Cubic(0.2, 1.5, 0.4, 1)));

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      // Read as one sentence, because a screen reader meets this popup with no
      // warning: what was won, how it was won, and what to do about it.
      label:
          'New badge! ${badge.title}. ${badge.description}. '
          'Tap to keep playing.',
      child: GestureDetector(
        // The whole scrim dismisses (`$("badgePop").onclick`,
        // `index.html:1126`) — the target is the screen, which is the right size
        // for a child who is looking at the badge rather than at a button.
        //
        // **It stays tappable and opaque to taps through the closing fade**,
        // where the prototype's `pointer-events:none` lets a tap fall through to
        // whatever is behind. A tap landing on a game answer 200ms after the
        // child dismissed a popup they were not aiming at is the sort of thing
        // that reads as the app answering for them.
        behavior: HitTestBehavior.opaque,
        onTap: onDismiss,
        child: Opacity(
          opacity: _fade.transform(t),
          child: ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: _scrimBlur, sigmaY: _scrimBlur),
              child: ColoredBox(
                color: _scrim,
                child: Center(
                  child: Transform.scale(
                    scale: _cardScale.transform(t),
                    child: ExcludeSemantics(
                      child: _BadgeCard(badge: badge),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.bcard` and its three lines of copy (`index.html:332-337`).
class _BadgeCard extends StatelessWidget {
  const _BadgeCard({required this.badge});

  final AnimalBadge badge;

  @override
  Widget build(BuildContext context) {
    // **A [Material], and not for its look.** This tree hangs off
    // `MaterialApp.builder`, above the `Navigator` and so above every [Scaffold]
    // in the app — and `Text` with no [Material] ancestor silently renders
    // monospace, weight 900, with a yellow double underline, in release as well
    // as debug. `loading_screen.dart` hit the same thing and records the probe.
    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: _cardWidth,
        // `padding:26px 30px` (`index.html:249`).
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 26),
        decoration: BoxDecoration(
          gradient: _cardGradient,
          borderRadius: const BorderRadius.all(Radius.circular(22)),
          // `border:1px solid var(--accent)` — the popup is the one card in the
          // app outlined in the interactive orange rather than `--line`, which
          // is how it reads as an event instead of a panel.
          border: Border.all(color: Palette.accent),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _HoppingEmoji(emoji: badge.emoji),
            // `h3{margin:10px 0 3px}` (`index.html:253`).
            const SizedBox(height: 10),
            Text(
              // `"New badge! "+bd.t` (`index.html:994`).
              'New badge! ${badge.title}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              badge.description,
              textAlign: TextAlign.center,
              // `.badgePop p{color:var(--muted);font-size:13px}`.
              style: const TextStyle(color: Palette.muted, fontSize: 13),
            ),
            // `.tap{margin-top:10px}` (`index.html:255`).
            const SizedBox(height: 10),
            const Text(
              // Lower case and unhurried, per `CLAUDE.md:63` — the popup asks
              // rather than instructs, and there is no way to get it wrong.
              'tap to keep playing',
              textAlign: TextAlign.center,
              style: TextStyle(color: Palette.accent2, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// The badge's emoji at 64px, hopping forever (`.badgePop .em`,
/// `index.html:251`).
///
/// **The same `hop` keyframes a right answer plays**, reused from
/// `reaction.dart` rather than re-ported: the prototype's popup names the very
/// animation `.happy` does (`animation:hop …`, `index.html:238,251`), differing
/// only in that it runs for 1.1s and repeats. Reusing [kHopLift] and [kHopTurns]
/// means the badge's celebration and an animal's cheer are literally the same
/// motion, which is the visual rhyme the prototype has and a second copy of the
/// keyframes would let drift.
class _HoppingEmoji extends StatefulWidget {
  const _HoppingEmoji({required this.emoji});

  final String emoji;

  @override
  State<_HoppingEmoji> createState() => _HoppingEmojiState();
}

class _HoppingEmojiState extends State<_HoppingEmoji>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: kBadgeHopDuration,
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      // `font-size:64px` (`index.html:251`).
      child: Text(widget.emoji, style: const TextStyle(fontSize: 64, height: 1)),
      builder: (BuildContext context, Widget? child) {
        // `hop` is `translateY(…) rotate(…)`, and a CSS transform list applies
        // right-to-left — so the rotation is the inner one. The same nesting
        // `ReactionAvatar` uses, and for the same reason.
        return Transform.translate(
          offset: Offset(0, kHopLift.evaluate(_controller)),
          child: Transform.rotate(
            angle: kHopTurns.evaluate(_controller) * 2 * math.pi,
            child: child,
          ),
        );
      },
    );
  }
}
