enum TaskStatus { inbox, available, scheduled, waiting, completed }

enum RecurrenceType { calendar, afterCompletion }

enum RecurrenceUnit {
  day,
  weekday,
  week,
  month,
  monthEnd,
  monthWeekday,
  monthLastWeekday,
  year,
}

class RecurrenceRule {
  const RecurrenceRule({
    required this.type,
    required this.unit,
    this.interval = 1,
  }) : assert(interval > 0);

  final RecurrenceType type;
  final RecurrenceUnit unit;
  final int interval;

  String encode() => '${type.name}:${unit.name}:$interval';

  static RecurrenceRule? decode(String? value) {
    if (value == null) return null;
    final parts = value.split(':');
    if (parts.length != 3) return null;
    final interval = int.tryParse(parts[2]);
    if (interval == null || interval < 1) return null;
    return RecurrenceRule(
      type: RecurrenceType.values.byName(parts[0]),
      unit: RecurrenceUnit.values.byName(parts[1]),
      interval: interval,
    );
  }
}

String recurrenceSmartLabel(String? encoded, String? showDate) {
  final rule = RecurrenceRule.decode(encoded);
  if (rule == null) return 'ricorrenza';
  CivilDate? anchor;
  if (showDate != null && showDate.isNotEmpty) {
    try {
      anchor = CivilDate.parse(showDate);
    } on FormatException {
      anchor = null;
    }
  }
  final interval = rule.interval;
  final unit = switch (rule.unit) {
    RecurrenceUnit.day => interval == 1 ? 'giorno' : '$interval giorni',
    RecurrenceUnit.weekday => 'giorno feriale',
    RecurrenceUnit.week =>
      interval == 1
          ? anchor == null
                ? 'settimana'
                : _weekdayName(anchor.asLocalDate.weekday)
          : '$interval settimane${anchor == null ? '' : ' · ${_weekdayName(anchor.asLocalDate.weekday)}'}',
    RecurrenceUnit.month =>
      interval == 1
          ? anchor == null
                ? 'mese'
                : '${anchor.day} del mese'
          : '$interval mesi${anchor == null ? '' : ' · giorno ${anchor.day}'}',
    RecurrenceUnit.monthEnd => 'ultimo giorno del mese',
    RecurrenceUnit.monthWeekday =>
      anchor == null
          ? 'mese'
          : '${_ordinalName(((anchor.day - 1) ~/ 7) + 1)} ${_weekdayName(anchor.asLocalDate.weekday)} del mese',
    RecurrenceUnit.monthLastWeekday =>
      anchor == null
          ? 'ultimo giorno feriale del mese'
          : 'ultimo ${_weekdayName(anchor.asLocalDate.weekday)} del mese',
    RecurrenceUnit.year =>
      anchor == null ? 'anno' : '${anchor.day} ${_monthName(anchor.month)}',
  };
  return rule.type == RecurrenceType.afterCompletion
      ? 'ogni $unit dopo il completamento'
      : 'ogni $unit';
}

String _weekdayName(int weekday) => const [
  'lunedì',
  'martedì',
  'mercoledì',
  'giovedì',
  'venerdì',
  'sabato',
  'domenica',
][weekday - 1];

String _monthName(int month) => const [
  'gennaio',
  'febbraio',
  'marzo',
  'aprile',
  'maggio',
  'giugno',
  'luglio',
  'agosto',
  'settembre',
  'ottobre',
  'novembre',
  'dicembre',
][month - 1];

String _ordinalName(int ordinal) => const [
  'primo',
  'secondo',
  'terzo',
  'quarto',
  'quinto',
][ordinal.clamp(1, 5) - 1];

class CivilDate implements Comparable<CivilDate> {
  const CivilDate(this.year, this.month, this.day);

  factory CivilDate.fromDateTime(DateTime value) =>
      CivilDate(value.year, value.month, value.day);

