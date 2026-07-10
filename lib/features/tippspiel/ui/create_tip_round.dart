import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/league_screen.dart';
import '../../../core/models/models.dart';
import '../models/tip.dart';
import '../providers.dart';
import 'tip_rules_editor.dart';

/// Erstellen einer Tipprunde: Name, Wettbewerb und (über [TipRulesEditor])
/// Basiswertung samt der frei kombinierbaren Modi.
class CreateTipRoundScreen extends ConsumerStatefulWidget {
  const CreateTipRoundScreen({super.key});

  @override
  ConsumerState<CreateTipRoundScreen> createState() =>
      _CreateTipRoundScreenState();
}

class _CreateTipRoundScreenState extends ConsumerState<CreateTipRoundScreen> {
  final _name = TextEditingController();
  LeagueInfo _league = Leagues.all.first;

  // Wertung + Modi — alle Standardwerte (Modi aus), vom Editor gepflegt.
  ScoringRules _rules = const ScoringRules();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_name.text.trim().length < 3) {
      setState(() => _error = 'Bitte einen Namen mit mind. 3 Zeichen wählen.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final round = await ref.read(tipRoundRepositoryProvider).createRound(
            name: _name.text,
            league: _league,
            season: _league.seasonFor(DateTime.now()),
            rules: _rules,
          );
      ref.invalidate(myRoundsProvider);
      activateRound(ref, round);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => LeagueScreen(round: round)));
    } catch (e) {
      setState(() => _error = 'Tipprunde konnte nicht erstellt werden: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Tippspiel erstellen')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Name der Tipprunde',
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            ),
          ),
          const SizedBox(height: 20),
          Text('Wettbewerb', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          DropdownButtonFormField<LeagueInfo>(
            initialValue: _league,
            // Menü farblich vom dunklen Hintergrund abheben.
            dropdownColor: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              filled: true,
              fillColor: scheme.primary.withValues(alpha: 0.10),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    BorderSide(color: scheme.primary.withValues(alpha: 0.5)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: scheme.primary, width: 1.5),
              ),
            ),
            items: [
              for (final league in Leagues.all)
                DropdownMenuItem(
                  value: league,
                  child: Row(
                    children: [
                      Icon(Icons.emoji_events, size: 18, color: scheme.primary),
                      const SizedBox(width: 8),
                      Text(league.name),
                    ],
                  ),
                ),
            ],
            onChanged: (l) => setState(() => _league = l ?? _league),
          ),
          const SizedBox(height: 24),
          TipRulesEditor(
            initial: _rules,
            onChanged: (r) => _rules = r,
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: scheme.error)),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: const Text('Tipprunde erstellen'),
            onPressed: _busy ? null : _create,
          ),
        ],
      ),
    );
  }
}
