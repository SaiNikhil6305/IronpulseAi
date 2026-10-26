// Pure aggregation of imported health samples into one row per day. No plugin code here - easy to test.

enum Sample { steps, heartRate, restingHeartRate, sleep }

class RawSample {
  final Sample kind;
  final DateTime from, to;
  final double value; // steps count, bpm, or ignored for sleep (duration comes from from/to)
  const RawSample(this.kind, this.from, this.to, this.value);
}

class DailyHealth {
  final String day; // yyyy-mm-dd
  int? steps;
  double? hrAvg, hrMin, hrMax, restingHr;
  int? sleepMinutes;
  DailyHealth(this.day);

  Map<String, Object?> toMap() => {
        'day': day,
        'steps': steps,
        'hr_avg': hrAvg,
        'hr_min': hrMin,
        'hr_max': hrMax,
        'resting_hr': restingHr,
        'sleep_minutes': sleepMinutes,
      };

  factory DailyHealth.fromMap(Map<String, Object?> m) => DailyHealth(m['day'] as String)
    ..steps = m['steps'] as int?
    ..hrAvg = (m['hr_avg'] as num?)?.toDouble()
    ..hrMin = (m['hr_min'] as num?)?.toDouble()
    ..hrMax = (m['hr_max'] as num?)?.toDouble()
    ..restingHr = (m['resting_hr'] as num?)?.toDouble()
    ..sleepMinutes = m['sleep_minutes'] as int?;

  bool get isEmpty => steps == null && hrAvg == null && restingHr == null && sleepMinutes == null;
}

String healthDayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// [stepsByDay] comes from the platform's de-duplicated daily total (phone + watch counted once),
/// so step samples are not summed here. Sleep is credited to the day the session ends (the morning).
/// Overlapping sleep sessions (e.g. from two apps) are merged so time is never double counted.
Map<String, DailyHealth> summarize(List<RawSample> samples, Map<String, int> stepsByDay) {
  final out = <String, DailyHealth>{};
  DailyHealth day(String k) => out.putIfAbsent(k, () => DailyHealth(k));

  stepsByDay.forEach((k, v) => day(k).steps = v);

  final hr = <String, List<double>>{};
  final resting = <String, List<double>>{};
  final sleep = <String, List<(DateTime, DateTime)>>{};
  for (final s in samples) {
    switch (s.kind) {
      case Sample.heartRate:
        if (s.value > 20 && s.value < 250) hr.putIfAbsent(healthDayKey(s.from), () => []).add(s.value);
      case Sample.restingHeartRate:
        if (s.value > 20 && s.value < 200) resting.putIfAbsent(healthDayKey(s.from), () => []).add(s.value);
      case Sample.sleep:
        if (s.to.isAfter(s.from)) sleep.putIfAbsent(healthDayKey(s.to), () => []).add((s.from, s.to));
      case Sample.steps:
        break;
    }
  }
  hr.forEach((k, v) {
    final d = day(k);
    d.hrAvg = v.reduce((a, b) => a + b) / v.length;
    d.hrMin = v.reduce((a, b) => a < b ? a : b);
    d.hrMax = v.reduce((a, b) => a > b ? a : b);
  });
  resting.forEach((k, v) => day(k).restingHr = v.reduce((a, b) => a + b) / v.length);
  sleep.forEach((k, v) {
    v.sort((a, b) => a.$1.compareTo(b.$1));
    var total = Duration.zero;
    DateTime? curStart, curEnd;
    for (final (s, e) in v) {
      if (curEnd == null || s.isAfter(curEnd)) {
        if (curStart != null) total += curEnd!.difference(curStart);
        curStart = s;
        curEnd = e;
      } else if (e.isAfter(curEnd)) {
        curEnd = e;
      }
    }
    if (curStart != null) total += curEnd!.difference(curStart);
    day(k).sleepMinutes = total.inMinutes;
  });
  return out;
}

String fmtSleep(int? minutes) => minutes == null ? '-' : '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';
