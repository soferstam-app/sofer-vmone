/// When one working day ends and the next begins.
///
/// A sofer who finishes at 01:00 still thinks of it as the previous day's work;
/// one who starts before dawn thinks of it as the new day already. And a sofer
/// who works by the Hebrew calendar throughout may want the day to turn over at
/// nightfall, the way the Hebrew date itself does.
///
/// All four answers are legitimate, so this is a setting rather than an
/// assumption baked into the code.
library;

import 'package:kosher_dart/kosher_dart.dart';

/// What marks the start of a new working day.
enum DayBoundary {
  /// Midnight — the civil convention, and the default.
  midnight,

  /// Sunset.
  sunset,

  /// Nightfall, when the Hebrew date itself turns over.
  nightfall,

  /// An hour the writer picks, e.g. 02:00 for someone who works late or 05:00
  /// for someone who starts before dawn.
  fixedHour;

  String get label => switch (this) {
        DayBoundary.midnight => 'חצות הלילה',
        DayBoundary.sunset => 'שקיעה',
        DayBoundary.nightfall => 'צאת הכוכבים',
        DayBoundary.fixedHour => 'שעה קבועה',
      };

  String get explanation => switch (this) {
        DayBoundary.midnight => '00:00, כמו בלוח האזרחי',
        DayBoundary.sunset => 'כתיבה אחרי השקיעה נרשמת ליום הבא',
        DayBoundary.nightfall =>
          'תחילת היום העברי — כתיבה אחרי צאת הכוכבים נרשמת ליום הבא',
        DayBoundary.fixedHour => 'שעה שאתה בוחר',
      };

  /// Whether the boundary falls in the evening, so that work after it belongs
  /// to the *next* day rather than the current one.
  bool get isEvening =>
      this == DayBoundary.sunset || this == DayBoundary.nightfall;

  static DayBoundary fromName(String? name, DayBoundary fallback) =>
      DayBoundary.values
          .firstWhere((b) => b.name == name, orElse: () => fallback);
}

/// The day-boundary setting, stored as one value.
class DayStart {
  static const int currentSchemaVersion = 1;

  final DayBoundary boundary;

  /// Used only when [boundary] is [DayBoundary.fixedHour]. 0–23.
  final int hour;

  const DayStart({this.boundary = DayBoundary.midnight, this.hour = 0});

  static const DayStart midnight = DayStart();

  DayStart copyWith({DayBoundary? boundary, int? hour}) => DayStart(
        boundary: boundary ?? this.boundary,
        hour: (hour ?? this.hour).clamp(0, 23),
      );

  String get summary => boundary == DayBoundary.fixedHour
      ? '${hour.toString().padLeft(2, '0')}:00'
      : boundary.label;

  Map<String, dynamic> toJson() => {
        'schemaVersion': currentSchemaVersion,
        'boundary': boundary.name,
        'hour': hour,
      };

  /// Tolerant of missing and unknown keys, so a file from any version opens.
  factory DayStart.fromJson(Map<String, dynamic> json) {
    final hour = json['hour'] is int ? (json['hour'] as int).clamp(0, 23) : 0;
    return DayStart(
      boundary: DayBoundary.fromName(
        json['boundary'] as String?,
        // Before this setting existed there was only a rollover hour: a
        // non-zero one meant the writer had deliberately moved the boundary.
        hour > 0 ? DayBoundary.fixedHour : DayBoundary.midnight,
      ),
      hour: hour,
    );
  }

  /// Builds the setting from the older standalone rollover hour.
  factory DayStart.fromRolloverHour(int hour) => hour > 0
      ? DayStart(boundary: DayBoundary.fixedHour, hour: hour.clamp(0, 23))
      : DayStart.midnight;
}

/// Sunset and nightfall for the app's reference location.
///
/// The app has no location permission and does not ask for one. Israel is small
/// enough that a single reference point is accurate to a couple of minutes
/// anywhere in the country, which is far finer than a decision about which day
/// a writing session belongs to needs.
class HebrewClock {
  const HebrewClock._();

  /// Jerusalem's coordinates at sea level — the customary reference, and close
  /// to the national average once elevation is left out.
  static const double latitude = 31.778;
  static const double longitude = 35.235;
  static const String locationName = 'ארץ ישראל (ממוצע)';

  /// Sunset on the calendar date of [date], in the device's local clock.
  ///
  /// Returns null only where the sun does not set, which cannot happen at this
  /// latitude — the null is carried through so callers degrade to midnight
  /// rather than crash if the reference point is ever changed.
  static DateTime? sunset(DateTime date) => _calendarFor(date).getSunset();

  /// Nightfall on the calendar date of [date], in the device's local clock.
  static DateTime? nightfall(DateTime date) => _calendarFor(date).getTzais();

  /// The instant on [date]'s calendar day at which the working day turns over,
  /// or null when the boundary is not a time of day (midnight).
  static DateTime? boundaryOn(DateTime date, DayStart dayStart) {
    switch (dayStart.boundary) {
      case DayBoundary.midnight:
        return null;
      case DayBoundary.fixedHour:
        return DateTime(date.year, date.month, date.day, dayStart.hour);
      case DayBoundary.sunset:
        return sunset(date);
      case DayBoundary.nightfall:
        return nightfall(date);
    }
  }

  static ZmanimCalendar _calendarFor(DateTime date) {
    final midnight = DateTime(date.year, date.month, date.day);
    final location = GeoLocation.setLocation(
        locationName, latitude, longitude, midnight);
    return ZmanimCalendar.intGeolocation(location);
  }
}
