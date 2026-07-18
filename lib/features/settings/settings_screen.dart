import 'package:flutter/material.dart';
import 'package:rockimals/core/theme/palette.dart';

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
/// **The body is deliberately empty in this commit.** This item is scoped to the
/// entry point and the frame; the three toggles (🔊 Sound, 🐢 Calm motion, 🧸
/// Little Kids mode) and the About block are each their own plan item and each
/// fills the body column in turn. No "coming soon" placeholder stands in —
/// the shell's `_TabStub` was exactly that and was deleted the moment the last
/// tab landed, so inviting a second one back would be re-learning the same
/// lesson. An empty grown-up screen inside an unreleased app costs a child
/// nothing; a placeholder costs the next three items a deletion each.
///
/// Chrome is the prototype's `.obar` + `.obody` (`index.html:92-95`, `322-324`)
/// — the flat back-bar over a scrolling body that the detail screen, the Play
/// hub, and the game framework all wear — rather than a Material [AppBar], which
/// would be the only Material-shaped screen in the app.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Palette.pageBackground,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Obar(title: 'Settings'),
          Expanded(
            child: SingleChildScrollView(
              // `.obody{padding:16px 16px 30px}` (`index.html:95`).
              padding: EdgeInsets.fromLTRB(16, 16, 16, 30),
              // The three toggles and the About block land in this column, in
              // spec order (`specs/08-settings-about.md:45-65`). It is childless
              // rather than holding a placeholder — see the class doc.
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch),
            ),
          ),
        ],
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
