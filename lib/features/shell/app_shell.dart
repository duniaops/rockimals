import 'package:flutter/material.dart';
import 'package:rockimals/features/debug/debug_animal_list_screen.dart';

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
/// drawing just because it is not the visible tab. That item does the stopping;
/// this one only makes sure there is something alive to stop.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  /// Radar, matching the prototype's `class="on"` on the first nav button
  /// (`index.html:303`). The radar is the app: it is what a child opens
  /// Rockimals to see, and `specs/02-live-radar.md:4` calls it the home tab.
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: <Widget>[for (final _NavTab tab in _tabs) tab.body],
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
  // The task-01 throwaway sits in the Radar slot rather than a stub, because it
  // is the only thing in the app that proves NASA → repository → providers →
  // AnimalSystem reaches a screen, and there is a plan item to delete it once
  // the real radar lands. A stub here would strand it: unreachable, still in
  // the tree, still on the ledger as "remove later" — i.e. removed from the app
  // without the item that is supposed to remove it. The radar's own item
  // replaces this entry.
  _NavTab(emoji: '🛰️', label: 'Radar', body: DebugAnimalListScreen()),
  _NavTab(emoji: '🌌', label: 'Sky', body: _TabStub(emoji: '🌌', title: 'Sky')),
  _NavTab(
    emoji: '⭐',
    label: 'Watchlist',
    body: _TabStub(emoji: '⭐', title: 'My Animals'),
  ),
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

// The nav's palette, ported from the prototype's CSS variables
// (`index.html:9-10`) and `.nav` rules (`index.html:83-87`). Private and local
// on purpose: this is the first screen to need the prototype's colours, and
// hoisting a shared palette off the back of one nav bar would be guessing which
// of the twelve variables the radar and the cards actually want. There is a
// plan item to extract it once a second surface asks.
//
/// `rgba(10,20,38,.94)` — .94 alpha rounds to 240 (`0xF0`).
const Color _navSurface = Color(0xF00A1426);

/// `--line2`, the 1px top rule.
const Color _navBorder = Color(0xFF1C3457);

/// `--muted`, the idle label.
const Color _navIdle = Color(0xFF93A8CA);

/// `--accent2`, i.e. `.nav button.on` — the *only* thing that marks the selected
/// tab in the prototype. The emoji does not change (a colour glyph ignores the
/// text colour that highlights the label), and there is no pill, underline, or
/// indicator to port.
const Color _navSelected = Color(0xFFFF7A45);

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
              border: Border(top: BorderSide(color: _navBorder)),
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
                color: selected ? _navSelected : _navIdle,
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
