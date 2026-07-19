/// The celebration popup (`specs/05`: *"a celebration popup (bouncing badge +
/// fanfare, tap to continue). Queue multiple unlocks."*).
///
/// **The widget half of the acceptance criteria.** `badge_controller_test.dart`
/// pins the queue as state; this pins that a child can actually see it and tap
/// it away — including the two properties the state tests cannot express: that
/// the popup covers a *pushed route* (a badge is nearly always earned mid-game),
/// and that it costs nothing when no badge is being celebrated.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/audio/sound_cues.dart';
import 'package:rockimals/core/audio/sound_engine.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/rewards/badge_controller.dart';
import 'package:rockimals/features/rewards/badge_popup.dart';
import 'package:rockimals/features/settings/calm_motion.dart';
import 'package:rockimals/features/settings/sound.dart';

import '../../support/memory_store.dart';
import '../../support/recording_sound_engine.dart';
import '../../support/stub_settings.dart';

void main() {
  late MemoryStore store;
  late RecordingSoundEngine engine;

  setUp(() {
    store = MemoryStore();
    engine = RecordingSoundEngine();
  });

  /// The app, mounted the way `main.dart` mounts it: the popup host wraps the
  /// `Navigator` through `MaterialApp.builder`, not a screen.
  ///
  /// [calmMotion] is the child's 🐢 Calm motion choice; null — the default — is
  /// the fresh-install state, which resolves against a `MediaQuery` that is not
  /// asking, so every test outside the Calm motion group gets the endless hop
  /// the prototype has.
  Future<ProviderContainer> pumpApp(
    WidgetTester tester, {
    Widget home = const _Home(),
    bool? calmMotion,
  }) async {
    final ProviderContainer container = ProviderContainer(
      overrides: [
        storeProvider.overrideWithValue(store),
        soundEngineProvider.overrideWithValue(engine),
        soundOnProvider.overrideWith(() => StubSoundOn(true)),
        reducedMotionProvider.overrideWith(() => StubCalmMotion(calmMotion)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: (BuildContext context, Widget? child) =>
              BadgePopupHost(child: child ?? const SizedBox.shrink()),
          home: home,
        ),
      ),
    );
    return container;
  }

  /// Run the popup's entry animation to its end.
  ///
  /// **`pumpAndSettle` cannot be used while a badge is on screen, and that is a
  /// property of the feature rather than an awkwardness of the test.** The emoji
  /// hops forever (`animation:hop 1.1s ease infinite`, `index.html:251`), so the
  /// tree never reaches a frame with no scheduled animation and a settle runs to
  /// its timeout. Every wait below is therefore an explicit duration.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(kBadgePopupDuration);
  }

  /// Tap the popup away and run out both the fade and the beat before whatever
  /// is queued behind it (`index.html:1126`).
  ///
  /// The last pump is not optional even when nothing is queued: `dismiss` arms a
  /// real [Timer], and a test that ended before it fired would fail on a pending
  /// timer rather than on anything it was asking about.
  Future<void> dismiss(WidgetTester tester) async {
    await tester.tapAt(const Offset(20, 20));
    await tester.pump();
    await tester.pump(kBadgePopupDuration);
    await tester.pump(kBadgeDrainGap);
    await tester.pump(kBadgePopupDuration);
  }

  testWidgets('shows nothing at all until a badge is earned', (
    WidgetTester tester,
  ) async {
    await pumpApp(tester);

    expect(find.textContaining('New badge!'), findsNothing);
    // Not merely invisible: the scrim carries a `BackdropFilter`, which would be
    // blurring the whole app every frame of a session in which no badge is ever
    // earned.
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('pops Mouse Scout with its emoji and goal', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = await pumpApp(tester);

    store.points = 50;
    container.read(badgesProvider.notifier).check();
    await settle(tester);

    expect(find.text('New badge! Mouse Scout'), findsOneWidget);
    expect(find.text('Earn 50 points'), findsOneWidget);
    expect(find.text('🐭'), findsOneWidget);
    expect(find.text('tap to keep playing'), findsOneWidget);
  });

  testWidgets('covers a pushed route, which is where badges are earned', (
    WidgetTester tester,
  ) async {
    // The placement test. A badge is nearly always earned inside a game, and a
    // game is a pushed `MaterialPageRoute`; a popup mounted on a screen rather
    // than above the `Navigator` would be celebrated underneath it.
    final ProviderContainer container = await pumpApp(tester);

    await tester.tap(find.text('open a game'));
    await tester.pumpAndSettle();
    expect(find.text('a game'), findsOneWidget);

    store.points = 50;
    container.read(badgesProvider.notifier).check();
    await settle(tester);

    expect(find.text('New badge! Mouse Scout'), findsOneWidget);
    // Painted over the route, not instead of it.
    expect(find.text('a game'), findsOneWidget);
  });

  testWidgets('a tap anywhere dismisses it', (WidgetTester tester) async {
    final ProviderContainer container = await pumpApp(tester);

    store.points = 50;
    container.read(badgesProvider.notifier).check();
    await settle(tester);

    // The whole scrim is the target (`$("badgePop").onclick`,
    // `index.html:1126`) — a child looking at the badge should not have to find
    // a button.
    await dismiss(tester);

    expect(find.textContaining('New badge!'), findsNothing);
    expect(container.read(badgesProvider).celebrating, isNull);
  });

  testWidgets('two badges are celebrated one at a time, in order', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = await pumpApp(tester);

    store.points = 50;
    store.bestStreak = 5;
    container.read(badgesProvider.notifier).check();
    await settle(tester);

    expect(find.text('New badge! Mouse Scout'), findsOneWidget);
    expect(find.textContaining('On Fire'), findsNothing);

    await dismiss(tester);

    expect(find.text('New badge! On Fire'), findsOneWidget);
    expect(find.text('Get 5 correct in a row'), findsOneWidget);

    await dismiss(tester);

    expect(find.textContaining('New badge!'), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('the card animates in rather than snapping to full size', (
    WidgetTester tester,
  ) async {
    // The "bouncing badge" of the spec line, and the sampling is the only way to
    // see it: a spring and an instant swap are identical once settled.
    //
    // **What is pinned is the overshoot specifically**, not merely that the
    // scale moves. `cubic-bezier(.2,1.5,.4,1)` (`index.html:249`) has a control
    // point above 1 on the y axis, so the card grows *past* its final size and
    // settles back — that momentary overshoot is the whole "pop". Swapping in
    // any ordinary ease would still animate, still land at 1, and read as a card
    // sliding into place rather than a prize arriving.
    final ProviderContainer container = await pumpApp(tester);

    store.points = 50;
    container.read(badgesProvider.notifier).check();
    await tester.pump();

    const Duration step = Duration(milliseconds: 20);
    await tester.pump(step);
    // ignore: avoid_print

    final List<double> scales = <double>[_cardScale(tester)];
    for (
      Duration elapsed = step;
      elapsed < kBadgePopupDuration + step;
      elapsed += step
    ) {
      await tester.pump(step);
      scales.add(_cardScale(tester));
    }

    expect(scales.first, lessThan(1), reason: 'it starts small');
    expect(
      scales.reduce(math.max),
      greaterThan(1),
      reason: 'and grows past full size before settling — the spring',
    );
    expect(scales.last, closeTo(1, 1e-6));
  });

  testWidgets('the emoji keeps hopping while the popup is up', (
    WidgetTester tester,
  ) async {
    // `animation:hop 1.1s ease infinite` (`index.html:251`) — the popup is the
    // one place in the app with an endless animation, so a settle would hang
    // were it driven any other way. `pump` with a duration, never
    // `pumpAndSettle`, from here on in this test.
    final ProviderContainer container = await pumpApp(tester);

    store.points = 50;
    container.read(badgesProvider.notifier).check();
    await tester.pump();
    await tester.pump(kBadgePopupDuration);

    // Sampled at 22% of the hop, where the keyframes put the emoji at its
    // highest (`translateY(-24px)`, `index.html:237`).
    await tester.pump(kBadgeHopDuration * 0.22);
    final Offset lifted = tester.getCenter(find.text('🐭'));

    // …and at 45%, back on the ground.
    await tester.pump(kBadgeHopDuration * 0.23);
    final Offset landed = tester.getCenter(find.text('🐭'));

    expect(
      lifted.dy,
      lessThan(landed.dy),
      reason: 'the emoji should be higher a fifth of the way through the hop',
    );
  });

  testWidgets('the fanfare plays once per badge', (WidgetTester tester) async {
    final ProviderContainer container = await pumpApp(tester);

    store.points = 50;
    container.read(badgesProvider.notifier).check();
    await settle(tester);

    expect(engine.played, <SoundCue>[SoundCue.cheer]);

    // Rebuilding the popup must not re-fire it — the cue belongs to the badge
    // being drained, not to the widget being painted.
    await tester.pump(const Duration(seconds: 1));
    expect(engine.played, hasLength(1));
  });

  /// 🐢 Calm motion's badge-popup half — **the surface the setting most exists
  /// for**, since this hop is the only animation in the app that never ends of
  /// its own accord. The radar's half is in `radar_view_test.dart`, the
  /// reactions' in `reaction_test.dart`, the spinner's in
  /// `loading_screen_test.dart`.
  group('🐢 Calm motion', () {
    testWidgets('settles the emoji instead of hopping it forever', (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = await pumpApp(
        tester,
        calmMotion: true,
      );

      store.points = 50;
      container.read(badgesProvider.notifier).check();
      await settle(tester);

      // The same two samples the full-motion test above takes — the peak of the
      // hop and the landing — read here as one position, because there is no
      // hop.
      final Offset atRest = tester.getCenter(find.text('🐭'));
      await tester.pump(kBadgeHopDuration * 0.22);
      expect(tester.getCenter(find.text('🐭')), atRest);
      await tester.pump(kBadgeHopDuration * 0.23);
      expect(tester.getCenter(find.text('🐭')), atRest);

      // **Settled at rest, not stopped wherever the controller happened to
      // be.** `kHopLift` puts the emoji 24px up at the peak, so a controller
      // merely `stop()`-ped mid-hop would sit visibly high and tilted — a frozen
      // bug's silhouette rather than a calm one. This is the assertion that
      // catches it: a full hop period on, it has not moved from where a
      // never-started controller puts it.
      await tester.pump(kBadgeHopDuration);
      expect(tester.getCenter(find.text('🐭')), atRest);
    });

    testWidgets('and so the popup can settle at all', (
      WidgetTester tester,
    ) async {
      // The mechanical proof of "forever" ending, and worth its own test
      // because it is the property the position samples above can only imply:
      // with the hop stopped there is no permanently scheduled animation left,
      // so `pumpAndSettle` — which the note on `settle()` above explains cannot
      // be used over a hopping popup, and which would time out against one —
      // now returns. If this ever hangs, something under the popup is animating
      // endlessly that Calm motion did not reach.
      final ProviderContainer container = await pumpApp(
        tester,
        calmMotion: true,
      );

      store.points = 50;
      container.read(badgesProvider.notifier).check();
      await tester.pumpAndSettle();

      expect(find.text('New badge! Mouse Scout'), findsOneWidget);
    });

    testWidgets('still celebrates — the scrim, the pop and the fanfare stay', (
      WidgetTester tester,
    ) async {
      // **The other half of the setting, and the one a "reduced motion means no
      // motion" reading would quietly destroy.** A child who turned Calm motion
      // on asked for the endless jiggling to stop; they did not ask to stop
      // being congratulated. The card still springs (it plays once, in 300ms,
      // and is what makes a prize read as an event), the scrim still fades, the
      // copy is unchanged and the cheer still plays.
      final ProviderContainer container = await pumpApp(
        tester,
        calmMotion: true,
      );

      store.points = 50;
      container.read(badgesProvider.notifier).check();
      await tester.pump();
      await tester.pump(kBadgePopupDuration * 0.5);

      expect(
        _cardScale(tester),
        isNot(closeTo(1, 1e-6)),
        reason: 'the card is still mid-spring halfway through its pop',
      );

      await tester.pumpAndSettle();
      expect(find.text('New badge! Mouse Scout'), findsOneWidget);
      expect(find.text('Earn 50 points'), findsOneWidget);
      expect(find.text('tap to keep playing'), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(engine.played, <SoundCue>[SoundCue.cheer]);
    });

    testWidgets('takes hold under a popup that is already open', (
      WidgetTester tester,
    ) async {
      // "No restart required" (`specs/08-settings-about.md:75`) is not reachable
      // by a child here — Settings is not tappable behind the scrim — but the
      // *mechanism* is, and it is the fragile part: the setting can only be read
      // in a build, while an `AnimationController` may not be driven from one.
      // `didUpdateWidget` is where that is resolved, and this is the only test
      // that exercises it on this surface. Without it the popup would be correct
      // only for the value of the setting at the moment it happened to mount.
      final ProviderContainer container = await pumpApp(tester);

      store.points = 50;
      container.read(badgesProvider.notifier).check();
      await settle(tester);

      // Hopping, as the full-motion test pins.
      final Offset low = tester.getCenter(find.text('🐭'));
      await tester.pump(kBadgeHopDuration * 0.22);
      expect(tester.getCenter(find.text('🐭')).dy, lessThan(low.dy));

      await container.read(reducedMotionProvider.notifier).choose(true);
      await tester.pump();

      // Back on the ground on the very next frame, and staying there.
      expect(tester.getCenter(find.text('🐭')), low);
      await tester.pump(kBadgeHopDuration * 0.22);
      expect(tester.getCenter(find.text('🐭')), low);
    });
  });
}

/// The scale [Transform] wrapping the card, mid-animation.
///
/// `.first` is the *closest* ancestor — `find.ancestor` walks outwards, and the
/// outer ones are the route's own transition transforms, which sit at 1 the
/// whole time and would make this assert nothing.
double _cardScale(WidgetTester tester) {
  final Transform transform = tester.widget<Transform>(
    find
        .ancestor(
          of: find.text('New badge! Mouse Scout'),
          matching: find.byType(Transform),
        )
        .first,
  );
  // `entry(0, 0)` — the x scale — and **not `getMaxScaleOnAxis()`**, which is
  // the obvious call and silently useless here: `Transform.scale` leaves the z
  // axis at 1, so the "max" scale never reads below 1 and the shrunk-card half
  // of this test would pass against a card that never animated at all.
  return transform.transform.entry(0, 0);
}

/// A screen with something to push, so the popup can be asked to cover a route.
class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (BuildContext context) =>
                  const Scaffold(body: Center(child: Text('a game'))),
            ),
          ),
          child: const Text('open a game'),
        ),
      ),
    );
  }
}
