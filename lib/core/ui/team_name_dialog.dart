import 'package:flutter/material.dart';

/// Dialog zum Setzen/Ändern des ligaspezifischen Teamnamens. Gibt den neuen
/// Namen zurück (leerer String = zurücksetzen auf den Nutzernamen) oder `null`,
/// wenn abgebrochen wurde.
Future<String?> showTeamNameDialog(BuildContext context, {String? current}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TeamNameDialog(current: current),
  );
}

/// Eigenes StatefulWidget, damit der [TextEditingController] erst nach dem
/// Schließen (inkl. Ausblend-Animation) entsorgt wird — sonst greift das
/// TextField beim Wegblenden auf einen bereits disposed Controller zu.
class _TeamNameDialog extends StatefulWidget {
  const _TeamNameDialog({this.current});

  final String? current;

  @override
  State<_TeamNameDialog> createState() => _TeamNameDialogState();
}

class _TeamNameDialogState extends State<_TeamNameDialog> {
  late final _controller = TextEditingController(text: widget.current ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Teamname in dieser Liga'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Wird in dieser Liga überall statt deines Nutzernamens angezeigt. '
            'Leer = wieder dein Nutzername.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: 24,
            decoration: const InputDecoration(
              labelText: 'Teamname',
              contentPadding: EdgeInsets.symmetric(horizontal: 12),
            ),
            onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}
