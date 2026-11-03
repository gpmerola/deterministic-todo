import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../domain/private_earnings.dart';
import '../services/private_earnings_service.dart';

class PrivateEarningsSheet extends StatefulWidget {
  const PrivateEarningsSheet({
    required this.service,
    DateTime Function()? now,
    super.key,
  }) : now = now ?? DateTime.now;
  final PrivateEarningsService service;
  final DateTime Function() now;

  /// Past months offered besides the current one (build 318).
  static const pastMonths = 3;
  @override
  State<PrivateEarningsSheet> createState() => _PrivateEarningsSheetState();
}

class _PrivateEarningsSheetState extends State<PrivateEarningsSheet> {
  /// 0 is the current month, 1 the previous one and so on (build 318).
  int _monthsBack = 0;

  DateTime _month(int back) {
    final now = widget.now();
    return DateTime(now.year, now.month - back);
  }

  late Future<PrivateEarnings> _result = _load();
  Future<PrivateEarnings> _load() {
    // A past month is estimated as at its last moment: everything is over.
    final asOf = _monthsBack == 0
        ? widget.now()
        : DateTime(
            _month(_monthsBack).year,
            _month(_monthsBack).month + 1,
          ).subtract(const Duration(milliseconds: 1));
    final result = widget.service
        .load(now: asOf)
        .timeout(const Duration(seconds: 15));
    // A retry may fail before the next frame attaches FutureBuilder. Handle
    // that interval too; FutureBuilder still receives the original error.
    result.ignore();
    return result;
  }

  String money(int pence) =>
      NumberFormat.currency(locale: 'en_GB', symbol: '£').format(pence / 100);

  /// Which events got no price (build 319): date, time and title.
  Widget unpricedList(PrivateEarnings result) => ExpansionTile(
    key: const ValueKey('earnings-unpriced'),
    tilePadding: EdgeInsets.zero,
    title: const Text('Non valorizzati'),
    subtitle: Text(
      '${result.unpricedEntries.length} eventi senza prezzo: tipo non '
      'riconosciuto, ASD o durata diversa dal tariffario',
    ),
    children: [
      for (final entry in result.unpricedEntries)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${DateFormat('d MMM HH:mm', 'it').format(entry.start)} · '
              '${entry.title.trim().isEmpty ? '(senza titolo)' : entry.title}',
            ),
          ),
        ),
    ],
  );

  Widget breakdown(
    String label,
    Map<PrivateFee, int> counts,
    int unpriced,
  ) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    title: Text(label),
    subtitle: Text(
      '${counts.values.fold(0, (sum, n) => sum + n)} prestazioni · $unpriced eventi non valorizzati',
    ),
    children: [
      for (final fee in PrivateFee.values)
        if (counts.containsKey(fee))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${counts[fee]} × ${fee.label} · ${money(fee.pence * counts[fee]!)}',
              ),
            ),
          ),
    ],
  );

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
    child: FutureBuilder<PrivateEarnings>(
      future: _result,
      builder: (context, snapshot) {
        final result = snapshot.data;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  'Lavoro privato · ',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                DropdownButton<int>(
                  key: const ValueKey('earnings-month'),
                  value: _monthsBack,
                  underline: const SizedBox.shrink(),
                  style: Theme.of(context).textTheme.titleLarge,
                  items: [
                    for (
                      var back = 0;
                      back <= PrivateEarningsSheet.pastMonths;
                      back++
                    )
                      DropdownMenuItem(
                        value: back,
                        child: Text(
                          DateFormat(
                            back == 0 ? 'MMMM' : 'MMMM y',
                            'it',
                          ).format(_month(back)),
                        ),
                      ),
                  ],
                  onChanged: snapshot.connectionState == ConnectionState.done
                      ? (back) => setState(() {
                          _monthsBack = back ?? 0;
                          _result = _load();
                        })
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (snapshot.connectionState != ConnectionState.done)
              const Center(child: CircularProgressIndicator())
            else if (snapshot.hasError)
              Text(
                snapshot.error is PrivateEarningsUnavailable
                    ? (snapshot.error! as PrivateEarningsUnavailable).message
                    : 'Stima non disponibile. Riprova tra poco.',
              )
            else if (result != null) ...[
              Text(_monthsBack == 0 ? 'Maturato finora' : 'Maturato nel mese'),
              Text(
                money(result.pence),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const Text('Solo appuntamenti già terminati'),
              if (_monthsBack == 0) ...[
                const SizedBox(height: 16),
                const Text('Totale previsto del mese'),
                Text(
                  money(result.monthPence),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                Text(
                  'Finora + ${money(result.scheduledPence)} da appuntamenti già programmati, inclusi quelli in corso',
                ),
              ],
              const SizedBox(height: 12),
              const Text('Importi lordi stimati · non incassi confermati'),
              breakdown('Dettaglio finora', result.counts, result.unpriced),
              if (_monthsBack == 0)
                breakdown(
                  'Ancora programmati',
                  result.scheduledCounts,
                  result.scheduledUnpriced,
                ),
              if (result.unpricedEntries.isNotEmpty) unpricedList(result),
              if (result.dnaVisits > 0 || result.sembleCancelled > 0)
                Padding(
                  key: const ValueKey('earnings-semble-dna'),
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    [
                      if (result.dnaVisits > 0)
                        'DNA da Semble: ${result.dnaVisits}'
                            '${result.dnaPence > 0 ? ', ${money(result.dnaPence)} non maturati' : ''}',
                      if (result.sembleCancelled > 0)
                        'Cancellate in Semble: ${result.sembleCancelled}',
                    ].join(' · '),
                  ),
                ),
              if (result.sembleVisits case final visits?)
                Text(
                  'Visite Semble lette direttamente da Semble: $visits '
                  '(tipo, orario ed esito dalle prenotazioni).',
                  key: const ValueKey('earnings-semble-visits'),
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else if (result.sembleMatched case final semble?)
                Text(
                  'Esiti Semble trovati per ${semble.matched} di '
                  '${semble.checked} visite del calendario Semble.',
                  key: const ValueKey('earnings-semble-matched'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (result.sembleProblem case final problem?)
                Text(
                  problem,
                  key: const ValueKey('earnings-semble-problem'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const SizedBox(height: 12),
              Text(
                'Solo il mese scelto (il corrente o uno dei 3 precedenti), secondo la data di inizio degli appuntamenti. Calcolato al ${DateFormat('d MMMM, HH:mm', 'it').format(result.asOf)}. Calendari OPUK / Semble / heydoc, anche se nascosti in agenda. Annullati e assenze esclusi; con chiave e cognome Semble le visite Semble vengono dalle prenotazioni, con DNA e cancellazioni. Il previsto assume che gli appuntamenti programmati si svolgano.',
              ),
              const SizedBox(height: 8),
              const Text(
                'Tariffario settembre 2026. ADHD: valutazione e feedback separati; report incluso; minori come adulti, da confermare con OPUK. ASD e tipi non riconosciuti esclusi. Prestazioni fuori calendario non comprese. Copie con titoli diversi possono essere contate due volte.',
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: snapshot.connectionState == ConnectionState.done
                    ? () => setState(() {
                        _result = _load();
                      })
                    : null,
                child: const Text('Aggiorna'),
              ),
            ),
          ],
        );
      },
    ),
  );
}
