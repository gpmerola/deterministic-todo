import 'task.dart';

class QuickTaskDraft {
  const QuickTaskDraft({required this.title, this.showDate, this.recurrence});

  final String title;
  final CivilDate? showDate;
  final String? recurrence;

  bool get isScheduled => showDate != null;
}

class QuickAddParser {
  const QuickAddParser();

  static final RegExp _recognizedSyntax = RegExp(
    r'\b(?:ogni\s+(?:(?:\d+\s+)?(?:giorno|giorni|settimana|settimane|mese|mesi|anno|anni)(?:\s+dopo\s+il\s+completamento)?|giorno\s+feriale|weekend|ultimo\s+giorno\s+del\s+mese|ultimo\s+(?:lunedi|lunedì|martedi|martedì|mercoledi|mercoledì|giovedi|giovedì|venerdi|venerdì|sabato|domenica)(?:\s+del\s+mese)?|[0-3]?\d\s+del\s+mese|(?:primo|secondo|terzo|quarto|quinto)\s+(?:lunedi|lunedì|martedi|martedì|mercoledi|mercoledì|giovedi|giovedì|venerdi|venerdì|sabato|domenica)(?:\s+del\s+mese)?|(?:lunedi|lunedì|martedi|martedì|mercoledi|mercoledì|giovedi|giovedì|venerdi|venerdì|sabato|domenica)|[0-3]?\d\s+(?:gennaio|febbraio|marzo|aprile|maggio|giugno|luglio|agosto|settembre|ottobre|novembre|dicembre))|stasera|questo\s+weekend|inizio\s+settimana\s+prossima|fine\s+mese|(?:tra|fra)\s+\d+\s+(?:giorni?|settimane?)|dopodomani|domani|oggi|(?:prossimo\s+)?(?:lunedi|lunedì|martedi|martedì|mercoledi|mercoledì|giovedi|giovedì|venerdi|venerdì|sabato|domenica)|(?:il\s+)?[0-3]?\d[\/-][01]?\d(?:[\/-](?:\d{2}|\d{4}))?|(?:il\s+)?[0-3]?\d\s+(?:gennaio|febbraio|marzo|aprile|maggio|giugno|luglio|agosto|settembre|ottobre|novembre|dicembre)(?:\s+\d{4})?)(?=\s|$)',
    caseSensitive: false,
  );

  Iterable<RegExpMatch> recognizedSyntax(String input) =>
      _recognizedSyntax.allMatches(input);

