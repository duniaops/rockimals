import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rockimals/data/models/asteroid.dart';

/// A request to bring one animal up on the radar — the detail screen's **Show
/// on radar** action (`openRadarFocus`, `index.html:657`; `specs/03-meet-
/// animal.md:23`).
///
/// **This is a one-shot event held as state, and the wrapper is what makes it
/// one.** The prototype's `openRadarFocus(a)` closes the detail, switches to the
/// radar tab, and selects `a` — three widgets' worth of work here (the detail
/// pops, the shell switches tabs, the radar selects and re-centres), and the way
/// they coordinate without knowing about each other is a shared provider each of
/// them listens to. Two of them react to *the same* change, so nothing consumes
/// or clears it: the request simply holds the last-focused animal, and a
/// `ref.listen` fires only on a change, so a held value never re-selects on a
/// rebuild.
///
/// [RadarFocus] carries no value equality on purpose. A child can open the same
/// animal's detail twice and press Show on radar each time — and the second
/// press must still re-centre the field, because between the two they may have
/// spun and zoomed away again. If this held a bare [Asteroid], the second
/// `focus` of the same instance would be `identical` to the first and publish
/// no change; a fresh [RadarFocus] each time is a new event whichever way
/// Riverpod compares.
@immutable
class RadarFocus {
  const RadarFocus(this.asteroid);

  /// The animal to select and centre on. Identified by its designation
  /// everywhere it lands (plan decision 12) — the radar matches it against the
  /// field's own list by [Asteroid.name], never by instance.
  final Asteroid asteroid;
}

/// Holds the latest [RadarFocus] request, or null before anything has been
/// focused. Written through [focus]; read via `ref.listen` by the shell (which
/// switches to the Radar tab) and the radar field (which selects the animal and
/// resets the view).
class RadarFocusNotifier extends Notifier<RadarFocus?> {
  @override
  RadarFocus? build() => null;

  /// Publish a request to focus [asteroid] on the radar. A new [RadarFocus]
  /// every call, so two requests for the same animal are still two events (see
  /// the class doc).
  void focus(Asteroid asteroid) => state = RadarFocus(asteroid);
}

/// The Show-on-radar channel. Its own provider rather than a field on the radar
/// or the shell because the request crosses all three — the detail publishes,
/// the shell and the radar listen — and none of them owns the others.
final NotifierProvider<RadarFocusNotifier, RadarFocus?> radarFocusProvider =
    NotifierProvider<RadarFocusNotifier, RadarFocus?>(
      RadarFocusNotifier.new,
      name: 'radarFocus',
    );
