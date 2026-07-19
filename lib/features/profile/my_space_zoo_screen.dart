import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rockimals/core/a11y/tap_target.dart';
import 'package:rockimals/core/theme/featured_gradient.dart';
import 'package:rockimals/core/theme/palette.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/profile/profile_providers.dart';
import 'package:rockimals/features/rewards/badge_controller.dart';
import 'package:rockimals/features/rewards/badges.dart';
import 'package:rockimals/features/settings/settings_screen.dart';

/// `.xpbar{background:#0a1830}` (`index.html:147`) — the unfilled part of the
/// progress bar, darker than any panel so the fill reads as light in a groove.
///
/// A one-off literal the prototype never named, so it stays local rather than
/// joining `Palette` — the rule `app_shell.dart` states for its own `_navSurface`.
const Color _xpTrack = Color(0xFF0A1830);

/// `.xpbar i{background:linear-gradient(90deg,var(--accent2),var(--accent))}`
/// (`index.html:148`) — left-to-right, so the bar warms as it fills. CSS's
/// `90deg` is [LinearGradient]'s default axis, hence no `begin`/`end` here.
const LinearGradient _xpFill = LinearGradient(
  colors: <Color>[Palette.accent2, Palette.accent],
);

/// The My Space Zoo tab — the points a child has collected, how close they are
/// to their next animal badge, three quick stats, and the badge shelf
/// (`specs/05-rewards-collection.md:40-43`, prototype `renderProfile`,
/// `index.html:518-540`).
///
/// A [ConsumerWidget] with no local state, the shape My Animals settled on next
/// door: every pixel here is a function of three providers, and there is nothing
/// on screen to remember between visits.
///
/// **It watches three providers rather than one, and the split is the design
/// rather than an accident of what already existed.** [profileStatsProvider] is
/// a memoised read of the store, dropped by `GameActions` when a game moves
/// points or the best streak; [badgesProvider] and [followsProvider] are
/// `Notifier`s that push their own changes. So the badge shelf lights up the
/// instant a badge is earned and the 🐾 count moves the frame a Follow button is
/// tapped, while the two store-backed numbers refresh on the write that changed
/// them. All four are live; only the mechanism differs, and each is named at the
/// line that reads it.
///
/// **The prototype calls `checkBadges()` at the top of `renderProfile`
/// (`index.html:519`) and this does not.** There, opening the Profile is one of
/// the few things that ever asks whether a badge has been earned — which is why
/// its Zoo Keeper pops on a screen with no connection to the follow that won it.
/// Here `BadgeController` listens to the follow set itself and every game write
/// ends in a check, so by the time this screen is built the answer is already
/// known. A screen that awarded things as a side effect of being looked at would
/// also be a screen that cannot be built twice safely.
class MySpaceZooScreen extends ConsumerWidget {
  const MySpaceZooScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ProfileStats stats = ref.watch(profileStatsProvider);
    final BadgeState badges = ref.watch(badgesProvider);
    final int followCount = ref.watch(followsProvider).length;
    final BadgeGoal? goal = nextBadgeGoal(stats.points);

