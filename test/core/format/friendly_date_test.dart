import 'package:flutter_test/flutter_test.dart';
import 'package:rockimals/core/format/friendly_date.dart';
import 'package:rockimals/data/fallback_asteroids.dart';

void main() {
  final DateTime today = DateTime(2026, 7, 15);

  group('friendlyDate', () {
    test('uses gentle language for past, present, and future flybys', () {
      expect(friendlyDate('2026-07-13', today), 'flew past 2 days ago');
      expect(friendlyDate('2026-07-14', today), 'flew past yesterday');
      expect(friendlyDate('2026-07-15', today), 'today');
      expect(friendlyDate('2026-07-16', today), 'tomorrow');
      expect(friendlyDate('2026-07-17', today), 'in 2 days');
    });

    test('does not present the bundled sample sentinel as a real date', () {
      expect(friendlyDate(sampleDate, today), '—');
    });

    test('never exposes malformed date data as a raw transport value', () {
      expect(friendlyDate('not-a-date', today), 'date to be confirmed');
    });
  });

  test('friendlyDateRange formats both endpoints', () {
    expect(
      friendlyDateRange('2026-07-15 → 2026-07-17', today),
      'today → in 2 days',
    );
  });
}
