import 'package:flutter/material.dart';

import '../domain/link_syntax.dart';

class TaskLinkDialog extends StatefulWidget {
  const TaskLinkDialog({this.selectedText, super.key});
  final String? selectedText;
  @override
  State<TaskLinkDialog> createState() => _TaskLinkDialogState();
}

class _TaskLinkDialogState extends State<TaskLinkDialog> {
  final url = TextEditingController();
  late final label = TextEditingController(text: widget.selectedText);
  String? error;
  @override
  void dispose() {
    url.dispose();
    label.dispose();
    super.dispose();
  }

  void _submit() {
    final uri = Uri.tryParse(normalizeWebUrl(url.text));
    if (uri == null ||
        uri.host.isEmpty ||
        !(uri.isScheme('https') || uri.isScheme('http')) ||
        uri.toString().contains(')') ||
        RegExp(r'[\[\]]').hasMatch(label.text)) {
      setState(() => error = 'Inserisci un indirizzo Web valido.');
      return;
    }
    Navigator.pop(context, (url: uri.toString(), label: label.text.trim()));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Aggiungi link'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: const ValueKey('link-url'),
          controller: url,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: 'Indirizzo',
            hintText: 'https://…',
            errorText: error,
          ),
          onSubmitted: (_) => _submit(),
        ),
        TextField(
          key: const ValueKey('link-label'),
          controller: label,
          decoration: const InputDecoration(labelText: 'Nome (facoltativo)'),
          onSubmitted: (_) => _submit(),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annulla'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Collega')),
    ],
  );
}
