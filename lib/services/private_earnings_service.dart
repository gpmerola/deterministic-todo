import 'dart:async';

import '../domain/agenda.dart';
import '../domain/private_earnings.dart';
import '../domain/semble_bookings.dart';
import '../domain/task.dart';
import 'agenda_service.dart';
import 'semble_service.dart';

class PrivateEarningsUnavailable implements Exception {
  const PrivateEarningsUnavailable(this.message);
  final String message;
}

/// On-demand, phone-local calculation. No amounts, titles or patient details
/// are persisted, sent over the network or included in logs.
class PrivateEarningsService {
  PrivateEarningsService(this.agenda, {this.semble, SembleClient? client})
    : sembleClient = client ?? SembleClient();
  final AgendaService agenda;

  /// When set and configured with a key and the user's name in Semble, the
  /// month's bookings give each Semble visit its recorded outcome (build
  /// 288): "did not attend" and deleted bookings leave the totals.
  final SembleSettings? semble;
  final SembleClient sembleClient;

  static const sembleTimeout = Duration(seconds: 12);

  Future<PrivateEarnings> load({DateTime? now}) async {
    if (agenda.writesViaPhone) {
      throw const PrivateEarningsUnavailable(
        'Consulta la stima su Android: la copia Web può non coprire tutto il mese.',
      );
    }
    if (await agenda.access() != AgendaAccess.granted) {
      throw const PrivateEarningsUnavailable(
        'Consenti l’accesso al Calendario per calcolare la stima.',
      );
    }
    final asOf = now ?? DateTime.now();
    final calendars = (await agenda.calendars())
        .where(isPrivateWorkCalendar)
        .toList();
    if (calendars.isEmpty) {
      throw const PrivateEarningsUnavailable(
        'Nessun calendario OPUK, Semble o heydoc trovato sul telefono.',
      );
    }
    final events = await agenda.events(
      DateTime(asOf.year, asOf.month),
      DateTime(asOf.year, asOf.month + 1),
      calendars.map((c) => c.id).toList(),
    );
    // Display visibility is not evidence that a service was not performed.
    // Exact duplicates use the same merging rule as the calendar itself.
    final entries = mergeAgendaEntries(
      events: events,
      calendars: calendars,
      hiddenCalendarIds: const {},
    );
    final sembleCalendars = {
      for (final calendar in calendars)
        if (isSembleCalendar(calendar)) calendar.id,
    };
    final (bookings, problem) = await _sembleBookings(asOf);
    final result = estimatePrivateEarnings(
      entries,
      asOf,
      outcome: bookings == null
          ? null
          : (entry) => sembleOutcomeFor(entry, bookings),
      sembleEntry: (entry) => entry.calendarIds.any(sembleCalendars.contains),
    );
    return problem == null ? result : result.withSembleProblem(problem);
  }

  /// The user's bookings of the month, or why they are missing. Nothing is
  /// stored: they live only for this calculation.
  Future<(List<SembleBooking>?, String?)> _sembleBookings(DateTime asOf) async {
    final settings = semble;
    if (settings == null) return (null, null);
    final config = await settings.read();
    if (config.maskedKey == null) return (null, null);
    final name = config.doctorName;
    if (name == null) {
      return (
        null,
        'Per DNA e cancellazioni da Semble scrivi il tuo cognome in '
            'Impostazioni → Semble.',
      );
    }
    final key = await settings.apiKey();
    if (key == null) return (null, null);
    try {
      final bookings = await sembleClient
          .bookings(
            key: key,
            first: CivilDate(asOf.year, asOf.month, 1),
            last: CivilDate.fromDateTime(
              DateTime(asOf.year, asOf.month + 1, 0),
            ),
            doctorName: name,
          )
          .timeout(sembleTimeout);
      return (bookings, null);
    } on SembleException catch (error) {
      return (null, 'Esiti Semble non letti: ${error.message}');
    } on TimeoutException {
      return (null, 'Esiti Semble non letti: Semble non ha risposto in tempo.');
    }
  }
}
