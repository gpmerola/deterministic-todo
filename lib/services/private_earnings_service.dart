import '../domain/agenda.dart';
import '../domain/private_earnings.dart';
import 'agenda_service.dart';

class PrivateEarningsUnavailable implements Exception {
  const PrivateEarningsUnavailable(this.message);
  final String message;
}

/// On-demand, phone-local calculation. No amounts, titles or patient details
/// are persisted, sent over the network or included in logs.
class PrivateEarningsService {
  PrivateEarningsService(this.agenda);
  final AgendaService agenda;

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
    return estimatePrivateEarnings(
      mergeAgendaEntries(
        events: events,
        calendars: calendars,
        hiddenCalendarIds: const {},
      ),
      asOf,
    );
  }
}
