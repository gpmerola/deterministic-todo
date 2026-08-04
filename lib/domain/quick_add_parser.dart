import 'task.dart';

class QuickTaskDraft {
  const QuickTaskDraft({required this.title, this.showDate, this.timeMinutes});

  final String title;
  final CivilDate? showDate;
  final int? timeMinutes;

  bool get isScheduled => showDate != null;
}

class QuickAddParser {
  const QuickAddParser();

  static final RegExp _recognizedSyntax = RegExp(
    r'\b(?:dopodomani|domani|oggi|(?:alle|ore)\s+(?:[01]?\d|2[0-3])(?:[\.:][0-5]\d)?|(?:prossimo\s+)?(?:lunedi|lunedì|martedi|martedì|mercoledi|mercoledì|giovedi|giovedì|venerdi|venerdì|sabato|domenica)|(?:il\s+)?[0-3]?\d[\/-][01]?\d(?:[\/-](?:\d{2}|\d{4}))?|(?:il\s+)?[0-3]?\d\s+(?:gennaio|febbraio|marzo|aprile|maggio|giugno|luglio|agosto|settembre|ottobre|novembre|dicembre)(?:\s+\d{4})?)\b',
    caseSensitive: false,
  );

  Iterable<RegExpMatch> recognizedSyntax(String input) =>
      _recognizedSyntax.allMatches(input);

  QuickTaskDraft parse(String input, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    var title = input.trim();
    CivilDate? date;
    int? minutes;

    final timeMatch = RegExp(
      r'\b(?:alle|ore)\s+([01]?\d|2[0-3])(?:[\.:]([0-5]\d))?\b',
      caseSensitive: false,
    ).firstMatch(title);
    if (timeMatch != null) {
      minutes =
          int.parse(timeMatch.group(1)!) * 60 +
          int.parse(timeMatch.group(2) ?? '0');
      title = _removeMatch(title, timeMatch);
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
      const names = <String>[
        'lunedi',
        'martedi',
        'mercoledi',
        'giovedi',
        'venerdi',
        'sabato',
        'domenica',
      ];
      final weekday = RegExp(
        r'\b(?:prossimo\s+)?(lunedi|lunedì|martedi|martedì|mercoledi|mercoledì|giovedi|giovedì|venerdi|venerdì|sabato|domenica)(?=\s|$)',
        caseSensitive: false,
      ).firstMatch(title);
      if (weekday != null) {
        final normalized = weekday.group(1)!.toLowerCase().replaceAll('ì', 'i');
        final target = names.indexOf(normalized) + 1;
        var delta = (target - reference.weekday) % 7;
        if (delta == 0 ||
            weekday.group(0)!.toLowerCase().startsWith('prossimo')) {
          delta += 7;
        }
        date = CivilDate.fromDateTime(reference).addDays(delta);
        title = _removeMatch(title, weekday);
      }
    }

    if (date == null && minutes != null) {
      date = CivilDate.fromDateTime(reference);
    }

    title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (title.isEmpty) {
      throw const FormatException('Il titolo è obbligatorio');
    }
    return QuickTaskDraft(title: title, showDate: date, timeMinutes: minutes);
  }

  CivilDate _validatedDate(int year, int month, int day) {
    final value = DateTime(year, month, day);
    if (value.year != year || value.month != month || value.day != day) {
      throw const FormatException('Data non valida');
    }
    return CivilDate(year, month, day);
  }

  String _removeMatch(String source, RegExpMatch match) =>
      source.replaceRange(match.start, match.end, ' ');
}
