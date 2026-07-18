import 'package:flutter/material.dart';
import 'package:rockimals/core/a11y/tap_target.dart';
import 'package:rockimals/core/safety/parent_gate.dart';
import 'package:rockimals/core/theme/palette.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/features/detail/detail_panel.dart';

/// The grown-up facts panel (`.panel`, `index.html:608-612`) — the **only**
/// place the real NASA designation and the external NASA/JPL link appear
/// (`CLAUDE.md:71`, spec 03 §25-27). Everywhere else the app shows the friendly
/// "{First} the {Species}" name ([critter]); the raw designation stays here,
/// tucked under a parent gate, so no jargon and no outbound link reaches a child
/// in the main flow.
///
/// **The designation is rendered verbatim** — `asteroid.name` exactly as the
/// model holds it (plan decision, the numbered-asteroid item). The prototype
/// does the same (`esc(a.name)`, `index.html:610`). The alternative forms
/// (`433 Eros` vs `433 Eros (A898 PA)` for a numbered rock whose live name has
/// its parens stripped) were rejected: `name` is the `hashStr` seed, so deriving
/// a display form is a trap only if it ever edits `name` — and verbatim needs no
/// derived getter at all, so determinism is trivially untouched. On the offline
/// fallback set every name is already clean, so verbatim is also correct there.
///
/// **The parent gate is a deliberate addition, not a port.** The prototype's
/// link opens on a bare tap (`index.html:611`); a kids-first app must not
/// (`CLAUDE.md:25`, spec 06:31-33). The tap goes to [openExternalLink] instead,
/// which checks the URL, asks a grown-up, and only then opens the browser. This
/// panel deliberately owns **none** of that: the gate lives in
/// `core/safety/parent_gate.dart` precisely so that raising it is not something
/// a screen has to remember to do.
class GrownUpFacts extends StatelessWidget {
  const GrownUpFacts({
    super.key,
    required this.asteroid,
    this.launcher = launchExternal,
    this.challenge,
  });

  final Asteroid asteroid;

  /// How the JPL link opens. Defaults to the real [launchExternal]; tests inject
  /// a spy so the gate flow is exercised without a platform channel.
  final ExternalLauncher launcher;

  /// Test seam: a fixed gate challenge. Null in production, where each tap draws
  /// a fresh [ParentGateChallenge.random] so the arithmetic is not a memorised
  /// constant a child could learn by rote.
  final ParentGateChallenge? challenge;

  /// The JPL page for this rock, or null if the model's URL is not one the app
  /// may open ([isSafeExternalLink]).
  ///
  /// `tryParse` rather than `parse` because `jpl` is a string off the network
  /// (`asteroid.dart:75`) and a malformed one should cost this panel a link,
  /// not throw in the middle of a build.
  Uri? get _jplUri {
    final Uri? url = Uri.tryParse(asteroid.jpl);
    if (url == null || !isSafeExternalLink(url)) {
      return null;
    }
    return url;
  }

  @override
  Widget build(BuildContext context) {
    // The `.panel` shell (`index.html:105`) comes from [DetailPanel]; this is
    // the one panel on the screen the prototype gives **no** `h4`
    // (`index.html:608`) — its own first line is the introduction — so it
    // passes no heading. `text-align:center` (`index.html:608`) stays here,
    // per-line, because it is this panel's alone.
    return DetailPanel(
      children: <Widget>[
        // `🔭 Grown-up fact — its real space name is` — `font-size:12px;
        // color:var(--muted)` (`index.html:609`).
        const Text(
          '🔭 Grown-up fact — its real space name is',
          textAlign: TextAlign.center,
          style: TextStyle(color: Palette.muted, fontSize: 12, height: 1.3),
        ),
        // The real designation, verbatim — `font-weight:800;font-size:15px;
        // margin:3px 0 6px` (`index.html:610`).
        const SizedBox(height: 3),
        Text(
          asteroid.name,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Palette.ink,
            fontSize: 15,
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
        // No link at all when the URL is not openable, rather than a link
        // that swallows the tap. A grown-up who taps and gets nothing has no
        // way to tell that from a broken app.
        if (_jplUri case final Uri url) ...<Widget>[
          const SizedBox(height: 6),
          _JplLink(
            onTap: () => openExternalLink(
              context,
              url,
              launcher: launcher,
              challenge: challenge,
            ),
          ),
        ],
      ],
    );
  }
}

/// The `Look it up on NASA/JPL ↗` link (`a.jpl`, `index.html:611`, `163`) — the
/// lighter [Palette.accent2] "text on dark" orange the prototype reserves for
/// links. Tapping raises the parent gate (via [openExternalLink]); the ↗
/// glyph is excluded from semantics behind a spoken label, the pattern the
/// detail's `‹ Back` pill and the action buttons follow.
class _JplLink extends StatelessWidget {
  const _JplLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Look it up on NASA or JPL',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          // A text link, so there is no pill to keep small — the [TapTarget]
          // goes inside the ink and takes the row from 28dp to 48. This is the
          // one control in the app that must be *hard* for a child to hit by
          // accident, but that is the parent gate's job, not a small target's:
          // a link a grown-up cannot reliably tap is just a broken link.
          child: const TapTarget(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: ExcludeSemantics(
                child: Text(
                  'Look it up on NASA/JPL ↗',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Palette.accent2,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
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
