import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rockimals/core/theme/palette.dart';
import 'package:rockimals/features/games/games_providers.dart';
import 'package:rockimals/features/settings/about_block.dart';
import 'package:rockimals/features/settings/calm_motion.dart';
import 'package:rockimals/features/settings/little_kids_mode.dart';

/// The Settings screen — the app's one home for its grown-up-facing toggles and
/// its NASA attribution (`specs/08-settings-about.md`).
///
/// **It is a pushed route, not a fifth nav tab**, and that is the one rule spec
/// 08 pins for the whole app (`specs/08-settings-about.md:40-42`): the nav is
/// fixed at four — Radar / Sky / Watchlist / Profile — and anything that wants a
/// home in it later has to displace something. `app_shell.dart` repeats the rule
/// at the list that would otherwise grow; the entry point is a row at the bottom
/// of the Profile tab, next door in `my_space_zoo_screen.dart`.
///
/// **The body filled one item at a time, in spec order, and is now complete.**
/// 🐢 Calm motion landed first, then 🔊 Sound above it, then the [AboutBlock] at
/// the foot, and finally 🧸 Little Kids mode *between* them — below Calm motion,
/// per spec 08's own list (`:45-53`). Nothing ever stood in for a row that had
/// not landed: the shell's `_TabStub` was exactly such a placeholder and was
/// deleted the moment the last tab arrived, so inviting a second one back would
/// have been re-learning the same lesson at the same cost.
///
/// **Nothing on this screen may be an outbound link** (`:64-65`); the rule and
/// the tests that hold it live on [AboutBlock], which is where the only text a
/// link would plausibly attach to sits.
///
/// Chrome is the prototype's `.obar` + `.obody` (`index.html:92-95`, `322-324`)
/// — the flat back-bar over a scrolling body that the detail screen, the Play
/// hub, and the game framework all wear — rather than a Material [AppBar], which
/// would be the only Material-shaped screen in the app.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Palette.pageBackground,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _Obar(title: 'Settings'),
          Expanded(
            child: SingleChildScrollView(
              // `.obody{padding:16px 16px 30px}` (`index.html:95`).
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
              // The toggles and the About block land in this column, in spec
              // order (`specs/08-settings-about.md:45-65`) — so 🧸 Little Kids
              // mode inserts *below* Calm motion and the About block after it.
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _ToggleRow(
                    // "🔊 Sound" verbatim (`specs/08-settings-about.md:46`).
                    // **A mirror, not a second setting**: this row and the Play
                    // hub's 🔊/🔇 button read and write the one `soundOn` key
                    // through [soundOnProvider], so neither owns it and the two
                    // cannot disagree — there is no second copy of the value to
                    // drift. The hub's button stays where it is, next to the
                    // games (`specs/08-settings-about.md:33-35`).
                    emoji: '🔊',
                    label: 'Sound',
                    hint: 'Plays happy little sounds in the games and when you '
                        'win a badge.',
                    value: ref.watch(soundOnProvider),
                    // Flips through `toggle()` and discards the row's `next`.
                    // [SoundOnNotifier] exposes no setter, and asking for one
                    // would widen the notifier's API for no gain: `toggle()`
                    // reads the *live* state, so a tap lands on whatever the
                    // value is at that instant rather than on whatever it was
                    // when this frame was built.
                    onChanged: (bool _) =>
                        ref.read(soundOnProvider.notifier).toggle(),
                  ),
                  // `.acard{…margin-bottom:10px}` (`index.html:65`) — the gap
                  // the prototype puts between stacked rows.
                  const SizedBox(height: 10),
                  _ToggleRow(
                    // "🐢 Calm motion" verbatim (`specs/08-settings-about.md:47`).
                    // The phrase "reduced motion" is the key's name and the OS
                    // flag's name and appears nowhere a child can read it.
                    emoji: '🐢',
                    label: 'Calm motion',
                    // Written for the grown-up who will actually flip this,
                    // in the kid-safe register the whole screen keeps
                    // (`specs/08-settings-about.md:67-69`) — it says what
                    // changes, not what an accessibility flag is.
                    hint: 'Slows the radar down and keeps the animals calmer.',
                    value: calmMotionOf(context, ref),
                    onChanged: (bool next) =>
                        ref.read(reducedMotionProvider.notifier).choose(next),
                  ),
                  const SizedBox(height: 10),
                  _ToggleRow(
                    // "🧸 Little Kids mode" verbatim
                    // (`specs/08-settings-about.md:51`).
                    emoji: '🧸',
                    label: 'Little Kids mode',
                    // **The hint says it is not here yet, and that is the
                    // decision this row turns on.** Spec 08 requires the toggle
                    // to ship *visible* and persisted while allowing its body to
                    // be a no-op (`:51-53`), so for one release a grown-up can
                    // flip a switch that changes nothing they can see. Copy
                    // describing the finished feature in the present tense would
                    // make that read as a broken app — the one impression a kids
                    // app can least afford — and copy describing nothing would
                    // leave the row meaningless. Naming what is coming, and
                    // saying plainly that it is coming, is the only version that
                    // is true on the day it ships. The three things listed are
                    // `specs/06-title-polish-safety.md:26`'s own list, in the
                    // order a grown-up would notice them.
                    // **Drop the last four words when v1.1 lands** — see
                    // `little_kids_mode.dart`, and the plan item that owns it.
                    hint: 'Read-aloud names, bigger buttons and simpler games — '
                        'coming soon.',
                    value: ref.watch(littleKidsModeProvider),
                    // `choose(next)` rather than the 🔊 row's `toggle()`: this
                    // notifier has no "unset" state to flip relative to, so the
                    // row's own `next` is the whole answer.
                    onChanged: (bool next) =>
                        ref.read(littleKidsModeProvider.notifier).choose(next),
                  ),
                  // A wider gap than the 10px between stacked rows: this is a
                  // change of subject, from switches a grown-up flips to
                  // statements they read.
                  const SizedBox(height: 22),
                  const AboutBlock(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One settings row: an emoji, a label, a line of explanation, and a [Switch].
///
/// **Built for three rows before there were two, and all three arrived without
/// touching it.** 🔊 Sound reused it whole for the cost of five lines in the
/// column above; 🧸 Little Kids mode was again the same row with different
/// words. What that bought is that the ≥48dp target and the semantics below were
/// decided once instead of three times, in three diffs, by three agents.
///
/// **The whole row is the target, not just the switch.** A [Switch] is ~40dp of
/// hittable box inside a 48dp one, and it sits at the far edge of the screen; a
/// child aiming at the words would otherwise hit nothing at all. So the tap
/// falls through to the same [onChanged], and the [Switch] itself is handed the
/// callback too so that a *drag* across it still works.
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.emoji,
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  final String emoji;
  final String label;
  final String hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// The Material/HIG minimum, and this screen's stated bar
  /// (`specs/08-settings-about.md:82`).
  static const double _minTarget = 48;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      // The row speaks as one control. Without this, a screen reader walks an
      // emoji, two strings and an unlabelled switch and never says which
      // setting the switch belongs to.
      label: '$label. $hint',
      child: ExcludeSemantics(
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () => onChanged(!value),
            borderRadius: const BorderRadius.all(Radius.circular(14)),
            child: Container(
              constraints: const BoxConstraints(minHeight: _minTarget),
              decoration: const BoxDecoration(
                color: Palette.card,
                borderRadius: BorderRadius.all(Radius.circular(14)),
                border: Border.fromBorderSide(BorderSide(color: Palette.line)),
              ),
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              child: Row(
                children: <Widget>[
                  Text(emoji, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          label,
                          style: const TextStyle(
                            color: Palette.ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hint,
                          style: const TextStyle(
                            color: Palette.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Switch(
                    value: value,
                    onChanged: onChanged,
                    activeThumbColor: Palette.ink,
                    activeTrackColor: Palette.accent,
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

/// The overlay back-bar (`.obar`, `index.html:92-94`): a card-pill back button
/// and a plain title over a bottom rule.
///
/// **The fourth copy**, after `detail_screen.dart`, `games_hub.dart`, and
/// `game_shell.dart`. It stays local for the reason the third one did: the
/// extraction is its own plan item across three completed, tested modules, and
/// folding it into a new screen's diff would bury a cross-feature move. The
/// clone is faithful, so nothing drifts before that item lands.
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
///
/// **One deliberate difference from the three clones this copies**: the tap
/// target is 48dp tall while the painted pill stays the prototype's ~30dp. The
/// item that owns this screen requires every target here to be ≥48dp, and the
/// pill's own `8px` vertical padding around 14px text cannot reach that without
/// making it visibly heavier than the 16px title beside it. So the [InkWell]
/// sits *outside* the pill and is stretched to 48 — the same trick
/// [IconButton] plays around a 24dp glyph — which grows the region a thumb has
/// to hit without touching a single painted pixel.
///
/// The other three pills are ~30dp targets and are the accessibility-audit
/// item's problem, not this screen's. When the `.obar` extraction item folds
/// all four into one widget it should take *this* version: it is the only one
/// that meets the guideline, and it is visually identical to the ones it
/// replaces.
class _BackButton extends StatelessWidget {
  const _BackButton();

  /// The Material/HIG minimum, and this item's stated bar.
  static const double _minTarget = 48;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      // The three sibling pills carry the same label and the radar and hub
      // route tests tap them by it — there is no Material `BackButton` here to
      // find. Kept identical so the extraction is a rename, not a re-test.
      label: 'Back',
      child: InkWell(
        onTap: () => Navigator.of(context).maybePop(),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _minTarget),
          child: const Center(
            // The row is `MainAxisSize.min` so the target is only as wide as
            // the pill; a 48dp-wide-minimum here would leave dead space beside
            // a pill that is already wider than 48.
            widthFactor: 1,
            child: _BackPill(),
          ),
        ),
      ),
    );
  }
}

/// The painted pill itself, split out so [_BackButton] can wrap it in a bigger
/// tap target without the ink and the border disagreeing about their bounds.
class _BackPill extends StatelessWidget {
  const _BackPill();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        color: Palette.card,
        borderRadius: BorderRadius.all(Radius.circular(11)),
        border: Border.fromBorderSide(BorderSide(color: Palette.line)),
      ),
      child: Padding(
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
    );
  }
}