    return SafeArea(
      // The shell's own `bottomNavigationBar` already sits below this body, so
      // only the top status bar needs clearing — My Animals' note, same reason.
      bottom: false,
      child: CustomScrollView(
        slivers: <Widget>[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // `.h-title` (`index.html:529`). "My Space Zoo", not the nav's
                  // "Profile" — the nav names the tab, the page names the place.
                  Semantics(
                    header: true,
                    child: const Text(
                      'My Space Zoo',
                      style: TextStyle(
                        color: Palette.ink,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  // `.h-sub` (`index.html:529`).
                  const Text(
                    'Collect points and win animal badges! 🏅',
                    style: TextStyle(color: Palette.muted, fontSize: 13),
                  ),
                  // `.h-sub{margin-bottom:14px}` (`index.html:36`).
                  const SizedBox(height: 14),
                  _PointsCard(points: stats.points, goal: goal),
                  // `.stats3{margin-top:14px}` (`index.html:534`).
                  const SizedBox(height: 14),
                  _StatRow(
                    badgeCount: badges.earnedCount,
                    bestStreak: stats.bestStreak,
                    followCount: followCount,
                  ),
                  // `.sect{margin:16px 2px 8px}` (`index.html:120`).
                  const Padding(
                    padding: EdgeInsets.fromLTRB(2, 16, 2, 8),
                    child: _SectionLabel('Animal badges'),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            sliver: SliverToBoxAdapter(child: _BadgeShelf(earned: badges)),
          ),
          const SliverPadding(
            // `.sect{margin:16px 2px 8px}`-sized gap above, and the 24 below is
            // the page's old bottom pad moved down with the last thing on it.
            padding: EdgeInsets.fromLTRB(16, 16, 16, 24),
            sliver: SliverToBoxAdapter(child: _SettingsRow()),
          ),
        ],
      ),
    );
  }
}

/// The points hero and the bar beneath it (`.ptsCard`, `index.html:530-533`):
/// a star, the total, and either how far the next tier is or the line a child
/// sees once there are no tiers left.
class _PointsCard extends StatelessWidget {
  const _PointsCard({required this.points, required this.goal});

  final int points;

  /// The next unearned point tier, or null once all five are collected.
  final BadgeGoal? goal;

  @override
  Widget build(BuildContext context) {
    final BadgeGoal? goal = this.goal;

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: kFeaturedGradient,
        border: Border.fromBorderSide(BorderSide(color: Palette.line)),
        // `.ptsCard{border-radius:20px}` (`index.html:262`).
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
      child: Padding(
        // `.ptsCard{padding:18px}` (`index.html:262`).
        padding: const EdgeInsets.all(18),
        child: Column(
          children: <Widget>[
            // The star, the number, and the caption say one thing between them,
            // so they are announced as one thing. Read separately a screen
            // reader gives "star", "142", "points collected" — three
            // disconnected utterances for what is visually a single figure.
            Semantics(
              label: '$points points collected',
              child: ExcludeSemantics(
                child: Column(
                  children: <Widget>[
                    // `font-size:34px` (`index.html:530`).
                    const Text('⭐', style: TextStyle(fontSize: 34, height: 1)),
                    const SizedBox(height: 4),
                    // `.ptsCard .pv` (`index.html:263`).
                    Text(
                      '$points',
                      style: const TextStyle(
                        color: Palette.accent2,
                        fontSize: 42,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'points collected',
                      style: TextStyle(color: Palette.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            if (goal != null) ...<Widget>[
              // `.xpbar{margin-top:12px}` (`index.html:532`).
              const SizedBox(height: 12),
              _XpBar(progress: goal.progress),
              // `margin-top:4px` on the line below (`index.html:532`).
              const SizedBox(height: 4),
              Text(
                // `${goal.need-goal.have} more points to unlock ${goal.name}`
                // (`index.html:532`) — the goal named with its emoji, which is
                // what `AnimalBadge.label` is for.
                '${goal.remaining} more points to unlock ${goal.badge.label}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Palette.muted, fontSize: 11),
              ),
            ] else ...<Widget>[
              const SizedBox(height: 10),
              // `index.html:533`. The bar is *replaced* rather than shown full:
              // a bar pinned at 100% forever reads as a thing still in progress,
              // and this is the one screen in the app that gets to say "done".
              const Text(
                '🏆 All animal badges collected — you’re a Space Zoo Master!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Palette.accent2,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The progress bar (`.xpbar`, `index.html:147-148`) — a 8px groove with a
/// gradient fill [progress] of the way across.
///
/// Decorative to a screen reader: the line under it already says "40 more points
/// to unlock 🦊 Fox Explorer", which is the same fact in words and a more useful
/// one than a percentage.
class _XpBar extends StatelessWidget {
  const _XpBar({required this.progress});

  /// 0…1, already clamped by [BadgeGoal.progress].
  final double progress;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        // `height:8px` under the page's global `box-sizing:border-box`
        // (`index.html:12`), so the 1px border is *inside* the 8 rather than
        // added to it — hence the border painted by the decoration and the
        // matching 1px inset below, rather than a `Container` border that would
        // grow this to 10.
        height: 8,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: _xpTrack,
            border: Border.fromBorderSide(BorderSide(color: Palette.line)),
            borderRadius: BorderRadius.all(Radius.circular(6)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(1),
            child: ClipRRect(
              // One less than the outer 6, so the fill's corners sit concentric
              // inside the groove rather than poking past it.
              borderRadius: const BorderRadius.all(Radius.circular(5)),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: progress,
                heightFactor: 1,
                child: const DecoratedBox(
                  decoration: BoxDecoration(gradient: _xpFill),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The three quick stats (`.stats3`, `index.html:534-538`): badges earned, best
/// answer streak, animals followed.
class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.badgeCount,
    required this.bestStreak,
    required this.followCount,
  });

  final int badgeCount;
  final int bestStreak;
  final int followCount;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        // Three equal columns of the same height (`grid-template-columns:1fr 1fr
        // 1fr`), so "BEST STREAK" wrapping to two lines does not leave the tiles
        // beside it short.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: _StatTile(
              value: '🏅 $badgeCount',
              caption: 'BADGES',
              semanticsLabel:
                  '$badgeCount ${badgeCount == 1 ? 'badge' : 'badges'} earned',
            ),
          ),
          // `.stats3{gap:9px}` (`index.html:270`).
          const SizedBox(width: 9),
          Expanded(
            child: _StatTile(
              value: '🔥 $bestStreak',
              caption: 'BEST STREAK',
              semanticsLabel: 'Best streak: $bestStreak',
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: _StatTile(
              value: '🐾 $followCount',
              caption: 'FOLLOWING',
              semanticsLabel:
                  'Following $followCount '
                  '${followCount == 1 ? 'animal' : 'animals'}',
            ),
          ),
        ],
      ),
    );
  }
}

/// One stat (`.stat`, `index.html:271-273`) — a big number with an emoji over a
/// small uppercase caption.
///
/// [semanticsLabel] carries the whole tile because the visual is two fragments
/// that only mean something together, and neither survives being read alone:
/// "paw prints 3" is not a sentence, and "FOLLOWING" without its number is not a
/// fact. The same trade `AnimalCard` makes.
class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.value,
    required this.caption,
    required this.semanticsLabel,
  });

  final String value;
  final String caption;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: Palette.card,
            border: Border.fromBorderSide(BorderSide(color: Palette.line)),
            borderRadius: BorderRadius.all(Radius.circular(14)),
          ),
          child: Padding(
            // `padding:12px 8px` (`index.html:271`).
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                // `.stat b{color:#fff}` — brighter than `Palette.ink` on
                // purpose, and the prototype's own literal: these three numbers
                // are the loudest thing on the row.
                Text(
                  value,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  caption,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Palette.muted,
                    fontSize: 10.5,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The ⚙️ Settings row at the foot of the Profile tab — the app's only entry
/// point to [SettingsScreen] (`specs/08-settings-about.md:39-43`).
///
/// **Here rather than in the bottom nav, and that is spec 08's rule for the
/// whole app**: the nav is fixed at four tabs, so the grown-up-facing screen
/// hangs off the tab whose content is already the least kid-facing. Bottom of
/// the Profile is also the one place a child scrolling for their badges will
/// never land on by accident — they stop at the shelf.
///
/// A [StatelessWidget] with a plain `Navigator.push` rather than anything
/// routed: [SettingsScreen] has no arguments, no result, and one caller. Pushing
/// over the whole shell — nav bar included — is deliberate and is what makes it
/// a screen rather than a fifth tab; the `‹ Back` pill is the only way out, so
/// there is no state to hold about how it was opened.
///
/// **Deliberately not scaled by 🧸 Little Kids mode — the one control where that
/// choice actually changes a pixel.** Of the app's screen-local controls this is
/// the only one whose [kMinTapTarget] floor genuinely binds: it measures exactly
/// 48dp, so the multiplier would take it to 60 rather than being the no-op it is
/// for the nav, the toggle rows and the game cards. It is still the wrong thing
/// to do here. 🧸 mode exists to make the controls a *child* drives easier to
/// hit, and the paragraph above places this row precisely where a child will
/// *not* land on it by accident; enlarging the grown-up door by a quarter in the
/// mode built for four-year-olds argues against its own placement. 48dp remains
/// the product commitment `specs/08-settings-about.md:82` asks for, and this row
/// meets it. Pinned in `test/a11y/one_off_controls_test.dart`.
class _SettingsRow extends StatelessWidget {
  const _SettingsRow();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      // The visible label is already the whole fact, so this repeats it rather
      // than embellishing — but it is set explicitly so the ⚙️ and the ›, both
      // excluded below, cannot creep back into the announcement as "gear
      // Settings greater-than".
      label: 'Settings',
      child: Material(
        color: Palette.card,
        shape: const RoundedRectangleBorder(
          // The badge tiles' radius (`.zb`, `index.html:276`) — this row sits
          // directly beneath the shelf and reads as one more card on it.
          borderRadius: BorderRadius.all(Radius.circular(14)),
          side: BorderSide(color: Palette.line),
        ),
        child: InkWell(
          borderRadius: const BorderRadius.all(Radius.circular(14)),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (BuildContext context) => const SettingsScreen(),
            ),
          ),
          child: ExcludeSemantics(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: kMinTapTarget),
              child: const Padding(
                // `.zb{padding:11px}` (`index.html:276`), widened to 13 so the
                // row's single line of text sits centred in its 48.
                padding: EdgeInsets.symmetric(horizontal: 11, vertical: 13),
                child: Row(
                  children: <Widget>[
                    Text('⚙️', style: TextStyle(fontSize: 18, height: 1)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Settings',
                        style: TextStyle(
                          color: Palette.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                    ),
                    // The affordance that says this row opens something rather
                    // than toggling it — the one thing the label alone cannot
                    // say. Muted, so it points without competing.
                    Text(
                      '›',
                      style: TextStyle(
                        color: Palette.muted,
                        fontSize: 18,
                        height: 1,
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

/// A `.sect` heading (`index.html:120`) — small, spaced-out, uppercase.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        // `text-transform:uppercase` is a *display* transform in CSS: the
        // document still says "Animal badges", and that is what a screen reader
        // announces. Upper-casing the string itself would make it announce
        // "A-N-I-M-A-L" in some readers, so the cased text is passed in and only
        // the painted glyphs are shouted.
        text.toUpperCase(),
        semanticsLabel: text,
        style: const TextStyle(
          color: Palette.muted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

/// The badge shelf (`.zbadges`, `index.html:539`) — all nine badges in
/// [kBadges]' order, two to a row, earned ones lit and the rest dimmed.
///
/// **Every badge is shown, including the ones a child has not earned**, and
/// that is the collection meta-game rather than a listing: a locked tile is an
/// invitation that says exactly what to do ("Get 5 correct in a row"). A shelf
/// of only what you have is a receipt.
///
/// Laid out as rows of two inside an [IntrinsicHeight] rather than as a
/// [SliverGrid], because the tiles' heights are set by text that wraps: "Score
/// 8/8 in Animal Match" takes two lines in a half-width column on a small phone
/// where "Earn 50 points" takes one. A grid wants a height decided before the
/// text is measured — an aspect ratio or a `mainAxisExtent` — and every value
/// for it is either an overflow on a narrow screen or a gap on a wide one. Rows
/// measure, then stretch both tiles to the taller of the pair.
class _BadgeShelf extends StatelessWidget {
  const _BadgeShelf({required this.earned});

  final BadgeState earned;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        for (int i = 0; i < kBadges.length; i += 2)
          Padding(
            // `.zbadges{gap:9px}` (`index.html:276`) — between rows, so none
            // after the last.
            padding: EdgeInsets.only(bottom: i + 2 < kBadges.length ? 9 : 0),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(
                    child: _BadgeTile(badge: kBadges[i], state: earned),
                  ),
                  const SizedBox(width: 9),
                  // The ninth badge is alone on the last row and keeps its
                  // half-width, exactly as a two-column CSS grid leaves it —
                  // stretching it across would make Perfect Match look like a
                  // different kind of thing from the eight above it.
                  Expanded(
                    child: i + 1 < kBadges.length
                        ? _BadgeTile(badge: kBadges[i + 1], state: earned)
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// One badge on the shelf (`.zb`, `index.html:523`) — its face, its name, and
/// how it is earned, at full strength or at `.4` opacity.
class _BadgeTile extends StatelessWidget {
  const _BadgeTile({required this.badge, required this.state});

  final AnimalBadge badge;
  final BadgeState state;

  @override
  Widget build(BuildContext context) {
    final bool isEarned = state.isEarned(badge.id);

    return Semantics(
      // The dimming is the *only* thing that distinguishes the two states
      // visually, and opacity is invisible to a screen reader — so without this
      // an unearned badge would be announced exactly like a won one. Worded
      // "not earned yet" rather than "locked" because a locked thing sounds
      // withheld and this one is simply ahead of you (`CLAUDE.md:63`).
      label:
          '${badge.title}, ${isEarned ? 'earned' : 'not earned yet'}. '
          '${badge.description}',
      child: ExcludeSemantics(
        child: Opacity(
          // `.zb.lock{opacity:.4}` (`index.html:277`).
          opacity: isEarned ? 1 : 0.4,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: Palette.card,
              border: Border.fromBorderSide(BorderSide(color: Palette.line)),
              borderRadius: BorderRadius.all(Radius.circular(14)),
            ),
            child: Padding(
              // `.zb{padding:11px}` (`index.html:276`).
              padding: const EdgeInsets.all(11),
              child: Row(
                children: <Widget>[
                  // `.zb .e{font-size:23px;flex:none}` (`index.html:278`).
                  Text(
                    badge.emoji,
                    style: const TextStyle(fontSize: 23, height: 1),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        // `.zb .zt` (`index.html:278`).
                        Text(
                          badge.title,
                          style: const TextStyle(
                            color: Palette.ink,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                        // `.zb .zd` (`index.html:278`) — shown on earned tiles
                        // too, as the prototype does: it is how the badge was
                        // won as much as how it is won.
                        Text(
                          badge.description,
                          style: const TextStyle(
                            color: Palette.muted,
                            fontSize: 10.5,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
