import 'package:intl/intl.dart';

/// Weight is stored in kilograms everywhere; conversion happens at the edges.
class Units {
  const Units._();
  static const kgPerLb = 0.45359237;

  static bool isImperial(String? units) => units == 'imperial';
  static String weightLabel(String? units) => isImperial(units) ? 'lb' : 'kg';

  static double fromKg(double kg, String? units) => isImperial(units) ? kg / kgPerLb : kg;
  static double toKg(double value, String? units) => isImperial(units) ? value * kgPerLb : value;

  /// Display value rounded to a gym-friendly precision (0.25 kg / 0.5 lb).
  static String weight(double? kg, String? units, {bool withUnit = true}) {
    if (kg == null) return '—';
    final v = fromKg(kg, units);
    final step = isImperial(units) ? 0.5 : 0.25;
    final r = (v / step).round() * step;
    final s = trimNum(r);
    return withUnit ? '$s ${weightLabel(units)}' : s;
  }

  static String trimNum(num v, {int maxDecimals = 2}) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    var s = v.toStringAsFixed(maxDecimals);
    while (s.contains('.') && (s.endsWith('0') || s.endsWith('.'))) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  static String height(double? cm, String? units) {
    if (cm == null) return '—';
    if (!isImperial(units)) return '${cm.round()} cm';
    final inches = cm / 2.54;
    return "${inches ~/ 12}' ${(inches % 12).round()}\"";
  }

  static String volume(double kg, String? units) {
    final v = fromKg(kg, units);
    return '${NumberFormat.decimalPattern().format(v.round())} ${weightLabel(units)}';
  }

  static String duration(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  static String durationWords(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60;
    if (h > 0) return m > 0 ? '${h}h ${m}min' : '${h}h';
    return '${d.inMinutes} min';
  }
}

class Dates {
  const Dates._();
  static String iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  static DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime parseDay(String s) => DateTime.parse(s);
  static String friendly(DateTime d) {
    final today = dayOnly(DateTime.now());
    final day = dayOnly(d.toLocal());
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff > 1 && diff < 7) return DateFormat('EEEE').format(day);
    return DateFormat('EEE, d MMM').format(day);
  }

  static String weekdayName(int isoWeekday, {bool short = false}) =>
      (short ? const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'] : const [
        'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
      ])[isoWeekday - 1];

  /// ISO week key matching the backend: e.g. 2026-W43.
  static String weekKey(DateTime d) {
    final day = DateTime.utc(d.year, d.month, d.day); // UTC avoids DST-length days
    final thursday = day.add(Duration(days: 4 - day.weekday));
    final firstThursday = DateTime.utc(thursday.year, 1, 4);
    final week1Monday = firstThursday.subtract(Duration(days: firstThursday.weekday - 1));
    final week = thursday.difference(week1Monday).inDays ~/ 7 + 1;
    return '${thursday.year}-W${week.toString().padLeft(2, '0')}';
  }

  static String hhmm(int hour, int minute) =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  static String timeLabel(String? hhmm) {
    if (hhmm == null || !hhmm.contains(':')) return '—';
    final p = hhmm.split(':');
    return DateFormat.jm().format(DateTime(2000, 1, 1, int.parse(p[0]), int.parse(p[1])));
  }
}
