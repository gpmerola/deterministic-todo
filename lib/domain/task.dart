enum TaskStatus { inbox, available, scheduled, waiting, completed }

enum RecurrenceType { calendar, afterCompletion }

enum RecurrenceUnit { day, week, month }

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
    RecurrenceUnit.week => current.addDays(7 * rule.interval),
    RecurrenceUnit.month => current.addMonths(
      rule.interval,
      anchorDay: anchor.day,
    ),
  };
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
