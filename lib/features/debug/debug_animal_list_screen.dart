import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rockimals/core/animals/animal_system.dart';
import 'package:rockimals/data/models/asteroid.dart';
import 'package:rockimals/data/models/asteroid_feed.dart';
import 'package:rockimals/features/data/providers.dart';

/// The task-01 throwaway: every animal the pipeline produced, printed plainly,
/// to prove NASA → repository → providers → AnimalSystem works before any real
/// UI is built on top of it (spec 01 §5).
///
/// **This screen is deliberately not kid-facing and is deleted before anything
/// ships** — there is a plan item to remove it once the radar, Sky, and detail
/// screens land. That is what buys the one guardrail exception here: it prints
/// the **real designation** (`2011 EW`), which `CLAUDE.md:70` confines to the
/// parent-gated grown-up facts. Spec 01's own acceptance criterion is to
/// "compare 5–6 sample asteroids side-by-side with the prototype", and the
/// designation is the only thing that identifies which rock a row is — it is
/// also the seed [critter] hashes, so a naming bug is invisible without it. Do
/// not copy this into a real screen.
///
/// It draws the **full `asteroids` list**, not `todayList`, and the rows
/// visiting today are marked instead. The two rules differ offline (plan
/// decision 10: fourteen asteroids, seven of them "today"), and that difference
/// is the subtlest thing in the spine — showing one list and a marker proves
/// both at a glance, where showing either alone hides the other.
class DebugAnimalListScreen extends ConsumerWidget {
  const DebugAnimalListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('ROCKIMALS · debug')),
      body: ref
          .watch(asteroidFeedProvider)
          .when(
            // Bare on purpose. "Contacting NASA…" and its spinner are their own
            // plan item and their own screen; standing in for it here would
            // leave two of them to reconcile, and this one is deleted anyway.
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (Object error, StackTrace stack) => _LoadBroke(error: error),
            data: (AsteroidFeed feed) => _AnimalList(feed: feed),
          ),
    );
  }
}

class _AnimalList extends StatelessWidget {
  const _AnimalList({required this.feed});

  final AsteroidFeed feed;

  @override
  Widget build(BuildContext context) {
    // A set, not a `contains` per row: `todayList` is a sublist of `asteroids`,
    // so the naive form is quadratic on the one input that grows (a busy day is
    // 60+ rocks).
    final Set<String> visitingToday = feed.todayList
        .map((Asteroid a) => a.name)
        .toSet();

    return Column(
      children: <Widget>[
        _FeedHeader(feed: feed),
        Expanded(
          child: ListView.builder(
            itemCount: feed.asteroids.length,
            itemBuilder: (BuildContext context, int i) {
              final Asteroid asteroid = feed.asteroids[i];
              return _AnimalRow(
                asteroid: asteroid,
                visitingToday: visitingToday.contains(asteroid.name),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Which sky this is, in the developer's terms rather than a child's.
///
/// [FeedProvenance] is printed raw — `today` / `earlier` / `sample`. The
/// kid-facing wording for the same three cases is an open product decision on
/// the home-overlay item, and guessing it here would create a second place for
/// it to be decided.
class _FeedHeader extends StatelessWidget {
  const _FeedHeader({required this.feed});

  final AsteroidFeed feed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Text(
        '${feed.asteroids.length} animals · '
        '${feed.todayList.length} visiting · '
        '${feed.feedRange} · ${feed.provenance.name}',
        style: Theme.of(context).textTheme.labelLarge,
      ),
    );
  }
}

class _AnimalRow extends StatelessWidget {
  const _AnimalRow({required this.asteroid, required this.visitingToday});

  final Asteroid asteroid;

  /// Whether this rock is in `todayList` — the home strip's and the Challenge's
  /// pool (plan decision 10).
  final bool visitingToday;

  @override
  Widget build(BuildContext context) {
    final Critter c = critter(asteroid);

    return ListTile(
      leading: Text(c.animal.emoji, style: const TextStyle(fontSize: 30)),
      title: Text(visitingToday ? '${c.name} · today' : c.name),
      subtitle: Text(
        '${c.animal.sizeLabel} · ${asteroid.diaMax.round()} m wide · '
        'comes ${distLabel(asteroid.missLunar)} · '
        'power ⭐ ${powerStars(asteroid)} · ${flybyTag(asteroid).label}\n'
        '${asteroid.name} · ${asteroid.date}',
      ),
      isThreeLine: true,
    );
  }
}

/// [AsteroidRepository.loadData] promises never to throw — a dead network, a
/// rate-limited key, an empty feed, and a corrupt record all resolve to the
/// bundled sample sky (spec 01 §3). So this branch is unreachable, and reaching
/// it means that promise broke.
///
/// It is rendered loudly rather than quietly swapped for the sample set,
/// because a silent substitution here is precisely how the repository's bug
/// would be hidden from the one screen built to catch it.
class _LoadBroke extends StatelessWidget {
  const _LoadBroke({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        'loadData() threw, which it promises never to do:\n\n$error',
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}
