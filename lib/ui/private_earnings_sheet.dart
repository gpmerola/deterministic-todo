import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../domain/private_earnings.dart';
import '../services/private_earnings_service.dart';

class PrivateEarningsSheet extends StatefulWidget {
  const PrivateEarningsSheet({required this.service, super.key});
  final PrivateEarningsService service;
  @override
  State<PrivateEarningsSheet> createState() => _PrivateEarningsSheetState();
}

class _PrivateEarningsSheetState extends State<PrivateEarningsSheet> {
  late Future<PrivateEarnings> _result = _load();
  Future<PrivateEarnings> _load() {
    final result = widget.service.load().timeout(const Duration(seconds: 15));
    // A retry may fail before the next frame attaches FutureBuilder. Handle
    // that interval too; FutureBuilder still receives the original error.
    result.ignore();
    return result;
  }

  String money(int pence) =>
      NumberFormat.currency(locale: 'en_GB', symbol: '£').format(pence / 100);

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
            Text(
              'Lavoro privato · ${DateFormat.MMMM('it').format(result?.asOf ?? DateTime.now())}',
              style: Theme.of(context).textTheme.titleLarge,
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
              const Text('Maturato finora'),
              Text(
                money(result.pence),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const Text('Solo appuntamenti già terminati'),
              const SizedBox(height: 16),
              const Text('Totale previsto del mese'),
              Text(
                money(result.monthPence),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              Text(
                'Finora + ${money(result.scheduledPence)} da appuntamenti già programmati, inclusi quelli in corso',
              ),
              const SizedBox(height: 12),
              const Text('Importi lordi stimati · non incassi confermati'),
              breakdown('Dettaglio finora', result.counts, result.unpriced),
              breakdown(
                'Ancora programmati',
                result.scheduledCounts,
                result.scheduledUnpriced,
              ),
              const SizedBox(height: 12),
              Text(
                'Solo il mese corrente, secondo la data di inizio degli appuntamenti. Aggiornato al ${DateFormat('d MMMM, HH:mm', 'it').format(result.asOf)}. Calendari OPUK / Semble / heydoc, anche se nascosti in agenda. Annullati e assenze esclusi. Il previsto assume che gli appuntamenti programmati si svolgano.',
              ),
              const SizedBox(height: 8),
              const Text(
                'Tariffario settembre 2026. ADHD: valutazione e feedback separati; report incluso. ASD e tipi non riconosciuti esclusi. Prestazioni fuori calendario non comprese. Copie con titoli diversi possono essere contate due volte.',
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
