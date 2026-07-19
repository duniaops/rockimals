import 'package:flutter/widgets.dart';

/// How much larger every shared control is drawn, published down the tree.
///
/// **This is the delivery mechanism for `LittleKidsMode.controlScale`, and it
/// exists so that `core/` does not have to import `features/settings/`.** The
/// multiplier is decided by a Riverpod provider
/// (`features/settings/little_kids_mode.dart`), but the widgets that must obey
/// it — [TapTarget], `ActionButton`, `AnimalCard` — are shared chrome. Having
/// them `ref.watch` the settings feature would point `core/` at a feature, which
/// is the layering inversion the plan's open "where does the sound gate belong"
/// item is already about; adding a second instance of that problem while the
/// first is unresolved is not a trade worth making. So the feature *pushes* the
/// number in at the root and core widgets read it from context, knowing nothing
/// about why it is what it is.
///
/// **It is deliberately shaped like [MediaQuery.textScaler]**, which answers the
/// same question one layer down: a number every widget multiplies
/// unconditionally, with a defined answer when nobody has provided one. That
/// default is what lets `core/a11y` be tested — and every screen be mounted in a
/// widget test — without a store, a provider scope, or the settings feature
/// existing at all.
///
/// **What it scales, and what it deliberately does not.** Geometry only:
/// padding, box dimensions, and the tap-target minimum. **Not type size.** Text
/// already grows with the OS's own accessibility setting through
/// [MediaQuery.textScaler], so multiplying `fontSize` here would compound with it
/// — a family who has turned the system font up *and* switched Little Kids mode
/// on would get 1.25 × 1.5, which is not what either control promised. The two
/// settings answer different questions and are kept orthogonal: the OS sizes the
/// words, this sizes the things you hit.
class ControlScale extends InheritedWidget {
  const ControlScale({required this.scale, required super.child, super.key});

  /// The multiplier. `1` is the standard size, so a widget can multiply without
  /// branching — see `LittleKidsMode.controlScale`, which says the same thing
  /// about the value it supplies.
  final double scale;

  /// The multiplier in effect at [context], or `1` where none was provided.
  ///
  /// **Absent means standard, not an error.** Most widget tests mount one screen
  /// directly rather than the whole app, and a screen that threw because nobody
  /// had told it about Little Kids mode would make this feature's wiring a
  /// prerequisite for testing anything. The risk that swap creates — production
  /// silently forgetting to provide it, and the whole affordance quietly not
  /// shipping — is closed by `app_test.dart`, which mounts the *real* tree with
  /// the toggle on and asserts a control actually grew.
  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ControlScale>()?.scale ?? 1;

  @override
  bool updateShouldNotify(ControlScale oldWidget) => scale != oldWidget.scale;
}
