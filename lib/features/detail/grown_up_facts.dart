import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rockimals/core/a11y/tap_target.dart';
import 'package:rockimals/core/theme/palette.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:url_launcher/url_launcher.dart';

/// Signature for opening an external URL. Injected into [GrownUpFacts] so tests
/// observe the launch without a real platform channel; production uses
/// [launchExternal].
typedef ExternalLauncher = Future<bool> Function(Uri url);

/// The one place this app leaves the app — opens [url] in the system browser
/// (`target="_blank"`, `index.html:611`). `externalApplication` is the
/// kids-safety requirement (`CLAUDE.md:25`, spec 06): the NASA/JPL page opens
/// *outside* Rockimals, never in an in-app web view a child could wander from.
Future<bool> launchExternal(Uri url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);

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
/// (`CLAUDE.md:25`, spec 06:31-33). A tap now raises [showParentGate] — a small
/// arithmetic prompt a child who cannot yet add cannot pass — and the browser
/// only opens on a correct answer. Task 06 ("Harden the parent gate") promotes
/// this into the shared, hardened gate; this is the simple task-03 version it
/// starts from.
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

  Future<void> _openJpl(BuildContext context) async {
    final ParentGateChallenge c = challenge ?? ParentGateChallenge.random();
    final bool passed = await showParentGate(context, challenge: c);
    // `passed` is the only thing that reaches past the gate; `context` is not
    // touched again, so no `mounted` guard is needed after the await.
    if (!passed) {
      return;
    }
    await launcher(Uri.parse(asteroid.jpl));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      // `.panel{background:var(--card);border:1px solid var(--line);
      // border-radius:16px;padding:14px}` (`index.html:105`), `text-align:center`
      // (`index.html:608`).
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        color: Palette.card,
        borderRadius: BorderRadius.all(Radius.circular(16)),
        border: Border.fromBorderSide(BorderSide(color: Palette.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
          const SizedBox(height: 6),
          _JplLink(onTap: () => _openJpl(context)),
        ],
      ),
    );
  }
}

/// The `Look it up on NASA/JPL ↗` link (`a.jpl`, `index.html:611`, `163`) — the
/// lighter [Palette.accent2] "text on dark" orange the prototype reserves for
/// links. Tapping raises the parent gate (via [GrownUpFacts._openJpl]); the ↗
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

/// A simple arithmetic parent gate (spec 03 §26-27, spec 06:31-33). Two small
/// addends: a child who cannot yet add cannot solve it, while a grown-up passes
/// in seconds — the "ask a grown-up" bar the kids-safety guardrail requires
/// before any external link.
@immutable
class ParentGateChallenge {
  const ParentGateChallenge(this.a, this.b);

  /// A fresh challenge with both addends in `2..9`, so the sum needs real
  /// addition (never a trivial `+0`/`+1`). [rng] is injectable for
  /// deterministic tests; production passes none and gets a new [Random].
  factory ParentGateChallenge.random([Random? rng]) {
    final Random r = rng ?? Random();
    return ParentGateChallenge(2 + r.nextInt(8), 2 + r.nextInt(8));
  }

  final int a;
  final int b;

  int get answer => a + b;

  String get prompt => 'What is $a + $b?';

  /// True when [input] parses to [answer]. Trims surrounding whitespace; any
  /// non-numeric or empty input is simply wrong (never an exception).
  bool accepts(String input) => int.tryParse(input.trim()) == answer;
}

/// Shows the parent gate and resolves `true` only when [challenge] is answered
/// correctly; Cancel or a barrier dismiss resolves `false`. Kept gentle
/// (`CLAUDE.md:63`) — a wrong answer nudges "ask a grown-up", never scolds.
Future<bool> showParentGate(
  BuildContext context, {
  required ParentGateChallenge challenge,
}) async {
  final bool? passed = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => _ParentGateDialog(challenge: challenge),
  );
  return passed ?? false;
}

class _ParentGateDialog extends StatefulWidget {
  const _ParentGateDialog({required this.challenge});

  final ParentGateChallenge challenge;

  @override
  State<_ParentGateDialog> createState() => _ParentGateDialogState();
}

class _ParentGateDialogState extends State<_ParentGateDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _wrong = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.challenge.accepts(_controller.text)) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _wrong = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Palette.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: Palette.line),
      ),
      title: const Text(
        'Ask a grown-up 🔭',
        style: TextStyle(
          color: Palette.ink,
          fontSize: 17,
          fontWeight: FontWeight.w800,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'This link goes to the grown-up science pages. '
            'To open it, solve:',
            style: TextStyle(color: Palette.muted, fontSize: 13, height: 1.3),
          ),
          const SizedBox(height: 10),
          Text(
            widget.challenge.prompt,
            style: const TextStyle(
              color: Palette.ink,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            onSubmitted: (_) => _submit(),
            style: const TextStyle(color: Palette.ink),
            decoration: InputDecoration(
              hintText: 'Type the answer',
              hintStyle: const TextStyle(color: Palette.muted),
              // Gentle, never a scold (`CLAUDE.md:63`).
              errorText:
                  _wrong ? 'Not quite — ask a grown-up to help!' : null,
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel', style: TextStyle(color: Palette.muted)),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text(
            'Open ↗',
            style: TextStyle(color: Palette.accent2, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
