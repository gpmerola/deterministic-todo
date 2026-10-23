import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../domain/semble_bookings.dart';
import '../domain/task.dart';
import '../services/semble_service.dart';

/// Whether Settings hold everything a Semble block needs (build 297).
Future<bool> sembleBlockReady(SembleSettings settings) async {
  try {
    final config = await settings.read();
    return config.ready && config.roomId != null;
  } on Object {
    // No secure storage (web, tests): no block action.
    return false;
  }
}

/// Confirms and creates a Semble unavailability for [start]–[end] (build
/// 297). The sheet shows the London times Semble will store, the only
/// write is sent after "Blocca in Semble", and the snackbar offers to
/// delete exactly that block. True when the block was created.
Future<bool> showSembleBlockSheet(
  BuildContext context, {
  required DateTime start,
  required DateTime end,
  SembleSettings? settings,
  SembleClient? client,
  SembleLayer? layer,
}) async {
  final store = settings ?? SembleSettings();
  final semble = client ?? SembleClient();
  final block = sembleBlockFor(start, end);
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (block == null) {
    messenger?.showSnackBar(
      const SnackBar(
        content: Text(
          'Un blocco Semble deve stare in un solo giorno, ora di Londra.',
        ),
      ),
    );
    return false;
  }
  final created = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _SembleBlockSheet(
      start: start,
      end: end,
      block: block,
      create: (type) async {
        final config = await store.read();
        final key = await store.apiKey();
        if (key == null || config.userId == null || config.roomId == null) {
          throw const SembleException(SembleFailure.noKey);
        }
        return semble.createUnavailability(
          key: key,
          userId: config.userId!,
          roomId: config.roomId!,
          start: start,
          end: end,
          type: type,
        );
      },
    ),
  );
  if (created == null) return false;
  final shared = layer ?? SembleLayer.shared;
  Future<void> refresh() => shared.refresh(
    today: CivilDate.fromDateTime(DateTime.now()),
    force: true,
  );
  await refresh().catchError((Object _) {});
  messenger?.showSnackBar(
    SnackBar(
      content: const Text('Bloccato in Semble.'),
      duration: const Duration(seconds: 8),
      action: SnackBarAction(
        label: 'Annulla',
        onPressed: () async {
          try {
            final key = await store.apiKey();
            if (key == null) return;
            await semble.deleteUnavailability(key: key, id: created);
            await refresh();
            messenger.showSnackBar(
              const SnackBar(content: Text('Blocco Semble annullato.')),
            );
          } on Object catch (error) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  error is SembleException
                      ? 'Blocco non annullato: ${error.message}'
                      : 'Blocco non annullato: toglilo da Semble.',
                ),
              ),
            );
          }
        },
      ),
    ),
  );
  return true;
}

class _SembleBlockSheet extends StatefulWidget {
  const _SembleBlockSheet({
    required this.start,
    required this.end,
    required this.block,
    required this.create,
  });

  final DateTime start;
  final DateTime end;
  final SembleBlock block;
  final Future<String> Function(SembleBlockType type) create;

  @override
  State<_SembleBlockSheet> createState() => _SembleBlockSheetState();
}

class _SembleBlockSheetState extends State<_SembleBlockSheet> {
  SembleBlockType type = SembleBlockType.other;
  bool busy = false;
  String? error;

  Future<void> _confirm() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final id = await widget.create(type);
      if (mounted) Navigator.of(context).pop(id);
    } on Object catch (failure) {
      if (!mounted) return;
      setState(() {
        busy = false;
        error = failure is SembleException
            ? failure.message
            : 'Blocco non creato: riprova.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final day = DateFormat('EEEE d MMMM', 'it').format(widget.start);
    final hm = DateFormat.Hm('it');
    final local = '${hm.format(widget.start)}–${hm.format(widget.end)}';
    final london = '${widget.block.startTime}–${widget.block.endTime}';
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        key: const ValueKey('semble-block-sheet'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Blocca in Semble', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text('$day, $local'),
          if (local != london)
            Text(
              'In Semble: $london, ora di Londra',
              style: theme.textTheme.bodySmall,
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final option in SembleBlockType.values)
                ChoiceChip(
                  key: ValueKey('semble-block-${option.name}'),
                  label: Text(option.label),
                  selected: type == option,
                  onSelected: busy
                      ? null
                      : (_) => setState(() => type = option),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'In Semble risulterai non disponibile in questo orario, con il '
            'commento «$sembleBlockComment». Il calendario del telefono non '
            'cambia.',
            style: theme.textTheme.bodySmall,
          ),
          if (error case final message?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                message,
                key: const ValueKey('semble-block-error'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: const ValueKey('semble-block-confirm'),
              onPressed: busy ? null : _confirm,
              icon: const Icon(Icons.event_busy),
              label: Text(busy ? 'Invio…' : 'Blocca in Semble'),
            ),
          ),
        ],
      ),
    );
  }
}
