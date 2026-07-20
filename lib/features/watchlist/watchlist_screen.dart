import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rockimals/core/format/friendly_date.dart';
import 'package:rockimals/core/mascot/rusty.dart';
import 'package:rockimals/core/theme/palette.dart';
import 'package:rockimals/data/fallback_asteroids.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/features/animals/widgets/animal_card.dart';
import 'package:rockimals/features/data/providers.dart';
import 'package:rockimals/features/detail/detail_screen.dart';

/// The followed animals, closest first — the pure heart of `renderWatch`
/// (`index.html:499`), lifted out of the widget so the filter and the ordering
/// are unit-testable without pumping a frame.
///
/// [source] is never mutated: it is the shared, unmodifiable `asteroids` list
/// (plan decision 9), and sorting it in place would move the radar's sky.
///
/// **The intersection is one-directional on purpose, and it is the prototype's
/// behaviour rather than an oversight.** [follows] is a set of real designations
/// that outlives any one feed window (plan decision 12), so a child can be
/// following a rock that is not in *today's* sky — NASA's window has moved on.
/// The prototype filters `asteroids` by the follow set (`watch.has(a.name)`),
/// which drops those quietly, and this does the same. Showing them would mean
/// inventing a card with no size, no distance, and no approach to put on it —
/// there is nothing persisted about a followed animal except its designation.
/// The follow is *not* forgotten: it stays in the store, and the animal
/// reappears the day its rock is back in the window.
List<Asteroid> followedAnimals(List<Asteroid> source, Set<String> follows) {
  final List<Asteroid> list = <Asteroid>[
    for (final Asteroid a in source)
      if (follows.contains(a.name)) a,
  ];
  // `sort((a,b) => a.missLunar - b.missLunar)` (`index.html:499`) — closest
  // first, which is the one ordering that answers "who is visiting next?"
  list.sort((Asteroid a, Asteroid b) => a.missLunar.compareTo(b.missLunar));
  return list;
}

/// The caption a followed animal's approach date is shown as, or `⏳ approach —`
/// for a bundled sample record (`index.html:506`).
///
/// The em-dash is not a formatting nicety — it is a refusal. A sample record
/// carries [sampleDate] rather than a real date precisely so nothing can pass
/// it off as live data (`fallback_asteroids.dart:202`), and printing the literal
/// string "sample" here would do exactly that in a child's reading of it.
String approachNote(String date, DateTime today) =>
    '⏳ approach ${friendlyDate(date, today)}';

/// The My Animals tab — every animal a child follows, closest first, with the
/// approach note the Sky tab's cards do not carry (`specs/05-rewards-collection
/// .md:35-37`, prototype `renderWatch`, `index.html:497-510`).
///
/// A [ConsumerWidget], where the Sky tab next to it is a
/// [ConsumerStatefulWidget]: this screen has no local UI state at all. Its
/// entire content is a function of two providers, and the sort is fixed at
/// closest-first — there are no chips to remember. Watching [followsProvider]
/// (a `Notifier`, written the same frame a Follow button is tapped) is what
/// makes the item's "populates it immediately" true without this screen knowing
/// anything about where the follow came from: the radar's HUD card and the
/// detail screen both write that provider, and neither knows this tab exists.
///
/// Mounted only behind the loading gate (`loading_screen.dart` builds the shell
/// once the feed resolves), so the sky is read with `.requireValue` — the same
/// entitlement [SkyScreen] claims.
class WatchlistScreen extends ConsumerWidget {
  const WatchlistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Asteroid> all = ref.watch(asteroidsProvider).requireValue;
    final Set<String> follows = ref.watch(followsProvider);
    final DateTime today = ref.watch(dayClockProvider)();
    final List<Asteroid> list = followedAnimals(all, follows);

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
                  // `.h-title` (`index.html:35`, `500`). "My Animals", not the
                  // nav's "Watchlist" — the list is titled the way a child would
                  // say it, and the nav label is only the nav's
                  // (`app_shell.dart`).
                  Semantics(
                    header: true,
                    child: const Text(
                      'My Animals',
                      style: TextStyle(
                        color: Palette.ink,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  // `.h-sub` (`index.html:36`, `500`).
                  const Text(
                    "The space animals you're following. 🐾",
                    style: TextStyle(color: Palette.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          if (list.isEmpty)
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 24),
              sliver: SliverToBoxAdapter(child: _WatchlistEmptyState()),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList.builder(
                itemCount: list.length,
                itemBuilder: (BuildContext context, int i) {
                  final Asteroid a = list[i];
                  final String note = approachNote(a.date, today);
                  return Padding(
                    // `.acard{margin-bottom:10px}` (`index.html:65`).
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AnimalCard(
                      asteroid: a,
                      onTap: () => _openDetail(context, a),
                      footer: _ApproachNote(note: note),
                      footerLabel: note,
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  /// A tapped card opens the Meet-an-Animal screen — `acardEl`'s own
  /// `onclick = () => openDetail(a)` (`index.html:467`), which the watchlist
  /// inherits by reusing the card. The same push the Sky tab makes.
  void _openDetail(BuildContext context, Asteroid asteroid) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => DetailScreen(asteroid: asteroid),
      ),
    );
  }
}

/// The approach-date caption My Animals appends beneath a card's flyby badge
/// (`index.html:505-507`): `color:var(--accent2);font-size:11px;font-weight:700;
/// margin-top:4px`.
///
/// The only thing a watchlist card shows that a Sky card does not, and the
/// reason [AnimalCard] has a [AnimalCard.footer] slot at all — this is the
/// "next-approach note" of `specs/05-rewards-collection.md:36`.
class _ApproachNote extends StatelessWidget {
  const _ApproachNote({required this.note});

  final String note;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // `margin-top:4px` (`index.html:505`), which sits below the badge the
      // card has already spaced 6px under the meta.
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        note,
        style: const TextStyle(
          color: Palette.accent2,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),
    );
  }
}

/// The empty state a child sees before their first follow (`.empty`,
/// `index.html:164`, `502`) — an invitation, not a report of nothing.
///
/// It is the only screen in the app that is empty by design rather than by
/// failure, so it is the one place the follow gesture has to be *taught*: a
/// child who has never tapped ⭐ Follow has no way to know this tab is where it
/// leads. The prototype's copy is ported verbatim for that reason.
class _WatchlistEmptyState extends StatelessWidget {
  const _WatchlistEmptyState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      child: Column(
        children: <Widget>[
          // The prototype's `🐾` (`index.html:502`), grown into the mascot —
          // spec 06 puts Rusty on the empty states
          // (`specs/06-title-polish-safety.md:18`). Still decoration, and still
          // silent: a painter publishes no semantics, so a screen reader reads
          // the invitation, exactly as the old `ExcludeSemantics` arranged.
          Rusty(size: kRustyHalfSize),
          SizedBox(height: 16),
          Text(
            "You're not following any space animals yet.\n"
            'Tap any animal and press ⭐ Follow to add it here!',
            textAlign: TextAlign.center,
            style: TextStyle(color: Palette.muted, fontSize: 14, height: 1.5),
          ),
        ],
      ),
    );
  }
}
