import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/a11y/tap_target.dart';

/// Walks a mounted tree and reports every interactive target smaller than
/// [kMinTapTarget] on either axis.
///
/// **Why a tree walk and not a per-widget assertion.** The bar this enforces —
/// `specs/08-settings-about.md:82`, "every tap target is ≥48dp" — is a property
/// of *the app*, not of any one button. A per-widget test only ever covers the
/// buttons someone remembered to write a test for, which is exactly the set
/// that was already being thought about. The failure this file exists to catch
/// is the button nobody thought about: a new pill copied from an old one, or a
/// chip whose padding was tuned for looks. Walking the tree catches those the
/// day they render, without anyone adding a line here.
///
/// **The rule is "one report per hittable region", and getting there took two
/// passes.** Flutter nests interactivity several deep: an [InkWell] builds a
/// [GestureDetector] internally, a [TextButton] builds an [InkWell], a [Switch]
/// builds both. A naive "every interactive element is ≥48" therefore fires
/// two or three times for every single button, on framework internals nobody
/// can fix. But the obvious dedupe — "skip anything with an interactive
/// ancestor" — is worse than it looks: the badge popup wraps the *entire
/// screen* in a dismiss-on-tap [GestureDetector] (`badge_popup.dart:222`), so
/// that rule would silently excuse every undersized button underneath it.
///
/// What separates the two cases is **size**. A framework re-wrap occupies
/// exactly the same box as the widget that created it; a small button inside a
/// big tappable region does not. So an element is skipped only when its nearest
/// interactive ancestor is *the same size* — the same physical region, reported
/// once at its outermost layer — and is measured otherwise. That is what a
/// finger experiences: it hits the largest region that responds, and there is
/// only one of those per place you can touch.
///
/// The fix this pushes people toward is the one `settings_screen.dart`'s back
/// pill found first (it now lives in `core/chrome/obar.dart`, shared by all
/// four screens that wear the bar) and `TapTarget` generalises: put the 48dp
/// around the 30dp painted pill, so what grows is the region a thumb has to
/// find, not the picture.
///
/// **What counts as interactive** is the handful of types this app actually
/// builds buttons out of. `lib/` contains no `ElevatedButton` or `IconButton`
/// (every button is hand-built as `Material` + [InkWell], see
/// `title_screen.dart:441-448`), so this list is short by design rather than by
/// omission. [Listener] is excluded on purpose: the radar's animal field is one
/// (`radar_view.dart:212`), it fills the screen, and the thing a child aims at
/// inside it is an animal token, whose tap radius is `radar_orbits.dart`'s
/// question and is tested there.
List<TapTargetViolation> tapTargetViolations(WidgetTester tester) {
  final List<TapTargetViolation> violations = <TapTargetViolation>[];

  // `find.byElementPredicate` and not `tester.allElements`, and the difference
  // is load-bearing here: the shell is an [IndexedStack], which keeps all four
  // tabs mounted and paints one. `allElements` walks the mounted tree, so every
  // tab's buttons would be audited on every tab — the same violations reported
  // four times, and a screen "passing" while the tab actually on screen was
  // never looked at. A [Finder] honours `debugVisitOnstageChildren`, so it sees
  // what a child sees.
  for (final Element element
      in find.byElementPredicate((Element _) => true).evaluate()) {
    if (!_isInteractive(element.widget)) continue;

    final RenderObject? render = element.renderObject;
    if (render is! RenderBox || !render.hasSize) continue;

    final Size size = render.size;
    if (size.width >= kMinTapTarget && size.height >= kMinTapTarget) continue;
    if (_isCoveredByAncestor(element, size)) continue;
    if (_isTextSelectionHandle(element)) continue;

    violations.add(TapTargetViolation(_describe(element), size));
  }

  return violations;
}

/// Fails with every undersized target on screen at once, named and measured.
///
/// One assertion per screen rather than per button, because the useful output
/// when this breaks is the whole list — fixing them one failure at a time is
/// how an audit turns into a dozen iterations.
void expectEveryTapTargetIsBigEnough(WidgetTester tester, {String? reason}) {
  final List<TapTargetViolation> violations = tapTargetViolations(tester);
  expect(
    violations,
    isEmpty,
    reason:
        '${reason ?? 'Undersized tap targets'} — every interactive target must '
        'be at least ${kMinTapTarget}dp on both axes '
        '(specs/08-settings-about.md:82):\n'
        '${violations.map((TapTargetViolation v) => '  • $v').join('\n')}',
  );
}

/// One undersized target: what it is, and how big it actually rendered.
class TapTargetViolation {
  const TapTargetViolation(this.description, this.size);

  final String description;
  final Size size;

