import 'package:flutter/material.dart';
import 'package:rockimals/core/chrome/panel.dart';
import 'package:rockimals/core/config/app_version.dart';
import 'package:rockimals/core/theme/palette.dart';

/// The About block at the foot of Settings (`specs/08-settings-about.md:55-65`)
/// — NASA's attribution, the "unofficial" disclaimer, the privacy line, and the
/// version.
///
/// **Three of these four lines are obligations, not features.** The attribution
/// is a condition of using NeoWs' data at all; the disclaimer is what keeps the
/// app from reading as NASA's own; the privacy line is `CLAUDE.md:23`'s
/// no-accounts/no-ads/no-tracking guardrail said *in the app*, where a parent
/// can find it, rather than only ticked on a release checklist. All three are
/// rendered verbatim from the spec — this is copy to port, not to improve.
///
/// **Zero outbound links, and that is the whole rule for this screen**
/// (`specs/08-settings-about.md:64-65`). The one place Rockimals leaves the app
/// is the JPL link in `grown_up_facts.dart`, behind the parent gate. A child can
/// reach *this* screen unaided, so nothing here may be tappable — not the NASA
/// name, not a privacy policy, not a support address. `about_block_test.dart`
/// holds that line two ways: it greps this feature's source for a `url_launcher`
/// import, and it walks the rendered tree for anything that takes a tap.
///
/// **The disclaimer is deliberately the loudest line here** (`:59` — *"must be
/// legible, not fine print"*). It renders at [_bodySize] in [Palette.ink] at
/// semibold, one step above the two lines around it, while the version — the
/// only line here that genuinely is a footnote — is the one that gets
/// [Palette.muted] and [_footnoteSize].
class AboutBlock extends StatelessWidget {
  const AboutBlock({super.key});

  /// `specs/08-settings-about.md:56-57`, verbatim. Named so the test asserting
  /// the string and the widget rendering it cannot drift apart while both
  /// still pass.
  static const String attribution =
      "Asteroid data from NASA's NeoWs (Near Earth Object Web Service).";

  /// `:58-59`, verbatim.
  static const String disclaimer =
      'Rockimals is an unofficial app. It is not affiliated with, endorsed by, '
      'or sponsored by NASA.';

  /// `:61-62`, verbatim — and the in-app statement of `CLAUDE.md:23`.
  static const String privacy =
      'Rockimals collects nothing about you. No accounts, no ads, no tracking.';

  /// The body size the disclaimer and the two lines beside it read at. 13px is
  /// the app's standing sub-heading size (`.h-sub`, `index.html:36`) — the
  /// smallest text elsewhere in Rockimals that is *meant* to be read rather
  /// than glanced at.
  static const double _bodySize = 13;

  /// Reserved for the version line alone. Everything else on this panel is a
  /// claim someone may need to act on.
  static const double _footnoteSize = 12;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Announced as a heading so a screen reader can jump the toggles and
        // land here, which is what a grown-up looking for the attribution is
        // doing. Matches `sky_screen.dart`'s "The Sky" treatment.
        Semantics(
          header: true,
          child: const Padding(
            padding: EdgeInsets.fromLTRB(2, 0, 2, 8),
            child: Text(
              'About',
              style: TextStyle(
                color: Palette.ink,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
          ),
        ),
        // The `.panel` surface (`index.html:105`) — the same one
        // `grown_up_facts.dart` wears, which is the other screen in the app
        // that talks to a grown-up, and now literally the same widget: it is
        // [Panel] in `core/chrome/`, which neither feature owns.
        //
        // Const the whole way down, and now including the surface itself:
        // every line here is a compile-time string, including the version, so
        // the panel is built once and rebuilt never. The [Container] this
        // replaced could not be const, so the card was the one part of this
        // block that rebuilt with its parent.
        const Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _AboutLine(emoji: '🛰️', text: attribution),
              SizedBox(height: 12),
              // No emoji, and not by omission: the two lines around it are
              // labelled topics a reader can skip, while this one is the
              // statement the panel exists to make. A glyph in front of it
              // would file it as one item in a list of three.
              Text(
                disclaimer,
                style: TextStyle(
                  color: Palette.ink,
                  fontSize: _bodySize,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
              SizedBox(height: 12),
              _AboutLine(emoji: '🔒', text: privacy),
              SizedBox(height: 14),
              // A hairline between the claims and the footnote — the same
              // `--line2` rule the back-bar uses (`index.html:92`).
              Divider(color: Palette.line2, height: 1, thickness: 1),
              SizedBox(height: 10),
              Text(
                AppVersion.display,
                style: TextStyle(
                  color: Palette.muted,
                  fontSize: _footnoteSize,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One emoji-led line of the About panel.
///
/// The emoji is excluded from semantics for the reason the Profile's Settings
/// row excludes its gear: read as authored, a screen reader says "satellite,
/// asteroid data from NASA's…", and the glyph is decoration that earns nothing
/// spoken aloud. The [Row] is `CrossAxisAlignment.start` so the glyph sits with
/// the *first* line of a paragraph that wraps to three on a narrow phone rather
/// than floating at its vertical centre.
class _AboutLine extends StatelessWidget {
  const _AboutLine({required this.emoji, required this.text});

  final String emoji;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ExcludeSemantics(
          child: Text(emoji, style: const TextStyle(fontSize: 15, height: 1.3)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Palette.ink,
              fontSize: AboutBlock._bodySize,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
