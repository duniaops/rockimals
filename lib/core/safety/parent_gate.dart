/// The parent gate, and the app's **only** way out of the app
/// (`CLAUDE.md:23-25`, `specs/06-title-polish-safety.md:31-33`, `:46`).
///
/// **Why this is a `core/` module and not a widget in `features/detail/`.** The
/// gate started life private to `grown_up_facts.dart`, next to the one link it
/// guarded. That put the safety property — *no outbound link without a
/// grown-up* — in the keeping of a call site: the gate was a thing a screen
/// could remember to raise, and therefore a thing the next screen could forget.
/// Here it is structural instead. [launchExternal] is the single `launchUrl`
/// call in the codebase and [openExternalLink] is the single caller of it, so
/// the gate is not *in front of* the exit, it **is** the exit. A feature that
/// wants to leave the app has exactly one function to call and that function
/// asks a grown-up first. `parent_gate_test.dart` pins the invariant by
/// grepping `lib/` for the `url_launcher` import and asserting this file is the
/// only hit.
///
/// The three checks a tap passes through, in order and each of them fail-closed:
///
///  1. [isSafeExternalLink] — the URL is `https` at a NASA host. This runs
///     *before* the gate, so a link that could never open never asks anyone to
///     solve anything.
///  2. [showParentGate] — the arithmetic prompt, capped at [kParentGateTries].
///  3. [launchExternal] — `LaunchMode.externalApplication`, so the page opens in
///     the system browser and never in an in-app web view a child could wander
///     from.
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rockimals/core/theme/palette.dart';
import 'package:url_launcher/url_launcher.dart';

/// Signature for opening an external URL. Injected into [openExternalLink] so
/// tests observe the launch without a real platform channel; production uses
/// [launchExternal].
typedef ExternalLauncher = Future<bool> Function(Uri url);

/// How many wrong answers one gate will take before it closes.
///
/// The cap is the difference between a prompt and a lock. The sums this gate
/// draws land in `11..18` (see [ParentGateChallenge.random]) — eight possible
/// answers, which an unlimited retry loop turns into a puzzle any determined
/// child solves by counting upwards. Three tries and a **fresh challenge on
/// every re-open** means guessing costs a re-open per three guesses and never
/// gets warmer, while a grown-up who fat-fingers the number is not locked out
/// of anything: the link is one tap away and the next gate is a new sum.
const int kParentGateTries = 3;

/// The one place this app leaves the app — opens [url] in the system browser
/// (`target="_blank"`, `index.html:611`). `externalApplication` is the
/// kids-safety requirement (`CLAUDE.md:25`, spec 06:31-33): the NASA/JPL page
/// opens *outside* Rockimals, never in an in-app web view.
///
/// Call [openExternalLink] instead — this is its launch step, exposed only so
/// it can be named as the default and swapped in tests.
Future<bool> launchExternal(Uri url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);

/// Whether [url] is a link this app is allowed to hand to the operating system.
///
/// **Two rules, and both of them exist because this URL is not ours.** The live
/// value is NeoWs' `nasa_jpl_url` field (`asteroid.dart:75`) — a string off the
/// network, or off a disk cache written from the network — and it reaches
/// [launchExternal] without a human ever reading it.
///
///  * **`https` only.** A scheme is an instruction to the OS about *which app*
///    to open, so an unchecked one is the whole attack: `market://`, `intent://`
///    and a registered custom scheme all leave Rockimals for somewhere nobody
///    reviewed, and plain `http` sends a child's traffic in the clear.
///  * **A NASA host.** Spec 06:46 does not say "the only external link is
///    parent-gated", it says the only external link **is the NASA/JPL one**.
///    That is a claim about *where* the app can go, and this is the line that
///    makes it true of the code rather than merely true of today's feed.
///
/// The suffix test is `.nasa.gov` with its leading dot, so `evilnasa.gov` and
/// `nasa.gov.example.com` both fail; `Uri` lower-cases the host on parse, so
/// there is no case to fold here.
///
/// A rejected link is not a dead tap: [GrownUpFacts] hides the link entirely
/// when this returns false, so if NASA ever moves off `nasa.gov` the failure
/// shows up as a missing link rather than a button that does nothing.
bool isSafeExternalLink(Uri url) {
  if (url.scheme != 'https') {
    return false;
  }
  final String host = url.host;
  return host == 'nasa.gov' || host.endsWith('.nasa.gov');
}

