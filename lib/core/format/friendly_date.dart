import 'package:rockimals/data/fallback_asteroids.dart';

/// Turns a NASA calendar date into the relative language used in kid-facing
/// surfaces.
///
/// [today] is passed in rather than read from the device clock so every caller
/// agrees on the same day and the copy stays deterministic in tests. The
/// bundled sample sentinel deliberately becomes an em dash: it is not a real
/// flyby date and must never be presented as one.
String friendlyDate(String date, DateTime today) {
  if (date == sampleDate) return '—';

  final DateTime? parsed = DateTime.tryParse(date);
  if (parsed == null) return 'date to be confirmed';

  final DateTime targetDay = DateTime.utc(
    parsed.year,
    parsed.month,
    parsed.day,
  );
  final DateTime todayDay = DateTime.utc(today.year, today.month, today.day);
  final int daysAway = targetDay.difference(todayDay).inDays;

  return switch (daysAway) {
    < -1 => 'flew past ${-daysAway} days ago',
    -1 => 'flew past yesterday',
    0 => 'today',
    1 => 'tomorrow',
    _ => 'in $daysAway days',
  };
}

/// Formats the repository's two-date feed window without exposing its ISO
/// transport values to a child. A malformed window is kept equally non-raw.
String friendlyDateRange(String range, DateTime today) {
  final List<String> endpoints = range.split(' → ');
  if (endpoints.length != 2) return 'dates to be confirmed';

  return '${friendlyDate(endpoints[0], today)} → '
      '${friendlyDate(endpoints[1], today)}';
}
