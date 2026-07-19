import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rockimals/core/a11y/tap_target.dart';
import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/core/mascot/rusty.dart';
import 'package:rockimals/core/theme/palette.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/features/animals/widgets/animal_card.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/detail/detail_screen.dart';

/// The three ways the Sky list can be ordered (`skySort`, `index.html:472`).
/// Exactly one is active at a time, and [closest] is the default
/// (`skySort="close"`).
enum SkySort {
  /// Nearest first (`missLunar` ascending). The default.
  closest('Closest'),

  /// Largest first (`diaMax` descending).
  biggest('Biggest'),

  /// Quickest first (`velKps` descending).
  fastest('Fastest');

  const SkySort(this.label);

  /// The word on the toggle chip.
  final String label;
}

/// The Sky list, filtered then sorted — the pure heart of `renderSky`
/// (`index.html:486-488`), lifted out of the widget so the ordering is
/// unit-testable without pumping a frame (spec 07's "all three sorts order
/// correctly, unit-tested").
///
/// [source] is never mutated: it is the shared, unmodifiable `asteroids` list
/// (plan decision 9), and sorting it in place would move the radar's sky. The
/// filter runs first, exactly as the prototype does, but it filters on
/// [flybyTag] — **not** the raw `hazardous` flag the prototype used — so a rock
/// passing inside the Moon's distance counts as a close flyby even when NASA
/// has not flagged it (spec 07 / plan decision 2, the "close flyby" tone
/// guardrail).
List<Asteroid> skyAnimals(
  List<Asteroid> source, {
  required SkySort sort,
  required bool closeFlybysOnly,
}) {
  final List<Asteroid> list = <Asteroid>[
    for (final Asteroid a in source)
      if (!closeFlybysOnly || flybyTag(a) == FlybyTag.closeFlyby) a,
  ];
  list.sort(switch (sort) {
    SkySort.closest => (Asteroid a, Asteroid b) => a.missLunar.compareTo(
      b.missLunar,
    ),
    SkySort.biggest => (Asteroid a, Asteroid b) => b.diaMax.compareTo(a.diaMax),
    SkySort.fastest => (Asteroid a, Asteroid b) => b.velKps.compareTo(a.velKps),
  });
  return list;
}

/// The Sky tab — a scrollable list of every animal in the current data window,
/// with three sorts and a close-flyby filter (`specs/07-sky-tab.md`, prototype
/// `renderSky`, `index.html:473`).
///
/// **Reads the full `asteroids` list, not `todayList`** (spec 07 / plan
/// decision 9): the radar shows what is around Earth right now, the Sky tab is
/// how you browse the whole window. It is mounted only behind the loading gate
/// (`loading_screen.dart` builds the shell once the feed resolves), so the
/// three feed providers are read with `.requireValue`.
///
/// A `SliverList.builder` rather than a plain column of cards: spec 07 wants a
/// busy day of 60+ animals to scroll smoothly, so the cards are built lazily as
/// they scroll into view rather than all at once.
class SkyScreen extends ConsumerStatefulWidget {
  const SkyScreen({super.key});

  @override
  ConsumerState<SkyScreen> createState() => _SkyScreenState();
}

class _SkyScreenState extends ConsumerState<SkyScreen> {
  SkySort _sort = SkySort.closest;
  bool _closeFlybysOnly = false;

  /// A tapped card opens the Meet-an-Animal screen (`openDetail`,
  /// `index.html:467`) — the same push the radar's Meet button makes.
  void _openDetail(Asteroid asteroid) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => DetailScreen(asteroid: asteroid),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Asteroid> all = ref.watch(asteroidsProvider).requireValue;
    final String feedRange = ref.watch(feedRangeProvider).requireValue;
    final bool usingFallback = ref.watch(usingFallbackProvider).requireValue;

    final List<Asteroid> list = skyAnimals(
      all,
      sort: _sort,
      closeFlybysOnly: _closeFlybysOnly,
    );

