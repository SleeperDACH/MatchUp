import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tip.dart';
import '../models/tip_round.dart';
import '../providers.dart';
import 'tip_rules_editor.dart';

/// Liga-Einstellungen (nur Ersteller): Wertung & Modi einer bestehenden
/// Tipprunde nachträglich ändern — dieselben Optionen wie beim Erstellen.
class TipRulesSettingsScreen extends ConsumerStatefulWidget {
  const TipRulesSettingsScreen({super.key, required this.round});

  final TipRound round;

  @override
  ConsumerState<TipRulesSettingsScreen> createState() =>
      _TipRulesSettingsScreenState();
}

class _TipRulesSettingsScreenState
    extends ConsumerState<TipRulesSettingsScreen> {
  late ScoringRules _rules = widget.round.scoring;
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref
          .read(tipRoundRepositoryProvider)
          .updateScoring(widget.round.id, _rules);
      // Aktive Runde aktualisieren, damit die Änderung sofort durchschlägt.
      activateRound(ref, widget.round.copyWith(scoring: _rules));
      ref.invalidate(myRoundsProvider);
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
          const SnackBar(content: Text('Einstellungen gespeichert.')));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Speichern fehlgeschlagen: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Liga-Einstellungen')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Änderungen an der Wertung gelten rückwirkend für die ganze '
              'Saison — die Tabelle wird neu berechnet.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 16),
          TipRulesEditor(
            initial: widget.round.scoring,
            onChanged: (r) => _rules = r,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_outlined),
            label: const Text('Speichern'),
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    );
  }
}
