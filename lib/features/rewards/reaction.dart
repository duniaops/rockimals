/// The reaction animations (`specs/05`, "Reactions (juice)") — a port of the
/// prototype's `hop` and `wob` keyframes and the `react()` that applies them
/// (`index.html:237-240,968`).
///
/// A right answer makes the animal's avatar **hop and spin** for 0.85s; a wrong
/// one gives it a gentle 0.65s **wobble**. Nothing else: this file is the motion,
/// and the tones `react()` fires alongside it belong to the sound engine, which
/// listens on [gameReactionProvider] instead (see "How a game reaches this"
/// below).
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// How long the happy hop runs (`.happy{animation:hop .85s ease}`,
/// `index.html:238`).
const Duration kHappyDuration = Duration(milliseconds: 850);

/// How long the sad wobble runs (`.sad{animation:wob .65s ease}`,
/// `index.html:240`).
const Duration kSadDuration = Duration(milliseconds: 650);

/// Which way an answer went, and therefore which motion the avatar plays.
enum Reaction {
  /// Correct — hop and spin.
  happy,

  /// Wrong — wobble. Every game pairs this with an encouraging line of its own
  /// (`CLAUDE.md:70`); the motion is deliberately gentle for the same reason.
  sad,
}

/// [Reaction.happy] for a right answer, [Reaction.sad] for a wrong one, and null
/// while the question is still open — the shape every game already holds its
/// answer state in (`bool? _pickedA`, `bool? _guessedCloser`, `Animal? _picked`,
/// `ChallengeGrade? _grade`).
Reaction? reactionFor(bool? correct) => switch (correct) {
  true => Reaction.happy,
  false => Reaction.sad,
  null => null,
};

/// A CSS keyframe segment: [begin] to [end] over [weight] percent of the
/// animation, eased.
///
/// `animation-timing-function` applies **between each pair of keyframes**, not
/// once across the whole run, so every segment gets its own curve — and
/// [Curves.ease] is `Cubic(0.25, 0.1, 0.25, 1.0)`, the exact definition of CSS
/// `ease`, so this is the prototype's easing rather than an approximation of it.
TweenSequenceItem<double> _segment(double begin, double end, double weight) {
  return TweenSequenceItem<double>(
    tween: Tween<double>(
      begin: begin,
      end: end,
    ).chain(CurveTween(curve: Curves.ease)),
    weight: weight,
  );
}

/// The hop's vertical offset in logical pixels, over the life of the animation.
///
/// `0%{translateY(0)} 22%{translateY(-24px)} 45%{translateY(0)}
/// 55%{translateY(-9px)} 78%{translateY(0)} 100%{translateY(0)}`
/// (`index.html:237`) — a big jump, then a small one, then a beat of stillness
/// so the spin has somewhere to finish.
final Animatable<double> kHopLift = TweenSequence<double>(
  <TweenSequenceItem<double>>[
    _segment(0, -24, 22),
    _segment(-24, 0, 23),
    _segment(0, -9, 10),
    _segment(-9, 0, 23),
    _segment(0, 0, 22),
  ],
);

/// The hop's rotation in **turns** (1 turn = 360°).
///
/// **It spins forward, snaps back, and then spins a full turn — and that is the
/// prototype's real behaviour, not a mistake in this port.** The keyframes name
/// a rotation at only three stops (`45%{… rotate(180deg)}`, `78%{… rotate(360deg)}`,
/// `100%`, `index.html:237`); the 22% and 55% stops list `translateY` alone. CSS
/// does not carry an omitted transform function forward — it pads the shorter
/// function list with the **identity**, so `55%{translateY(-9px)}` means
/// `rotate(0deg)`, and the browser really does wind the avatar back to zero
/// between the half turn and the full one. In 0.85s it reads as an excited
/// tumble, which is why nobody ever filed it.
///
/// Ported literally under `CLAUDE.md:22-26` — `index.html` is the authoritative
/// spec for animations, and decisions 8 and 11 in `IMPLEMENTATION_PLAN.md` are
/// the standing rule that surprising prototype behaviour gets ported and
/// documented rather than quietly corrected. A designer who wants the plain
/// monotonic 0→360 spin the spec line describes changes the third and fourth
/// segments below to `_segment(0.5, 0.75, 10), _segment(0.75, 1, 23)`.
final Animatable<double> kHopTurns = TweenSequence<double>(
  <TweenSequenceItem<double>>[
    _segment(0, 0, 22),
    _segment(0, 0.5, 23),
    _segment(0.5, 0, 10),
    _segment(0, 1, 23),
    _segment(1, 1, 22),
  ],
);

/// The wobble's rotation in turns: `-13°, 11°, -8°, 6°, 0°` at every fifth of
/// the animation (`index.html:239`) — a shake that decays instead of stopping
/// dead.
final Animatable<double> kWobbleTurns =
    TweenSequence<double>(<TweenSequenceItem<double>>[
      _segment(0, -13 / 360, 20),
      _segment(-13 / 360, 11 / 360, 20),
      _segment(11 / 360, -8 / 360, 20),
      _segment(-8 / 360, 6 / 360, 20),
      _segment(6 / 360, 0, 20),
    ]);

