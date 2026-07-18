import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rockimals/core/theme/palette.dart';
import 'package:rockimals/features/radar/radar_focus.dart';
import 'package:rockimals/features/radar/radar_view.dart';
import 'package:rockimals/features/sky/sky_screen.dart';
import 'package:rockimals/features/watchlist/watchlist_screen.dart';

/// The frame every screen in the app lives inside: four tabs and the bottom nav
/// that switches them (`index.html:302-307`).
///
/// **No spec owns this.** Spec 01 is explicitly "no UI beyond a debug screen",
/// and specs 02 / 05 / 07 each build only their own tab's *contents* — so the
/// thing that holds them is nobody's, which is why it is its own plan item and
/// why the prototype is the only authority for it. Spec 08 pins the one rule
/// that outlives this file: the nav is **fixed at four** tabs
/// (`specs/08-settings-about.md:40-42`) — Settings is a row on the Profile tab,
/// not a fifth tab. Anything that wants a home in the nav later has to displace
/// something.
///
/// The tabs are an [IndexedStack] rather than a rebuilt body, because the item
/// asks for each tab's state to stay alive: a child who scrolls halfway down the
/// Sky, taps Profile to check their points, and comes back should find the Sky
/// where they left it. The cost is that all four are mounted from the first
/// frame — which is also what makes the "pause the render loop off-tab" item
/// (`specs/02-live-radar.md:29`) *necessary* rather than automatic: an offstage
/// [IndexedStack] child keeps its tickers running, so the radar will not stop
/// drawing just because it is not the visible tab. That item is now the
/// per-tab [TickerMode] in [build] below — it does the stopping; this
/// [IndexedStack] only makes sure there is something alive to stop.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  /// Radar, matching the prototype's `class="on"` on the first nav button
  /// (`index.html:303`). The radar is the app: it is what a child opens
  /// Rockimals to see, and `specs/02-live-radar.md:4` calls it the home tab.
  int _index = _radarTab;

  /// The Radar tab's index — the home tab, and where Show-on-radar lands
  /// (`switchTab("today")` in `openRadarFocus`, `index.html:657`).
  static const int _radarTab = 0;

  @override
  Widget build(BuildContext context) {
    // **Show-on-radar's tab half** (`switchTab("today")`, `index.html:657`;
    // `specs/03-meet-animal.md:23`). The detail screen publishes a focus
    // request; this brings the Radar tab to the front so the child lands on the
    // animal they picked. The selecting and re-centring is the radar's own
    // (it listens to the same request from inside the IndexedStack, so it reacts
    // even while hidden here) — this only switches the tab.
    //
    // `listen`, not `watch`: this reacts to a request without rebuilding the
    // whole shell on unrelated provider churn, and it fires only on a *change*,
    // so a held request never re-switches the tab on a later rebuild.
    ref.listen<RadarFocus?>(radarFocusProvider, (
      RadarFocus? previous,
      RadarFocus? next,
    ) {
      if (next != null && _index != _radarTab) {
        setState(() => _index = _radarTab);
      }
    });

    return Scaffold(
      // **Each tab is wrapped in a `TickerMode` gated on whether it is the shown
      // one — this is the "pause the render loop off-tab" item
      // (`specs/02-live-radar.md:29`), and it lives here because the problem is
      // the shell's.** An [IndexedStack] keeps every child mounted and its
      // tickers running (see the class doc), so the radar would go on drawing
      // sixty frames a second from behind the Sky tab. `SingleTickerProvider`-
      // backed tickers mute themselves when their `TickerMode` is off, so the
      // radar's frame clock simply stops being called the moment it is not the
      // visible tab, and starts again on return — the port of the prototype's
      // `if(view-today hidden){Radar.running=false;return;}` (`index.html:729`).
      //
      // Muting rather than tearing down is what makes the resume smooth: the
      // ticker keeps its start time across the gap, so the first frame back
      // reports a large elapsed — which [FrameClock]'s `min(0.05, …)` clamp
      // absorbs into a single ordinary step, exactly as the prototype relies on
      // its own never-reset `Radar.last`. Nothing here resets the clock.
      //
      // Gating *every* tab, not just the radar, is deliberate: it is the general
      // rule an [IndexedStack] wants — an offstage tab's animations should not
      // run — so the games and reactions that land in the other tabs inherit the
      // same pause for free rather than each re-discovering this.
      body: IndexedStack(
        index: _index,
        children: <Widget>[
          for (int i = 0; i < _tabs.length; i++)
            TickerMode(enabled: i == _index, child: _tabs[i].body),
        ],
      ),
      bottomNavigationBar: _NavBar(
        index: _index,
        onSelect: (int i) => setState(() => _index = i),
      ),
    );
  }
}

