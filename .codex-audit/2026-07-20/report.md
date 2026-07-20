# Rockimals mobile games audit

Date: 2026-07-20

Scope: manual browser walkthrough at 390×844 and 320×568, all four games, correct and incorrect answers, scoring, badges, game-over states, scrolling, keyboard/semantics checks, and repository-native validation.

## Overall verdict

The visual identity and kid-safe tone are strong, and all four games complete their intended loops. The biggest opportunity is to make the rules teachable rather than guessable: explain Power and the size-to-animal ladder, soften one-strike endings, and prevent badge popups from hiding timed answer feedback.

## Flow steps

1. **Opening screen — Healthy.** Clear identity, inviting mascot, and one dominant action.
2. **Radar and Play entry — Mostly healthy.** The Play action is prominent, but several icons rendered as missing-glyph boxes on first entry in the web build.
3. **Games hub — Healthy with discoverability risk.** The four choices are clear at 390×844. At 320×568, Animal Match is below the fold and the screen gives little indication that more content is available.
4. **Today's Challenge — Playable, rule clarity needs work.** Ranking is responsive and the reveal is satisfying. “83% right” and “+30” measure different things, which is difficult to understand without an explanation.
5. **Power Duel — Playable, but overly punishing.** Correct/incorrect feedback is strong. The Power formula is hidden before the choice and one wrong answer ends the run.
6. **Closer or Farther — Needs attention.** The first challenger has no learnable history, so the opening answer is effectively a guess; one wrong guess immediately ends the game.
7. **Animal Match — Playable, but the learning model is hidden.** The size-to-species ladder is not taught. A badge popup can cover answer feedback while the round timer continues.
8. **Small phone and accessibility — Mixed.** Scrolling works at 320×568. In this Flutter web session, keyboard navigation exposed only the framework's “Enable accessibility” placeholder and not the game controls; native VoiceOver/TalkBack still needs device testing.

## Highest-impact recommendations

1. Add a short, skippable tutorial and persistent rule hints: “Power = bigger + closer + faster” and a compact size-to-animal ladder.
2. Pause round timers while badge popups are open, or queue badges for the end of a round/run.
3. Replace one-strike endings with three lives or a fixed five-round session; keep streaks as a bonus.
4. Explain Daily Challenge scoring as two measures: ordering accuracy and exact positions.
5. After every answer, add one sentence explaining why it was correct so the games teach rather than reveal.
6. Let children tap “Next” after feedback, or extend the reveal time; the current 0.95–1.4 second transitions are quick for young readers.
7. Preload icon/emoji fonts in the web build and never rely on emoji alone for essential controls.
8. Add an explicit scroll cue or a more compact hub on short phones.
9. Verify native VoiceOver/TalkBack labels, focus order, selected state, and live-result announcements on iOS and Android.

## Validation

- Formatting check: passed, 165 files and 0 changes.
- Static analysis: passed with no issues.
- Game test suite: passed, 146 tests.
- Full project test suite: failed 1 of 1,115 reported tests because `flutter_launcher_icons` is present in `pubspec.yaml` but missing from the safety test's reviewed development-dependency allowlist (`test/core/safety/kids_safety_checklist_test.dart:74`). This is a test-maintenance mismatch, not a game-play failure.

## Evidence limits

This was a browser-based review of the Flutter web build. Sound quality, haptics, GPU performance, touch behavior on physical devices, screen-reader behavior on native iOS/Android, and long-term retention were not verified.

