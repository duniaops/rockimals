import 'package:flutter/painting.dart';

/// The prototype's palette — its `:root` custom properties (`index.html:9-10`),
/// ported once so they stop being re-declared per screen.
///
/// **Why this is a port of a real artifact and not a speculative helper.** This
/// plan has twice refused to add a constant nothing calls yet (`usingDemoKey`,
/// `isCloseFlyby`), and that rule still holds — but it is about *inventing* an
/// abstraction the prototype does not have. A `:root` block is the opposite:
/// the prototype already decided these eleven colours are the shared, named,
/// reused ones, and gave each a name. Porting it whole is the same call
/// `kNamePool` and `kFallbackAsteroids` made — the table is the prototype's, so
/// it comes across intact rather than sampled down to today's call sites.
///
/// **What is deliberately *not* here: one-off literals.** Most colours in
/// `index.html` are not variables. The radar's ring strokes, Earth's gradient
/// stops, and the spinner's track each appear exactly once and stay local to the
/// widget that draws them; hoisting them would invent a relationship the
/// prototype does not have (see the note in `radar_painter.dart`). The test for
/// membership here is that the prototype named it, not that two Dart files
/// happen to want it.
///
/// **That rule has been held once against a real candidate**, which is worth
/// recording so the next one is decided the same way. The featured-card gradient
/// is restated five times in `index.html` and wanted by three separate features,
/// and it still did not come in here — because the prototype names it nothing,
/// and admitting it would have quietly rewritten the test above into "enough
/// files want it". It sits beside this file instead, as `kFeaturedGradient` in
/// `featured_gradient.dart`: same directory, own library, membership rule
/// untouched.
///
/// **Two of the eleven are dead and are not ported**, per the plan's
/// decision 1 ("do not port the prototype's dead state"): `--navy` (`#0B1F3A`)
/// and `--card2` (`#0f2242`) are declared on lines 9-10 and then referenced
/// nowhere — not by `var()`, not by a raw hex, not in the JS, not in
/// `title.html`. Verified rather than assumed; every other variable below
/// carries its live use count for the same reason. If a later screen genuinely
/// needs a second card shade, `--card2` can be resurrected *then*, with a
/// consumer to justify it.
///
/// The `ColorScheme` mapping proper is still open — see `main.dart`, which pins
/// only the two entries the prototype answers outright.
abstract final class Palette {
  /// `--accent` `#E8571F` — 19 uses. The prototype's one interactive colour:
  /// every selected chip, the primary buttons, the play control, the spinner's
  /// lit quarter. Where the app says "this does something", it is this orange.
  static const Color accent = Color(0xFFE8571F);

  /// `--accent2` `#ff7a45` — 21 uses. The lighter orange, for text *on* dark
  /// rather than fills: links, the selected nav label, the JPL link.
  static const Color accent2 = Color(0xFFFF7A45);

  /// `--good` `#31c48d` — 8 uses. Right answers only.
  static const Color good = Color(0xFF31C48D);

  /// `--bad` `#f05252` — 6 uses. Wrong answers only — and note `CLAUDE.md:63`
  /// still governs the *copy* that wears it: a wrong answer is encouraging,
  /// whatever colour it is.
  static const Color bad = Color(0xFFF05252);

  /// `--ink` `#eaf1fb` — 6 uses. Body text, set on `body` and inherited.
  static const Color ink = Color(0xFFEAF1FB);

  /// `--muted` `#93a8ca` — 34 uses, the most-used colour in the prototype and
  /// the one that had drifted into three separate Dart files before this
  /// existed (`app_shell.dart`, `loading_screen.dart`, `radar_painter.dart`).
  /// Secondary text everywhere: the idle nav label, "Contacting NASA…", the
  /// radar's ring labels.
  static const Color muted = Color(0xFF93A8CA);

  /// `--card` `#132a4d` — 15 uses as `var(--card)`, plus 5 more as the raw
  /// `rgba(19,42,77,…)` at various alphas (the radar chips, the home strip).
  /// The surface every panel is drawn on.
  static const Color card = Color(0xFF132A4D);

  /// `--line` `#24406e` — 28 uses. The 1px border on essentially every card,
  /// chip, and button in the app.
  static const Color line = Color(0xFF24406E);

  /// `--line2` `#1c3457` — 3 uses. The darker rule, for chrome that sits
  /// *outside* the content: the nav's top border, the radar's bottom bar.
  static const Color line2 = Color(0xFF1C3457);

  /// `body{background:#070f1f}` (`index.html:15`) — 3 uses. Not a `:root`
  /// variable, but named here because it is the colour behind the entire app
  /// and the prototype restates it by hand each time it needs it (the loading
  /// overlay does exactly that at `index.html:165`).
  ///
  /// Flat. The body also lays a starfield radial-gradient over it
  /// (`index.html:14-16`); that is scenery and belongs to whatever ports the
  /// starfield, not here.
  static const Color pageBackground = Color(0xFF070F1F);

  /// `#1a0d05` — 5 uses, always as the text or glyph sitting *on* [accent]
  /// (`.rchip.on`, `.rplay`, the primary buttons). Not a variable either, but it
  /// is the prototype's own answer to "what goes on the orange", which is a
  /// question `ColorScheme.onPrimary` asks and would otherwise have to guess.
  static const Color onAccent = Color(0xFF1A0D05);
}