  @override
  String toString() =>
      '$description is ${size.width.toStringAsFixed(1)}×'
      '${size.height.toStringAsFixed(1)}dp';
}

bool _isInteractive(Widget widget) {
  if (widget is InkResponse) return widget.onTap != null;
  if (widget is GestureDetector) return widget.onTap != null;
  if (widget is Switch) return widget.onChanged != null;
  if (widget is TextButton) return widget.onPressed != null;
  return false;
}

/// True when this element is an inner layer of a target already accounted for
/// by its nearest interactive ancestor, on either of two counts.
///
/// **Same size — a framework re-wrap.** An [InkWell] builds a
/// [GestureDetector] over exactly its own box; reporting both would double every
/// finding. Deduped whatever the size, because if the outer one is undersized it
/// is the one to go and fix.
///
/// **Padded up to the minimum — Material's own tap-target mechanism.** A
/// [TextButton] renders a 40dp [InkWell] inside a 48dp `_InputPadding` that
/// extends hit testing to the full 48 (`materialTapTargetSize`). The parent gate
/// buttons measure exactly this way — 108.6×40 ink inside a 108.6×48 button — and
/// they meet the guideline, so reporting the inner box would be a false positive
/// that the only available "fix" (hand-rolling the dialog's buttons) would make
/// the app worse to satisfy.
///
/// The second clause is bounded to [kMinTapTarget] of growth on each axis, and
/// that bound is what stops it swallowing the case it superficially resembles:
/// the badge popup wraps the *whole screen* in a dismiss-on-tap
/// [GestureDetector] (`badge_popup.dart:222`), so an unbounded "an interactive
/// ancestor is big enough" rule would silently excuse every undersized button
/// underneath it. A control padded to the minimum grows by at most the minimum;
/// a full-screen scrim does not.
bool _isCoveredByAncestor(Element element, Size size) {
  bool covered = false;

  element.visitAncestorElements((Element ancestor) {
    if (!_isInteractive(ancestor.widget)) return true;

    final RenderObject? render = ancestor.renderObject;
    if (render is RenderBox && render.hasSize) {
      final Size outer = render.size;
      final bool sameRegion = outer == size;
      final bool paddedToMinimum =
          outer.width >= kMinTapTarget &&
          outer.height >= kMinTapTarget &&
          outer.width - size.width <= kMinTapTarget &&
          outer.height - size.height <= kMinTapTarget;
      covered = sameRegion || paddedToMinimum;
    }
    // Stop at the *nearest* interactive ancestor either way: a further-out one
    // is a different region, and what it measures says nothing about whether
    // this element is an inner layer of it.
    return false;
  });

  return covered;
}

/// Flutter's own text-selection handles, which are drag affordances the
/// framework draws inside a [TextField] and sizes itself.
///
/// The parent gate's answer box brings two of them, at 22×22. They are excluded
/// rather than fixed because there is nothing here to fix: the app cannot resize
/// them without forking Material's text field, they carry no semantics
/// (`ExcludeSemantics`), and they are a grown-up's editing gesture on the one
/// screen a child is not meant to be driving. Excluding them by name, loudly, is
/// honest; quietly widening the audit's rules until they passed would not be.
bool _isTextSelectionHandle(Element element) {
  bool handle = false;
  element.visitAncestorElements((Element ancestor) {
    if (ancestor.widget.runtimeType.toString() == '_SelectionHandleOverlay') {
      handle = true;
      return false;
    }
    return true;
  });
  return handle;
}

/// Names a violation by its semantic label — "Zoom in", "Closest" — because
/// that is the one identifier this app gives every button on purpose, it is
/// unique, and it greps straight to the source.
///
/// Naming by enclosing widget type was tried first and abandoned: `Material`
/// and `InkWell` interpose their own private widgets (`_InkFeatures`,
/// `_FocusInheritedScope`) between a button and its own class, so "nearest
/// private ancestor" reports a framework internal for every hand-built button
/// in this app — which is all of them.
///
/// A target with **no** label still reports, as its widget type. That is not a
/// fallback so much as a second finding: an unlabelled button is already a
/// screen-reader bug, and seeing `InkWell is 30×20dp` in this output is a
/// useful way to find out.
String _describe(Element element) {
  final String label = _semanticLabelOf(element);
  return label.isEmpty ? '${element.widget.runtimeType}' : '"$label"';
}

String _semanticLabelOf(Element element) {
  String label = '';
  element.visitAncestorElements((Element ancestor) {
    final Widget widget = ancestor.widget;
    if (widget is Semantics && widget.properties.label != null) {
      label = widget.properties.label!;
      return false;
    }
    return true;
  });
  return label;
}