/// The wobble's vertical offset: `translateY(3px)` rides along with the first
/// two swings only (`index.html:239`), so the avatar sags slightly as it shakes
/// and then picks itself back up. The last three keyframes name no translation,
/// which CSS pads to zero — the same identity-padding rule as [kHopTurns].
final Animatable<double> kWobbleLift = TweenSequence<double>(
  <TweenSequenceItem<double>>[
    _segment(0, 3, 20),
    _segment(3, 3, 20),
    _segment(3, 0, 20),
    _segment(0, 0, 20),
    _segment(0, 0, 20),
  ],
);

/// Wraps an animal avatar and plays the hop or the wobble when [reaction]
/// changes to a non-null value.
///
/// **How a game reaches this: it does *not* go through [gameReactionProvider].**
/// That channel carries one reaction per answer, which is exactly right for the
/// sound engine — one cue per tap — but it cannot say *which avatar on screen*
/// moves, and in two of the four games that is not "all of them":
///
/// * **Power Duel** hops only the card the child tapped (`react(av, win)` where
///   `av` is `c.querySelector('.avatar')` on the tapped card, `index.html:1052`)
///   — the other animal sits still even though both cards reveal.
/// * **Today's Challenge** never calls `react()` at all. It animates all four
///   cards, each on **its own** correctness (`av.classList.add(ok?'happy':'sad')`
///   where `ok = userPos === truePos`, `index.html:937`), while the single sound
///   it plays is chosen by the round's overall accuracy (`index.html:939`). One
///   channel value cannot be four different card outcomes.
///
/// So motion is driven by the state each widget already holds and sound by the
/// channel. Feeding both off the channel would have made the duel hop the wrong
/// animal and the challenge tell four cards the same thing.
///
/// The child is passed to [AnimatedBuilder] rather than rebuilt inside it, so a
/// frame of this animation re-runs two [Transform]s and nothing else — the
/// low-allocation shape `CLAUDE.md:80` asks for, and free here.
class ReactionAvatar extends StatefulWidget {
  const ReactionAvatar({
    required this.reaction,
    required this.child,
    super.key,
  });

  /// The motion to play, or null while the question is open.
  ///
  /// **Null between answers is what makes a run of same-sign answers work.** The
  /// prototype replays by removing the class, forcing a reflow and adding it
  /// back (`void el.offsetWidth`, `index.html:968`); here the replay trigger is
  /// this value *changing*, so two correct answers in a row only both hop
  /// because the game resets to null when it deals the next round. Every game
  /// does (`_nextRound`, `_advance`, `_startOver`), and a test pins it.
  final Reaction? reaction;

  /// The avatar itself — each game's own disc, at its own size. This widget adds
  /// motion and nothing else, so the four avatars stay four different sizes.
  final Widget child;

  @override
  State<ReactionAvatar> createState() => _ReactionAvatarState();
}

class _ReactionAvatarState extends State<ReactionAvatar>
    with SingleTickerProviderStateMixin {
  /// One controller per avatar, as `specs/05` asks. Its duration is set at each
  /// play, because the happy and sad motions are different lengths.
  late final AnimationController _controller = AnimationController(vsync: this);

  @override
  void initState() {
    super.initState();
    // An avatar mounted already carrying a reaction plays it. Unreachable from
    // the four games as they stand — they all mount a round unanswered — but
    // "a non-null reaction animates" should not depend on whether the element
    // happened to be reused, which is the sort of thing a later layout change
    // silently flips.
    _play();
  }

  @override
  void didUpdateWidget(ReactionAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reaction != oldWidget.reaction) _play();
  }

  void _play() {
    switch (widget.reaction) {
      case null:
        // Back to an open question: stop wherever the motion got to and sit
        // still, so the next round opens on an untilted avatar.
        _controller.stop();
        _controller.value = 0;
      case Reaction.happy:
        _controller.duration = kHappyDuration;
        _controller.forward(from: 0);
      case Reaction.sad:
        _controller.duration = kSadDuration;
        _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Reaction? reaction = widget.reaction;
    if (reaction == null) return widget.child;

    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (BuildContext context, Widget? child) => switch (reaction) {
        // A CSS transform list applies right-to-left, so the leftmost function
        // is the outermost nesting here. `hop` is `translateY(…) rotate(…)`
        // (`index.html:237`) — spin in place, then lift — and `wob` is
        // `rotate(…) translateY(…)` (`index.html:239`), where the 3px sag is
        // applied first and then carried round by the tilt. The two orders are
        // not interchangeable, which is why they are written out twice.
        Reaction.happy => Transform.translate(
          offset: Offset(0, kHopLift.evaluate(_controller)),
          child: Transform.rotate(
            angle: kHopTurns.evaluate(_controller) * 2 * math.pi,
            child: child,
          ),
        ),
        Reaction.sad => Transform.rotate(
          angle: kWobbleTurns.evaluate(_controller) * 2 * math.pi,
          child: Transform.translate(
            offset: Offset(0, kWobbleLift.evaluate(_controller)),
            child: child,
          ),
        ),
      },
    );
  }
}
