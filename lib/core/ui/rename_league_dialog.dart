import 'package:flutter/material.dart';

/// Dialog zum Umbenennen einer Liga/Tipprunde. Gibt den neuen (getrimmten)
/// Namen zurück oder `null` bei Abbruch / zu kurzem Namen (< 3 Zeichen).
Future<String?> showRenameLeagueDialog(BuildContext context,
    {required String current}) async {
  final result = await showDialog<String>(
    context: context,
    builder: (_) => _RenameLeagueDialog(current: current),
  );
  if (result == null || result.trim().length < 3) return null;
  return result.trim();
}

/// Eigenes StatefulWidget, damit der [TextEditingController] erst nach dem
/// Schließen (inkl. Ausblend-Animation) entsorgt wird — sonst greift das
/// TextField beim Wegblenden auf einen bereits disposed Controller zu
/// (Assertion `_dependents.isEmpty`).
class _RenameLeagueDialog extends StatefulWidget {
  const _RenameLeagueDialog({required this.current});

  final String current;

  @override
  State<_RenameLeagueDialog> createState() => _RenameLeagueDialogState();
}

class _RenameLeagueDialogState extends State<_RenameLeagueDialog> {
  late final _controller = TextEditingController(text: widget.current);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Liga-Name ändern'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 64,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Name der Liga',
          helperText: '3–64 Zeichen',
        ),
        onSubmitted: (_) => Navigator.of(context).pop(_controller.text.trim()),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen')),
        FilledButton(
            onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
            child: const Text('Speichern')),
      ],
    );
  }
}