/// Asks a grown-up, then opens [url] in the system browser. Resolves `true`
/// only if the page was actually opened.
///
/// The whole outbound path in one function, so there is no order of operations
/// for a caller to get wrong. Every early return is a `false`: an unsafe URL
/// never raises the gate, and a failed gate never reaches the launcher.
///
/// [launcher] and [challenge] are test seams. In production the challenge is
/// null, so every tap draws a fresh [ParentGateChallenge.random] — a fixed sum
/// would be learnable by rote, which is exactly the gate a five-year-old beats.
Future<bool> openExternalLink(
  BuildContext context,
  Uri url, {
  ExternalLauncher launcher = launchExternal,
  ParentGateChallenge? challenge,
}) async {
  if (!isSafeExternalLink(url)) {
    return false;
  }
  final bool passed = await showParentGate(
    context,
    challenge: challenge ?? ParentGateChallenge.random(),
  );
  // `passed` is the only thing that reaches past the gate; `context` is not
  // touched again, so no `mounted` guard is needed after the await.
  if (!passed) {
    return false;
  }
  return launcher(url);
}

/// A simple arithmetic parent gate (spec 03 §26-27, spec 06:31-33) — the
/// "ask a grown-up" bar the kids-safety guardrail requires before any external
/// link.
@immutable
class ParentGateChallenge {
  const ParentGateChallenge(this.a, this.b);

  /// A fresh challenge whose addends are each in `3..9` **and whose sum is at
  /// least [_minSum]**, so answering it needs addition across ten.
  ///
  /// Both bounds are the gate's difficulty, and they are set against a reader
  /// who is four or five. Counting on fingers gets a child to sums of ten;
  /// crossing ten is the skill that arrives with school, which is roughly the
  /// age this gate stops needing to hold. The old `2..9` range let through
  /// `2 + 3`, which is not a gate at all.
  ///
  /// [rng] is injectable for deterministic tests; production passes none.
  factory ParentGateChallenge.random([Random? rng]) {
    final Random r = rng ?? Random();
    final int a = _minAddend + r.nextInt(_maxAddend - _minAddend + 1);
    // Draw `b` from whatever still clears `_minSum`, rather than re-rolling
    // until the pair does — a loop here would be unbounded on a hostile [rng]
    // and this is arithmetic either way.
    final int lowB = max(_minAddend, _minSum - a);
    final int b = lowB + r.nextInt(_maxAddend - lowB + 1);
    return ParentGateChallenge(a, b);
  }

  static const int _minAddend = 3;
  static const int _maxAddend = 9;
  static const int _minSum = 11;

  final int a;
  final int b;

  int get answer => a + b;

  /// The question, with both numbers **spelled out**: `What is seven plus
  /// four?`.
  ///
  /// Words rather than `7 + 4` because numerals and `+` are the first notation
  /// a small child learns to recognise, and a prompt they can recognise is a
  /// prompt they can attempt. Reading "seven plus four" needs the words, and it
  /// costs a grown-up nothing. The answer is still typed as digits — the field
  /// is `digitsOnly` — so this raises the bar on reading the question, not on
  /// answering it.
  String get prompt => 'What is ${_spell(a)} plus ${_spell(b)}?';

  /// True when [input] parses to [answer]. Trims surrounding whitespace; any
  /// non-numeric or empty input is simply wrong (never an exception).
  bool accepts(String input) => int.tryParse(input.trim()) == answer;

  static const List<String> _numberWords = <String>[
    'zero',
    'one',
    'two',
    'three',
    'four',
    'five',
    'six',
    'seven',
    'eight',
    'nine',
  ];

  static String _spell(int n) => _numberWords[n];
}

/// Shows the parent gate and resolves `true` only when [challenge] is answered
/// correctly. Cancel, a barrier dismiss, the system back button, and running
/// out of [kParentGateTries] all resolve `false` — every way out that is not a
/// correct answer is a refusal. Kept gentle (`CLAUDE.md:63`): a wrong answer
/// nudges "ask a grown-up", never scolds.
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
  int _triesLeft = kParentGateTries;
  bool _wrong = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.challenge.accepts(_controller.text)) {
      Navigator.of(context).pop(true);
      return;
    }
    if (_triesLeft <= 1) {
      // Out of tries. Closing is the refusal — there is nothing to say to a
      // child here, and a grown-up who was really trying gets a fresh sum from
      // the next tap on the link.
      Navigator.of(context).pop(false);
      return;
    }
    setState(() {
      _triesLeft--;
      _wrong = true;
      // Clear it, so the next try starts from an empty field rather than from
      // the last wrong number.
      _controller.clear();
    });
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
