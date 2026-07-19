import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/a11y/control_scale.dart';
import 'package:rockimals/core/a11y/tap_target.dart';
import 'package:rockimals/core/chrome/action_button.dart';

/// [ControlScale] — the carrier that takes 🧸 Little Kids mode's multiplier from
/// the settings feature to the shared chrome in `core/`.
///
/// **This file owns the mechanism; it does not own the number.** What is asserted
/// here is that an arbitrary multiplier reaches the widgets and multiplies the
/// right things, so every test picks a scale that suits the question rather than
/// the production one — mostly `2`, and `1.2` in the one case that needs the
/// floor not to dominate. `little_kids_mode_test.dart` pins the real constant,
/// and `app_test.dart` proves the two ends are actually connected in the real
/// tree.
void main() {
  group('the carrier', () {
    testWidgets('answers 1 where nobody provided one', (tester) async {
      // **The load-bearing default.** Almost every widget test in this repo
      // mounts one screen rather than the whole app, so a missing [ControlScale]
      // has to mean "standard" rather than an error — otherwise this feature's
      // wiring becomes a prerequisite for testing any screen at all.
      late double seen;
      await tester.pumpWidget(
        Builder(
          builder: (BuildContext context) {
            seen = ControlScale.of(context);
            return const SizedBox.shrink();
          },
        ),
      );

      expect(seen, 1);
    });

    testWidgets('hands the nearest value down the tree', (tester) async {
      late double seen;
      await tester.pumpWidget(
        ControlScale(
          scale: 2,
          child: Builder(
            builder: (BuildContext context) {
              seen = ControlScale.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(seen, 2);
    });

    testWidgets('rebuilds its dependents when the value changes', (
      tester,
    ) async {
      // The switch must resize controls on the frame of the tap, not on the
      // next restart (`specs/08-settings-about.md:75`). That is
      // `updateShouldNotify`'s job, and an [InheritedWidget] that returned
      // `false` there would leave every control at its old size with nothing
      // else failing.
      // [Center] is not decoration: a widget pumped as the root gets *tight*
      // constraints of the whole 800×600 surface, and a [ConstrainedBox] can
      // only raise a minimum inside the constraints it is handed — so a bare
      // [TapTarget] here measures 800×600 and would pass any scale at all.
      // Centring hands it loose constraints, which is what every real caller
      // gives it.
      Widget tree(double scale) => ControlScale(
        scale: scale,
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: TapTarget(child: SizedBox.shrink())),
        ),
      );

      await tester.pumpWidget(tree(1));
      expect(tester.getSize(find.byType(TapTarget)).height, kMinTapTarget);

      await tester.pumpWidget(tree(2));
      expect(tester.getSize(find.byType(TapTarget)).height, kMinTapTarget * 2);
    });
  });

  group('what it scales', () {
    testWidgets('raises TapTarget\'s floor, on both axes', (tester) async {
      // The highest-leverage of the three: thirteen sites already wrap
      // themselves in a [TapTarget], and all of them get a bigger region to hit
      // from this one multiplication without knowing the setting exists.
      await tester.pumpWidget(
        const ControlScale(
          scale: 2,
          child: Directionality(
            textDirection: TextDirection.ltr,
            // Centred for the reason the test above spells out — a root widget
            // is given tight constraints and would measure the whole surface.
            child: Center(
              child: TapTarget(expandWidth: true, child: SizedBox.shrink()),
            ),
          ),
        ),
      );

      expect(
        tester.getSize(find.byType(TapTarget)),
        const Size(kMinTapTarget * 2, kMinTapTarget * 2),
      );
    });

    testWidgets('does not repaint the child it grew around', (tester) async {
      // [TapTarget]'s whole contract — grow the hit region, touch no painted
      // pixel — has to survive the multiplier, or Little Kids mode becomes a
      // redraw of the app's chrome rather than a bigger target inside it.
      await tester.pumpWidget(
        const ControlScale(
          scale: 2,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: TapTarget(
              child: SizedBox(width: 30, height: 20, child: Placeholder()),
            ),
          ),
        ),
      );

      expect(tester.getSize(find.byType(Placeholder)), const Size(30, 20));
    });

    testWidgets('grows ActionButton by the floor at ordinary text size', (
      tester,
    ) async {
      // **The button is floor-sized, not content-sized, and that is worth
      // pinning rather than assuming.** It paints 43dp — 14dp padding either
      // side of a 15dp label — and [TapTarget] lifts it to 48. Both numbers
      // scale by the same multiplier, and 43 < 48, so the floor keeps winning
      // at every scale: the height is exactly `kMinTapTarget × scale`.
      //
      // The first draft of this test asserted *greater than* the floor, on the
      // assumption that scaled padding would push past it. It cannot, at this
      // text size. The test below is where the padding becomes observable.
      await tester.pumpWidget(_button(scale: 2));

      expect(
        tester.getSize(find.byType(ActionButton)).height,
        kMinTapTarget * 2,
      );
    });

    testWidgets('and by its own padding once the label outgrows the floor', (
      tester,
    ) async {
      // **Where the scaled padding earns its keep.** Turn the system font up far
      // enough and the label alone exceeds the floor, so the button stops being
      // floor-sized and starts being content-sized — and from that point the
      // padding is the only thing Little Kids mode still has hold of. Without it
      // the button would keep growing with the *text* while every control around
      // it grew with the *multiplier*, which is the one case where scaling
      // padding is not redundant with scaling the floor.
      //
      // 1.2 rather than the production 1.25, because this file pins the
      // mechanism and not the number — and it has to be a multiplier small
      // enough that the floor does not reclaim the lead.
      //
      // **Compared against the same button at scale 1, not against the floor.**
      // The first draft asserted `> kMinTapTarget * scale` and a mutant with the
      // padding left unscaled survived it: at this text size the content already
      // clears the scaled floor by a hair (58 against 57.6), so the assertion
      // passed on the label's own growth. Measuring both scales is what makes
      // the padding the only thing that can explain the difference.
      const double scale = 1.2;

      await tester.pumpWidget(_button(scale: 1, textScale: 2));
      final double standard = tester.getSize(find.byType(ActionButton)).height;

      await tester.pumpWidget(_button(scale: scale, textScale: 2));

      expect(
        tester.getSize(find.byType(ActionButton)).height,
        greaterThan(standard),
        reason:
            'both buttons are content-sized at this text scale, so only the '
            'padding can separate them',
      );
    });

    testWidgets('leaves type size to the OS', (tester) async {
      // **The orthogonality rule, asserted rather than just documented.** Text
      // grows through [MediaQuery.textScaler]; controls grow through this. A
      // `fontSize` multiplied here would compound the two for the family most
      // likely to have both turned up — so the label must measure identically
      // at either multiplier.
      await tester.pumpWidget(_button(scale: 1));
      final Size standard = tester.getSize(find.text('Meet'));

      await tester.pumpWidget(_button(scale: 2));

      expect(tester.getSize(find.text('Meet')), standard);
    });
  });
}

/// The app's one shared button under a given control multiplier, and optionally
/// a given OS text scale — the two settings [ControlScale] deliberately keeps
/// orthogonal, so several tests here need to vary them independently.
Widget _button({required double scale, double textScale = 1}) => ControlScale(
  scale: scale,
  child: MaterialApp(
    builder: (BuildContext context, Widget? child) =>
        MediaQuery.withClampedTextScaling(
          minScaleFactor: textScale,
          maxScaleFactor: textScale,
          child: child!,
        ),
    home: Scaffold(
      body: Center(
        child: ActionButton(label: 'Meet', onTap: () {}),
      ),
    ),
  ),
);