/// The four tabs, in the prototype's order (`index.html:303-306`).
///
/// "Watchlist" is kept verbatim even though `CLAUDE.md:64` rewrites "track" →
/// "follow": the guardrail is about not sounding like an observatory tracking a
/// threat, and `specs/08-settings-about.md:41` names this tab Watchlist in the
/// one place any spec names the nav at all. The *verb* stays "follow"
/// (`specs/03-meet-animal.md:23`) and the list itself is titled "My Animals"
/// (`specs/05-rewards-collection.md:36`) — this is only the nav label.
const List<_NavTab> _tabs = <_NavTab>[
  _NavTab(emoji: '🛰️', label: 'Radar', body: RadarView()),
  _NavTab(emoji: '🌌', label: 'Sky', body: SkyScreen()),
  _NavTab(emoji: '⭐', label: 'Watchlist', body: WatchlistScreen()),
  _NavTab(
    emoji: '👤',
    label: 'Profile',
    body: _TabStub(emoji: '👤', title: 'My Space Zoo'),
  ),
];

class _NavTab {
  const _NavTab({required this.emoji, required this.label, required this.body});

  final String emoji;
  final String label;
  final Widget body;
}

// The nav's palette (`.nav` rules, `index.html:83-87`). The three that are CSS
// variables now come from `Palette` — this file used to declare its own copies,
// which is what the plan's "extract the palette" item existed to undo.
//
// The nav uses, in order: `--line2` for its 1px top rule, `--muted` for the idle
// label, and `--accent2` for the selected one — `.nav button.on` being the
// *only* thing that marks the selected tab in the prototype. The emoji does not
// change (a colour glyph ignores the text colour that highlights the label), and
// there is no pill, underline, or indicator to port.

/// `rgba(10,20,38,.94)` — .94 alpha rounds to 240 (`0xF0`).
///
/// **Stays local, and that is the same call `radar_painter.dart` makes about its
/// ring strokes.** This is not a `:root` variable; it is a bare literal the nav
/// declares for itself, so `Palette` — whose membership test is "the prototype
/// named it" — is not its home. It does recur once, at `rgba(10,20,38,.82)` on
/// the radar's bottom bar (`index.html:187`), which is the one thing that could
/// change the answer: when the "radar toggle chips and play/pause" item ports
/// that bar, this becomes a base colour two chrome surfaces share at different
/// alphas, and *then* it is worth naming. One consumer is not enough to know
/// whether the shared thing is the colour or the coincidence.
const Color _navSurface = Color(0xF00A1426);

class _NavBar extends StatelessWidget {
  const _NavBar({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _navSurface,
      // The prototype is a fixed 390×844 browser frame and has no concept of a
      // home indicator; a real phone does, and without this the labels sit
      // under it. Not a deviation from the prototype so much as a question it
      // was never asked.
      child: SafeArea(
        top: false,
        child: SizedBox(
          // `height:70px` with the page's global `box-sizing:border-box`
          // (`index.html:12`), so the 1px rule is inside the 70, not added to
          // it.
          height: 70,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Palette.line2)),
            ),
            child: Row(
              children: <Widget>[
                for (int i = 0; i < _tabs.length; i++)
                  Expanded(
                    child: _NavButton(
                      tab: _tabs[i],
                      selected: i == index,
                      onTap: () => onSelect(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final _NavTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        // The prototype kills the tap highlight, but that is
        // `-webkit-tap-highlight-color:transparent` (`index.html:12`) — a global
        // reset that removes the mobile browser's grey box, not a decision that
        // taps should give no feedback. A child needs to see the tap land, so
        // the ripple stays.
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            // Excluded from semantics so a screen reader announces "Radar", not
            // "satellite Radar" — the emoji is decoration, and the label below
            // already says the same thing in words.
            ExcludeSemantics(
              child: Text(
                tab.emoji,
                style: const TextStyle(fontSize: 19, height: 1),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              tab.label,
              style: TextStyle(
                color: selected ? Palette.accent2 : Palette.muted,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What a tab shows until its own task builds it.
///
/// Worded for a child rather than a developer ("coming soon", not "not
/// implemented"), because these are reachable in any build the shell is in and
/// `CLAUDE.md:63` asks for a gentle tone everywhere — but each is deleted by the
/// task that owns its tab, so none of this copy is load-bearing.
class _TabStub extends StatelessWidget {
  const _TabStub({required this.emoji, required this.title});

  final String emoji;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(emoji, style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text('$title is coming soon', style: const TextStyle(fontSize: 16)),
        ],
      ),
    );
  }
}
