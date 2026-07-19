import 'package:flutter/painting.dart';

/// `linear-gradient(150deg,#17325c,#0e2244)` — the fill every "this panel is the
/// special one" surface wears.
///
/// The prototype uses it five times and never names it: `.hero`
/// (`index.html:45`), `.lvlcard` (`:145`), `.gfeat` (`:210`), `.badgePop .bcard`
/// (`:249`), and `.ptsCard` (`:262`). Four of those are ported, and each carried
/// its own local copy of the two hex values until this existed — the Play hub's
/// points card and its featured daily tile, the badge popup's celebration card,
/// and the Profile's points hero.
///
/// **Why this is not in `Palette`, and why it is beside it.** `Palette`'s stated
/// membership test is that *the prototype named it* — its `:root` block is the
/// prototype's own decision about which colours are shared, and widening that
/// test to "two Dart files happen to want it" would let one-off literals in. The
/// prototype names this nothing, so it fails that test and stays out. But it is
/// plainly not a one-off either: five restatements is the prototype telling us
/// this is shared while lacking the vocabulary to say so. So it lives in
/// `core/theme/` — the tokens directory `Palette` heads — in its own library,
/// which keeps the membership rule intact rather than bending it.
///
/// **Why `core/` at all rather than a feature.** The four consumers live in
/// three different features (`games`, `rewards`, `profile`), so any feature that
/// owned it would make the other two import a sibling for something that is not
/// about that sibling. That is the same seam `Obar` (`core/chrome/obar.dart`)
/// was extracted to close, and
/// this is the token half of the answer `core/chrome/` gave for widgets.
///
/// `topLeft → bottomRight` approximates CSS's 150° — a line pointing down and
/// slightly right. All four copies made that same approximation independently,
/// so nothing changes visually by sharing it.
const LinearGradient kFeaturedGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: <Color>[Color(0xFF17325C), Color(0xFF0E2244)],
);