  factory CivilDate.parse(String value) {
    final parts = value.split('-');
    if (parts.length != 3) throw const FormatException('Data non valida');
    return CivilDate(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  final int year;
  final int month;
  final int day;

  DateTime get asLocalDate => DateTime(year, month, day);

  CivilDate addDays(int days) =>
      CivilDate.fromDateTime(DateTime(year, month, day + days));

  CivilDate addMonths(int months, {int? anchorDay}) {
    final index = year * 12 + month - 1 + months;
    final targetYear = index ~/ 12;
    final targetMonth = index % 12 + 1;
    final lastDay = DateTime(targetYear, targetMonth + 1, 0).day;
    final desired = anchorDay ?? day;
    return CivilDate(targetYear, targetMonth, desired.clamp(1, lastDay));
  }

  @override
  int compareTo(CivilDate other) => toString().compareTo(other.toString());

  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is CivilDate && toString() == other.toString();

  @override
  int get hashCode => Object.hash(year, month, day);
}

CivilDate nextOccurrence(
  CivilDate anchor,
  CivilDate current,
  RecurrenceRule rule,
) {
  return switch (rule.unit) {
    RecurrenceUnit.day => current.addDays(rule.interval),
    RecurrenceUnit.weekday => _nextWeekday(current, rule.interval),
    RecurrenceUnit.week => current.addDays(7 * rule.interval),
    RecurrenceUnit.month => current.addMonths(
      rule.interval,
      anchorDay: anchor.day,
    ),
    RecurrenceUnit.monthWeekday => _nextMonthlyWeekday(
      anchor,
      current,
      rule.interval,
    ),
    RecurrenceUnit.monthEnd => _nextMonthEnd(current, rule.interval),
    RecurrenceUnit.monthLastWeekday => _nextMonthlyLastWeekday(
      anchor,
      current,
      rule.interval,
    ),
    RecurrenceUnit.year => current.addMonths(
      12 * rule.interval,
      anchorDay: anchor.day,
    ),
  };
}

CivilDate _nextWeekday(CivilDate current, int interval) {
  var result = current;
  var remaining = interval;
  while (remaining > 0) {
    result = result.addDays(1);
    if (result.asLocalDate.weekday <= DateTime.friday) remaining--;
  }
  return result;
}

CivilDate _nextMonthEnd(CivilDate current, int interval) {
  final month = CivilDate(current.year, current.month, 1).addMonths(interval);
  return CivilDate(
    month.year,
    month.month,
    DateTime(month.year, month.month + 1, 0).day,
  );
}

CivilDate _nextMonthlyLastWeekday(
  CivilDate anchor,
  CivilDate current,
  int interval,
) {
  final month = CivilDate(current.year, current.month, 1).addMonths(interval);
  final weekday = anchor.asLocalDate.weekday;
  var date = DateTime(month.year, month.month + 1, 0);
  while (date.weekday != weekday) {
    date = date.subtract(const Duration(days: 1));
  }
  return CivilDate.fromDateTime(date);
}

CivilDate _nextMonthlyWeekday(
  CivilDate anchor,
  CivilDate current,
  int interval,
) {
  final target = current.addMonths(interval);
  final ordinal = ((anchor.day - 1) ~/ 7) + 1;
  final weekday = anchor.asLocalDate.weekday;
  final first = DateTime(target.year, target.month);
  var day = 1 + (weekday - first.weekday) % 7 + (ordinal - 1) * 7;
  final lastDay = DateTime(target.year, target.month + 1, 0).day;
  if (day > lastDay) day -= 7;
  return CivilDate(target.year, target.month, day);
}

class LogicalVersion implements Comparable<LogicalVersion> {
  const LogicalVersion(this.counter, this.deviceId);

  final int counter;
  final String deviceId;

  @override
  int compareTo(LogicalVersion other) {
    final byCounter = counter.compareTo(other.counter);
    return byCounter != 0 ? byCounter : deviceId.compareTo(other.deviceId);
  }
}
