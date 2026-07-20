import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rockimals/core/a11y/tap_target.dart';
import 'package:rockimals/core/chrome/action_button.dart';
import 'package:rockimals/core/chrome/obar.dart';
import 'package:rockimals/core/storage/store.dart';
import 'package:rockimals/core/theme/palette.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/games/tutorial/game_tutorial.dart';
import 'package:rockimals/features/settings/about_block.dart';
import 'package:rockimals/features/settings/calm_motion.dart';
import 'package:rockimals/features/settings/little_kids_mode.dart';
import 'package:rockimals/features/settings/sound.dart';

/// The Settings screen — the app's one home for its grown-up-facing toggles and
/// its NASA attribution (`specs/08-settings-about.md`).
///
/// **It is a pushed route, not a fifth nav tab**, and that is the one rule spec
/// 08 pins for the whole app (`specs/08-settings-about.md:40-42`): the nav is
/// fixed at four — Radar / Sky / My Animals / Profile — and anything that wants a
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
          const Obar(title: 'Settings'),
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
                    hint:
                        'Plays happy little sounds in the games and when you '
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
                    // **The hint names exactly what the switch does, and no
                    // more.** For one release it ended "— coming soon", because
                    // spec 08 lets the body be a no-op (`:51-53`) and a row
                    // promising nothing would have been meaningless. The first
                    // affordance has now shipped, so the promise is replaced by
                    // a description in the present tense.
                    // **Read-aloud is still deliberately not mentioned.** It is
                    // still a standard answer (`LittleKidsExperience` says why
                    // per member), and a hint that listed it would put this row
                    // back to advertising a feature a grown-up cannot get — the
                    // thing the "coming soon" wording was carefully avoiding.
                    // Bigger buttons has since shipped, so it is named. The
                    // standing rule: this string lists what the switch does
                    // today, and it grows one clause per affordance that lands.
                    hint:
                        'Bigger buttons, and only the two simplest games: '
                        'Power Duel and Closer or Farther.',
                    value: ref.watch(littleKidsModeProvider),
                    // `choose(next)` rather than the 🔊 row's `toggle()`: this
                    // notifier has no "unset" state to flip relative to, so the
                    // row's own `next` is the whole answer.
                    onChanged: (bool next) =>
                        ref.read(littleKidsModeProvider.notifier).choose(next),
                  ),
                  const SizedBox(height: 16),
                  ActionButton(
                    label: 'Play the game guide again',
                    ghost: true,
                    onTap: () => _openGameGuide(context, ref),
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

  void _openGameGuide(BuildContext context, WidgetRef ref) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext guideContext) => GameTutorialScreen(
          onFinished: () => unawaited(_finishGameGuide(guideContext, ref)),
        ),
      ),
    );
  }

  Future<void> _finishGameGuide(BuildContext context, WidgetRef ref) async {
    final Store store = ref.read(storeProvider);
    final Set<String> progress = store.gameTutorialProgress.toSet()
      ..add(kGameGuideProgressToken);
    await store.setGameTutorialProgress(progress);
    if (context.mounted) Navigator.of(context).pop();
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
///
/// **Deliberately not scaled by 🧸 Little Kids mode**, and the reason is
/// measurement rather than taste: the row's [kMinTapTarget] `minHeight` never
/// binds. Emoji, label and a wrapped line of hint drive it to ~90dp on their
/// own, well past the 60dp floor the multiplier would ask for, so scaling it
/// would change nothing that renders. Pinned in
/// `test/a11y/one_off_controls_test.dart`.
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
              constraints: const BoxConstraints(minHeight: kMinTapTarget),
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
