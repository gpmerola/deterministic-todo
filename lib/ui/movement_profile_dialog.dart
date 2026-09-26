import 'package:flutter/material.dart';

class MovementProfileDialog extends StatefulWidget {
  const MovementProfileDialog({required this.values, super.key});
  final Map<String, Object?> values;

  @override
  State<MovementProfileDialog> createState() => _MovementProfileDialogState();
}

class _MovementProfileDialogState extends State<MovementProfileDialog> {
  final form = GlobalKey<FormState>();
  late final weight = TextEditingController(text: _initial('weight_kg', 70));
  late final walking = TextEditingController(
    text: _initial('walking_stride_meters', .72),
  );
  late final running = TextEditingController(
    text: _initial('running_stride_meters', 1.05),
  );

  String _initial(String key, double fallback) =>
      ((widget.values[key] as num?)?.toDouble() ?? fallback).toStringAsFixed(2);
  double? _number(String? text) =>
      double.tryParse((text ?? '').replaceAll(',', '.'));

  @override
  void dispose() {
    weight.dispose();
    walking.dispose();
    running.dispose();
    super.dispose();
  }

  Widget _field(
    String label,
    TextEditingController controller,
    double min,
    double max,
  ) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
      validator: (text) {
        final value = _number(text);
        return value == null || !value.isFinite || value < min || value > max
            ? 'Inserisci un valore tra $min e $max'
            : null;
      },
    ),
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Profilo movimento'),
    content: SingleChildScrollView(
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Parametri salvati solo su questo dispositivo. Distanze e calorie restano stime. La calibrazione può aggiornare la lunghezza del passo.',
            ),
            _field('Peso (kg)', weight, 25, 300),
            _field('Passo camminata (m)', walking, .30, 1.50),
            _field('Passo corsa (m)', running, .40, 2.50),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annulla'),
      ),
      FilledButton(
        onPressed: () {
          if (!form.currentState!.validate()) return;
          Navigator.pop(context, <String, double>{
            'weight_kg': _number(weight.text)!,
            'walking_stride_meters': _number(walking.text)!,
            'running_stride_meters': _number(running.text)!,
          });
        },
        child: const Text('Salva'),
      ),
    ],
  );
}