  QuickTaskDraft parse(String input, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    var title = input.trim();
    CivilDate? date;
    String? recurrence;

    const weekdayNames = <String>[
      'lunedi',
      'martedi',
      'mercoledi',
      'giovedi',
      'venerdi',
      'sabato',
      'domenica',
    ];
    const monthNumbers = <String, int>{
      'gennaio': 1,
      'febbraio': 2,
      'marzo': 3,
      'aprile': 4,
      'maggio': 5,
      'giugno': 6,
      'luglio': 7,
      'agosto': 8,
      'settembre': 9,
      'ottobre': 10,
      'novembre': 11,
      'dicembre': 12,
    };

    final afterCompletion = RegExp(
      r'\bogni\s+(?:(\d+)\s+)?(giorno|giorni|settimana|settimane|mese|mesi|anno|anni)\s+dopo\s+il\s+completamento(?=\s|$)',
      caseSensitive: false,
    ).firstMatch(title);
    if (afterCompletion != null) {
      final interval = int.parse(afterCompletion.group(1) ?? '1');
      final word = afterCompletion.group(2)!.toLowerCase();
      final unit = word.startsWith('giorn')
          ? RecurrenceUnit.day
          : word.startsWith('settiman')
          ? RecurrenceUnit.week
          : word.startsWith('mes')
          ? RecurrenceUnit.month
          : RecurrenceUnit.year;
      recurrence = RecurrenceRule(
        type: RecurrenceType.afterCompletion,
        unit: unit,
        interval: interval,
      ).encode();
      date = CivilDate.fromDateTime(reference);
      title = _removeMatch(title, afterCompletion);
    }

    final everyWeekday = RegExp(
      r'\bogni\s+giorno\s+feriale(?=\s|$)',
      caseSensitive: false,
    ).firstMatch(title);
    if (everyWeekday != null) {
      var candidate = CivilDate.fromDateTime(reference);
      while (candidate.asLocalDate.weekday > DateTime.friday) {
        candidate = candidate.addDays(1);
      }
      date = candidate;
      recurrence = const RecurrenceRule(
        type: RecurrenceType.calendar,
        unit: RecurrenceUnit.weekday,
      ).encode();
      title = _removeMatch(title, everyWeekday);
    }

    final everyWeekend = RegExp(
      r'\bogni\s+weekend(?=\s|$)',
      caseSensitive: false,
    ).firstMatch(title);
    if (everyWeekend != null) {
      final delta = (DateTime.saturday - reference.weekday) % 7;
      date = CivilDate.fromDateTime(reference).addDays(delta);
      recurrence = const RecurrenceRule(
        type: RecurrenceType.calendar,
        unit: RecurrenceUnit.week,
      ).encode();
      title = _removeMatch(title, everyWeekend);
    }

    final everyMonthEnd = RegExp(
      r'\bogni\s+ultimo\s+giorno\s+del\s+mese(?=\s|$)',
      caseSensitive: false,
    ).firstMatch(title);
    if (everyMonthEnd != null) {
      date = CivilDate(
        reference.year,
        reference.month,
        DateTime(reference.year, reference.month + 1, 0).day,
      );
      recurrence = const RecurrenceRule(
        type: RecurrenceType.calendar,
        unit: RecurrenceUnit.monthEnd,
      ).encode();
      title = _removeMatch(title, everyMonthEnd);
    }

    final everyLastWeekday = RegExp(
      r'\bogni\s+ultimo\s+(lunedi|lunedì|martedi|martedì|mercoledi|mercoledì|giovedi|giovedì|venerdi|venerdì|sabato|domenica)(?:\s+del\s+mese)?(?=\s|$)',
      caseSensitive: false,
    ).firstMatch(title);
    if (everyLastWeekday != null) {
      final normalized = everyLastWeekday
          .group(1)!
          .toLowerCase()
          .replaceAll('ì', 'i');
      final weekday = weekdayNames.indexOf(normalized) + 1;
      var candidate = _lastWeekday(reference.year, reference.month, weekday);
      if (candidate.asLocalDate.isBefore(
        DateTime(reference.year, reference.month, reference.day),
      )) {
        final next = CivilDate(reference.year, reference.month, 1).addMonths(1);
        candidate = _lastWeekday(next.year, next.month, weekday);
      }
      date = candidate;
      recurrence = const RecurrenceRule(
        type: RecurrenceType.calendar,
        unit: RecurrenceUnit.monthLastWeekday,
      ).encode();
      title = _removeMatch(title, everyLastWeekday);
    }

    final relativeDistance = RegExp(
      r'\b(?:tra|fra)\s+(\d+)\s+(giorno|giorni|settimana|settimane)(?=\s|$)',
      caseSensitive: false,
    ).firstMatch(title);
    if (relativeDistance != null) {
      final amount = int.parse(relativeDistance.group(1)!);
      final multiplier =
          relativeDistance.group(2)!.toLowerCase().startsWith('settiman')
          ? 7
          : 1;
      date = CivilDate.fromDateTime(reference).addDays(amount * multiplier);
      title = _removeMatch(title, relativeDistance);
    }

    final tonight = RegExp(
      r'\bstasera\b',
      caseSensitive: false,
    ).firstMatch(title);
    if (tonight != null) {
      date = CivilDate.fromDateTime(reference);
      title = _removeMatch(title, tonight);
    }

    final thisWeekend = RegExp(
      r'\bquesto\s+weekend(?=\s|$)',
      caseSensitive: false,
    ).firstMatch(title);
    if (thisWeekend != null) {
      final delta = (DateTime.saturday - reference.weekday) % 7;
      date = CivilDate.fromDateTime(reference).addDays(delta);
      title = _removeMatch(title, thisWeekend);
    }

    final nextWeekStart = RegExp(
      r'\binizio\s+settimana\s+prossima(?=\s|$)',
      caseSensitive: false,
    ).firstMatch(title);
    if (nextWeekStart != null) {
      date = CivilDate.fromDateTime(reference).addDays(8 - reference.weekday);
      title = _removeMatch(title, nextWeekStart);
    }

    final monthEnd = RegExp(
      r'\bfine\s+mese(?=\s|$)',
      caseSensitive: false,
    ).firstMatch(title);
    if (monthEnd != null) {
      date = CivilDate(
        reference.year,
        reference.month,
        DateTime(reference.year, reference.month + 1, 0).day,
      );
      title = _removeMatch(title, monthEnd);
    }

    final recurringAnnualDate = RegExp(
      r'\bogni\s+([0-3]?\d)\s+(gennaio|febbraio|marzo|aprile|maggio|giugno|luglio|agosto|settembre|ottobre|novembre|dicembre)(?=\s|$)',
      caseSensitive: false,
    ).firstMatch(title);
    if (recurringAnnualDate != null) {
      final day = int.parse(recurringAnnualDate.group(1)!);
      final month = monthNumbers[recurringAnnualDate.group(2)!.toLowerCase()]!;
      var candidate = _validatedDate(reference.year, month, day);
      if (candidate.asLocalDate.isBefore(
        DateTime(reference.year, reference.month, reference.day),
      )) {
        candidate = _validatedDate(reference.year + 1, month, day);
      }
      date = candidate;
      recurrence = const RecurrenceRule(
        type: RecurrenceType.calendar,
        unit: RecurrenceUnit.year,
      ).encode();
      title = _removeMatch(title, recurringAnnualDate);
    }

    final recurringMonthDay = RegExp(
      r'\bogni\s+([0-3]?\d)\s+del\s+mese(?=\s|$)',
      caseSensitive: false,
    ).firstMatch(title);
    if (recurringMonthDay != null) {
      final day = int.parse(recurringMonthDay.group(1)!);
      if (day < 1 || day > 31) {
        throw const FormatException('Giorno mensile non valido');
      }
      var monthOffset = 0;
      CivilDate? candidate;
      while (candidate == null) {
        final month = CivilDate(
          reference.year,
          reference.month,
          1,
        ).addMonths(monthOffset++);
        final lastDay = DateTime(month.year, month.month + 1, 0).day;
        if (day > lastDay) continue;
        final value = CivilDate(month.year, month.month, day);
        if (!value.asLocalDate.isBefore(
          DateTime(reference.year, reference.month, reference.day),
        )) {
          candidate = value;
        }
      }
      date = candidate;
      recurrence = const RecurrenceRule(
        type: RecurrenceType.calendar,
        unit: RecurrenceUnit.month,
      ).encode();
      title = _removeMatch(title, recurringMonthDay);
    }

    final recurringOrdinalWeekday = RegExp(
      r'\bogni\s+(primo|secondo|terzo|quarto|quinto)\s+(lunedi|lunedì|martedi|martedì|mercoledi|mercoledì|giovedi|giovedì|venerdi|venerdì|sabato|domenica)(?:\s+del\s+mese)?(?=\s|$)',
      caseSensitive: false,
    ).firstMatch(title);
    if (recurringOrdinalWeekday != null) {
      const ordinals = {
        'primo': 1,
        'secondo': 2,
        'terzo': 3,
        'quarto': 4,
        'quinto': 5,
      };
      final ordinal =
          ordinals[recurringOrdinalWeekday.group(1)!.toLowerCase()]!;
      final normalized = recurringOrdinalWeekday
          .group(2)!
          .toLowerCase()
          .replaceAll('ì', 'i');
      final weekday = weekdayNames.indexOf(normalized) + 1;
      var candidate = _nthWeekday(
        reference.year,
        reference.month,
        weekday,
        ordinal,
      );
      if (candidate.asLocalDate.isBefore(
        DateTime(reference.year, reference.month, reference.day),
      )) {
        final nextMonth = CivilDate(
          reference.year,
          reference.month,
          1,
        ).addMonths(1);
        candidate = _nthWeekday(
          nextMonth.year,
          nextMonth.month,
          weekday,
          ordinal,
        );
      }
      date = candidate;
      recurrence = const RecurrenceRule(
        type: RecurrenceType.calendar,
        unit: RecurrenceUnit.monthWeekday,
      ).encode();
      title = _removeMatch(title, recurringOrdinalWeekday);
    }

    final recurringWeekday = RegExp(
      r'\bogni\s+(lunedi|lunedì|martedi|martedì|mercoledi|mercoledì|giovedi|giovedì|venerdi|venerdì|sabato|domenica)(?=\s|$)',
      caseSensitive: false,
    ).firstMatch(title);
    if (recurringWeekday != null) {
      final normalized = recurringWeekday
          .group(1)!
          .toLowerCase()
          .replaceAll('ì', 'i');
      final target = weekdayNames.indexOf(normalized) + 1;
      final delta = (target - reference.weekday) % 7;
      date = CivilDate.fromDateTime(reference).addDays(delta);
      recurrence = const RecurrenceRule(
        type: RecurrenceType.calendar,
        unit: RecurrenceUnit.week,
      ).encode();
      title = _removeMatch(title, recurringWeekday);
    }

    final recurringUnit = RegExp(
      r'\bogni\s+(?:(\d+)\s+)?(giorno|giorni|settimana|settimane|mese|mesi|anno|anni)(?=\s|$)',
      caseSensitive: false,
    ).firstMatch(title);
    if (recurringUnit != null) {
      final interval = int.parse(recurringUnit.group(1) ?? '1');
      if (interval < 1) throw const FormatException('Ricorrenza non valida');
      final unitWord = recurringUnit.group(2)!.toLowerCase();
      final unit = unitWord.startsWith('giorn')
          ? RecurrenceUnit.day
          : unitWord.startsWith('settiman')
          ? RecurrenceUnit.week
          : unitWord.startsWith('mes')
          ? RecurrenceUnit.month
          : RecurrenceUnit.year;
      recurrence = RecurrenceRule(
        type: RecurrenceType.calendar,
        unit: unit,
        interval: interval,
      ).encode();
      date ??= CivilDate.fromDateTime(reference);
      title = _removeMatch(title, recurringUnit);
    }

    final relative = RegExp(
      r'\b(dopodomani|domani|oggi)\b',
      caseSensitive: false,
    ).firstMatch(title);
    if (relative != null) {
      final word = relative.group(1)!.toLowerCase();
      final offset = word == 'oggi' ? 0 : (word == 'domani' ? 1 : 2);
      date = CivilDate.fromDateTime(reference).addDays(offset);
      title = _removeMatch(title, relative);
    }

    if (date == null) {
      final numeric = RegExp(
        r'\b(?:il\s+)?([0-3]?\d)[\/-]([01]?\d)(?:[\/-](\d{2}|\d{4}))?\b',
        caseSensitive: false,
      ).firstMatch(title);
      if (numeric != null) {
        final day = int.parse(numeric.group(1)!);
        final month = int.parse(numeric.group(2)!);
        var year = numeric.group(3) == null
            ? reference.year
            : int.parse(numeric.group(3)!);
        if (year < 100) year += 2000;
        date = _validatedDate(year, month, day);
        if (numeric.group(3) == null &&
            date.asLocalDate.isBefore(
              DateTime(reference.year, reference.month, reference.day),
            )) {
          date = _validatedDate(year + 1, month, day);
        }
        title = _removeMatch(title, numeric);
      }
    }

    if (date == null) {
      const months = <String, int>{
        'gennaio': 1,
        'febbraio': 2,
        'marzo': 3,
        'aprile': 4,
        'maggio': 5,
        'giugno': 6,
        'luglio': 7,
        'agosto': 8,
        'settembre': 9,
        'ottobre': 10,
        'novembre': 11,
        'dicembre': 12,
      };
      final named = RegExp(
        r'\b(?:il\s+)?([0-3]?\d)\s+(gennaio|febbraio|marzo|aprile|maggio|giugno|luglio|agosto|settembre|ottobre|novembre|dicembre)(?:\s+(\d{4}))?(?=\s|$)',
        caseSensitive: false,
      ).firstMatch(title);
      if (named != null) {
        final day = int.parse(named.group(1)!);
        final month = months[named.group(2)!.toLowerCase()]!;
        var year = named.group(3) == null
            ? reference.year
            : int.parse(named.group(3)!);
        date = _validatedDate(year, month, day);
        if (named.group(3) == null &&
            date.asLocalDate.isBefore(
              DateTime(reference.year, reference.month, reference.day),
            )) {
          year++;
          date = _validatedDate(year, month, day);
        }
        title = _removeMatch(title, named);
      }
    }

    if (date == null) {
      final weekday = RegExp(
        r'\b(?:prossimo\s+)?(lunedi|lunedì|martedi|martedì|mercoledi|mercoledì|giovedi|giovedì|venerdi|venerdì|sabato|domenica)(?=\s|$)',
        caseSensitive: false,
      ).firstMatch(title);
      if (weekday != null) {
        final normalized = weekday.group(1)!.toLowerCase().replaceAll('ì', 'i');
        final target = weekdayNames.indexOf(normalized) + 1;
        var delta = (target - reference.weekday) % 7;
        if (delta == 0 ||
            weekday.group(0)!.toLowerCase().startsWith('prossimo')) {
          delta += 7;
        }
        date = CivilDate.fromDateTime(reference).addDays(delta);
        title = _removeMatch(title, weekday);
      }
    }

    title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (title.isEmpty) {
      throw const FormatException('Il titolo è obbligatorio');
    }
    return QuickTaskDraft(title: title, showDate: date, recurrence: recurrence);
  }

  CivilDate _validatedDate(int year, int month, int day) {
    final value = DateTime(year, month, day);
    if (value.year != year || value.month != month || value.day != day) {
      throw const FormatException('Data non valida');
    }
    return CivilDate(year, month, day);
  }

  CivilDate _nthWeekday(int year, int month, int weekday, int ordinal) {
    final first = DateTime(year, month);
    var day = 1 + (weekday - first.weekday) % 7 + (ordinal - 1) * 7;
    final lastDay = DateTime(year, month + 1, 0).day;
    if (day > lastDay) day -= 7;
    return CivilDate(year, month, day);
  }

  CivilDate _lastWeekday(int year, int month, int weekday) {
    var value = DateTime(year, month + 1, 0);
    while (value.weekday != weekday) {
      value = value.subtract(const Duration(days: 1));
    }
    return CivilDate.fromDateTime(value);
  }

  String _removeMatch(String source, RegExpMatch match) =>
      source.replaceRange(match.start, match.end, ' ');
}
