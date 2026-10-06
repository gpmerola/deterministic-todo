import 'package:flutter/material.dart';

class AgendaZonePicker extends StatefulWidget {
  const AgendaZonePicker({required this.zones, super.key});
  final List<String> zones;
  @override
  State<AgendaZonePicker> createState() => AgendaZonePickerState();
}

class AgendaZonePickerState extends State<AgendaZonePicker> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final shown = widget.zones
        .where((z) => z.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return AlertDialog(
      title: const Text('Fuso orario IANA'),
      content: SizedBox(
        width: 400,
        height: 360,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Cerca città o fuso',
              ),
              onChanged: (text) => setState(() => query = text),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: shown.length,
                itemBuilder: (context, i) => ListTile(
                  title: Text(shown[i]),
                  onTap: () => Navigator.pop(context, shown[i]),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annulla'),
        ),
      ],
    );
  }
}