    return SafeArea(
      // The bottom nav is the shell's own `bottomNavigationBar`, so it already
      // sits below this body — only the top status bar needs clearing here.
      bottom: false,
      child: CustomScrollView(
        slivers: <Widget>[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // `.h-title` (`index.html:35`, `477`).
                  Semantics(
                    header: true,
                    child: const Text(
                      'The Sky',
                      style: TextStyle(
                        color: Palette.ink,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  // `.h-sub` (`index.html:36`, `478`).
                  const Text(
                    'Every asteroid NASA is tracking in this window.',
                    style: TextStyle(color: Palette.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  _SortFilterBar(
                    sort: _sort,
                    closeFlybysOnly: _closeFlybysOnly,
                    onSort: (SkySort s) => setState(() => _sort = s),
                    onToggleFilter: () =>
                        setState(() => _closeFlybysOnly = !_closeFlybysOnly),
                  ),
                  const SizedBox(height: 8),
                  // The provenance caption (`index.html:483`), minus the
                  // prototype's "Time Machine ready" span — no such feature
                  // exists (spec 07). Reads "sample set" offline, else the real
                  // window; `usingFallback` picks between them because
                  // `feedRange` itself says "sample data" on the fallback path.
                  Text(
                    '📅 Showing ${usingFallback ? 'sample set' : feedRange}',
                    style: const TextStyle(color: Palette.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          if (list.isEmpty)
            // Reachable only with the filter on: behind the loading gate the
            // sky is never empty, so an empty `list` means the close-flyby
            // filter matched nothing — the prototype's `if(!list.length)`
            // (`index.html:489`).
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 28, 16, 24),
              sliver: SliverToBoxAdapter(child: _SkyEmptyState()),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList.builder(
                itemCount: list.length,
                itemBuilder: (BuildContext context, int i) {
                  final Asteroid a = list[i];
                  return Padding(
                    // `.acard{margin-bottom:10px}` (`index.html:65`).
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AnimalCard(asteroid: a, onTap: () => _openDetail(a)),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// The sort-and-filter bar (`.bar`, `index.html:77`, `479-482`). The
/// close-flyby filter leads, then the three mutually-exclusive sorts — the
/// prototype's order.
class _SortFilterBar extends StatelessWidget {
  const _SortFilterBar({
    required this.sort,
    required this.closeFlybysOnly,
    required this.onSort,
    required this.onToggleFilter,
  });

  final SkySort sort;
  final bool closeFlybysOnly;
  final ValueChanged<SkySort> onSort;
  final VoidCallback onToggleFilter;

  @override
  Widget build(BuildContext context) {
    // `.bar{display:flex;gap:8px;flex-wrap:wrap}` — a `Wrap` so the four chips
    // reflow onto a second row on a narrow phone instead of overflowing.
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        _Toggle(
          // Softened from the prototype's "⚠ Hazardous only" (spec 07 / plan
          // decision 2): the copy and the filter both speak "close flyby", and
          // the filter is `flybyTag`, not the raw `hazardous` flag.
          label: '👋 Close flybys only',
          semanticLabel: 'Close flybys only',
          selected: closeFlybysOnly,
          onTap: onToggleFilter,
        ),
        for (final SkySort s in SkySort.values)
          _Toggle(
            label: s.label,
            semanticLabel: s.label,
            selected: s == sort,
            onTap: () => onSort(s),
          ),
      ],
    );
  }
}

/// A `.toggle` pill (`index.html:78-79`) — the shared shape of both the filter
/// and the three sort chips.
///
/// Local to the Sky tab: it is the first and only `.toggle` consumer today, and
/// this plan waits for a second caller before hoisting a widget into shared
/// space (the `_AnimalAvatar` / `isCloseFlyby` rule). It is deliberately *not*
/// the radar's `.rchip` — that is a different pill with its own styling.
class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.semanticLabel,
    required this.selected,
    required this.onTap,
  });

  /// The visible chip text, emoji included.
  final String label;

  /// What a screen reader announces — [label] without the decorative emoji,
  /// spoken alongside the button/selected state (the pattern the nav and cards
  /// follow).
  final String semanticLabel;

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: Material(
          // `.toggle` idle is the card surface with a `--line` edge and muted
          // text; `.toggle.on` fills with `--accent` and sets `#1a0d05`
          // (`--onAccent`) on it (`index.html:78-79`).
          color: selected ? Palette.accent : Palette.card,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.all(Radius.circular(20)),
            side: BorderSide(color: selected ? Palette.accent : Palette.line),
          ),
          child: InkWell(
            borderRadius: const BorderRadius.all(Radius.circular(20)),
            onTap: onTap,
            // The pill stays 31dp — a sort chip padded to 48 would out-weigh
            // the cards it sorts — and [TapTarget] grows only what answers a
            // touch. Four of these sit in a row a child has to pick between.
            child: TapTarget(
              child: Padding(
                // `.toggle{padding:7px 12px}` (`index.html:78`).
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected ? Palette.onAccent : Palette.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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

/// The friendly empty state when the close-flyby filter matches nothing
/// (`.empty`, `index.html:164`, `489`). The prototype's "No hazardous
/// asteroids…" wording is softened per the tone guardrail (spec 07 /
/// `CLAUDE.md:64`).
class _SkyEmptyState extends StatelessWidget {
  const _SkyEmptyState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        children: <Widget>[
          // Spec 06 puts Rusty on the empty states
          // (`specs/06-title-polish-safety.md:18`); the prototype's `.empty` is
          // text alone. Decoration — a painter publishes no semantics — so the
          // good news below is what a screen reader hears.
          Rusty(size: kRustyHalfSize),
          SizedBox(height: 16),
          Text(
            'No close flybys in this window — good news! 🌍',
            textAlign: TextAlign.center,
            style: TextStyle(color: Palette.muted, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
