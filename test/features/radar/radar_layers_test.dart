import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/features/radar/radar_layers.dart';

/// The five toggle chips' state, in isolation from the canvas — which chip is
/// lit, what a toggle does to it, and that flipping one leaves the rest alone.
void main() {
  group('RadarLayers', () {
    test('opens on the prototype\'s state: Close-flybys off, the rest on', () {
      // `showHaz:false … showLabels:true, showRings:true, showMoon:true,
      // showPlanets:true` (`index.html:625`). The one chip that starts unlit is
      // the filter, because the sky should open showing every animal.
      const RadarLayers layers = RadarLayers();

      expect(layers.isOn(RadarLayer.closeFlybys), isFalse);
      expect(layers.isOn(RadarLayer.planets), isTrue);
      expect(layers.isOn(RadarLayer.labels), isTrue);
      expect(layers.isOn(RadarLayer.rings), isTrue);
      expect(layers.isOn(RadarLayer.moon), isTrue);
    });

    test('the chips read in the prototype\'s own order', () {
      // The row maps over `RadarLayer.values` the way `radarChips()` maps over
      // `defs` (`index.html:670`), so the enum order *is* the on-screen order.
      // Pinned so a reorder that would silently rearrange the chip row fails
      // here instead.
      expect(RadarLayer.values, <RadarLayer>[
        RadarLayer.closeFlybys,
        RadarLayer.planets,
        RadarLayer.labels,
        RadarLayer.rings,
        RadarLayer.moon,
      ]);
    });

    test('the first chip says Close flybys, never Hazards', () {
      // Plan decision 2 and `CLAUDE.md:64`: the radar must never leak NASA's word
      // for it. The label is a plain string, so the guardrail is cheap to pin and
      // worth pinning — this is the one chip a careless edit would name wrong.
      expect(RadarLayer.closeFlybys.label, '👋 Close flybys');
      for (final RadarLayer layer in RadarLayer.values) {
        expect(layer.label.toLowerCase(), isNot(contains('hazard')));
      }
    });

    test('toggling a chip flips only that chip', () {
      // `Radar[k] = !Radar[k]` (`index.html:672`) — one chip at a time. The other
      // four must be untouched, or a child turning off the Moon would find the
      // rings gone too.
      const RadarLayers layers = RadarLayers();

      final RadarLayers noRings = layers.toggle(RadarLayer.rings);
      expect(noRings.isOn(RadarLayer.rings), isFalse);
      expect(noRings.isOn(RadarLayer.moon), isTrue);
      expect(noRings.isOn(RadarLayer.planets), isTrue);
      expect(noRings.isOn(RadarLayer.labels), isTrue);
      expect(noRings.isOn(RadarLayer.closeFlybys), isFalse);
    });

    test('toggling the Close-flybys chip turns the filter on and off', () {
      const RadarLayers layers = RadarLayers();
      final RadarLayers filtered = layers.toggle(RadarLayer.closeFlybys);

      expect(filtered.closeFlybysOnly, isTrue);
      expect(filtered.toggle(RadarLayer.closeFlybys).closeFlybysOnly, isFalse);
    });

    test('toggling twice returns the original', () {
      // The chip is a plain flip, so two taps are a no-op — and because the value
      // has `==`, that is a value a test can assert rather than a fact to trust.
      const RadarLayers layers = RadarLayers();
      for (final RadarLayer layer in RadarLayer.values) {
        expect(layers.toggle(layer).toggle(layer), layers);
      }
    });

    test('equality is by every field, so the painter repaints on any change', () {
      // [RadarPainter.shouldRepaint] leans on this: two layer sets that differ in
      // one chip must be unequal, or toggling that chip would draw nothing new.
      const RadarLayers layers = RadarLayers();
      for (final RadarLayer layer in RadarLayer.values) {
        expect(layers.toggle(layer), isNot(layers));
      }
      // And two equal values agree on their hash — the half of the contract a
      // `Set`/`Map` actually relies on.
      expect(const RadarLayers().hashCode, const RadarLayers().hashCode);
    });
  });
}
