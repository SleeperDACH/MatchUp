import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../leagues/ui/visibility_picker.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';
import 'fantasy_league_screen.dart';

/// Erstellen einer Fantasy-Liga: nur das Nötigste — Modus, Name und
/// Teilnehmerzahl. Draft- und Playoff-Details bekommen sinnvolle Standards
/// und sind nachträglich in den Liga-Einstellungen anpassbar.
class CreateFantasyLeagueScreen extends ConsumerStatefulWidget {
  const CreateFantasyLeagueScreen({super.key, required this.mode});

  final FantasyMode mode;

  @override
  ConsumerState<CreateFantasyLeagueScreen> createState() =>
      _CreateFantasyLeagueScreenState();
}

class _CreateFantasyLeagueScreenState
    extends ConsumerState<CreateFantasyLeagueScreen> {
  final _name = TextEditingController();
  late FantasyMode _mode = widget.mode;

  static const _minTeams = 2;
  static const _maxTeams = 18;
  int _teams = 10; // Standard-Teilnehmerzahl

  String _visibility = 'private';
  String _joinPolicy = 'open';
  bool _tipEnabled = false;

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
      final league =
          await ref.read(fantasyLeagueRepositoryProvider).createLeague(
                name: _name.text,
                mode: _mode,
                season: ref.read(fantasySeasonProvider),
                // Draft-Standards (später in den Einstellungen änderbar).
                pickTime: DraftPickTime.m1,
                roster: RosterConfig.standard,
                maxTeams: _teams,
                draftOrderMode: 'auto',
                // Fantasy geht immer in die Playoffs: Standard 4 Teams ·
                // 1-Wochen-Partien. Feinjustierung später in den Einstellungen.
                playoffTeams: 4,
                playoffWeeks: 1,
                visibility: _visibility,
                joinPolicy: _joinPolicy,
                tipEnabled: _tipEnabled,
              );
      ref.invalidate(myFantasyLeaguesProvider);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => FantasyLeagueScreen(league: league)));
    } catch (e) {
      setState(() => _error = 'Liga konnte nicht erstellt werden: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fantasy-Liga erstellen')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Name der Liga', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Name der Liga',
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            ),
          ),
          const SizedBox(height: 20),
          Text('Teilnehmerzahl',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _StepperRow(
            label: 'Teams',
            value: _teams,
            min: _minTeams,
            max: _maxTeams,
            onChanged: (v) => setState(() => _teams = v),
          ),
          const SizedBox(height: 20),
          Text('Modus', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final mode in FantasyMode.values)
            _ModeCard(
              mode: mode,
              selected: _mode == mode,
              onTap: () => setState(() => _mode = mode),
            ),
          const SizedBox(height: 20),
          Text('Sichtbarkeit', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          VisibilityPicker(
            visibility: _visibility,
            joinPolicy: _joinPolicy,
            onChanged: (v, p) => setState(() {
              _visibility = v;
              _joinPolicy = p;
            }),
          ),
          const SizedBox(height: 20),
          Text('Tippspiel', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _tipEnabled,
            onChanged: (v) => setState(() => _tipEnabled = v),
            title: const Text('Ligainternes Tippspiel'),
            subtitle: const Text(
                'Zusätzlich zum Fantasy ein Tippspiel mit denselben '
                'Mitgliedern — später auf der Übersicht einrichtbar. Du kannst '
                'es auch nachträglich in den Einstellungen einschalten.'),
          ),
          const SizedBox(height: 12),
          Text(
            'Draft- und Playoff-Einstellungen sind später in den '
            'Liga-Einstellungen anpassbar.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: const Text('Liga erstellen'),
            onPressed: _busy ? null : _create,
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final FantasyMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: selected ? scheme.primary.withValues(alpha: 0.15) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? scheme.primary : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: ListTile(
        leading: Icon(
          mode == FantasyMode.dynasty ? Icons.auto_awesome : Icons.calendar_today,
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
        ),
        title: Text(mode.label,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(mode.tagline),
        trailing: selected
            ? Icon(Icons.check_circle, color: scheme.primary)
            : const Icon(Icons.circle_outlined),
        onTap: onTap,
      ),
    );
  }
}

/// Kompakte +/–-Zeile für Zahlenwerte (Teilnehmerzahl).
class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: value > min ? () => onChanged(value - 1) : null,
          ),
          SizedBox(
            width: 28,
            child: Text('$value',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: value < max ? () => onChanged(value + 1) : null,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Einstiegs-Flows (vom Homescreen)
// ---------------------------------------------------------------------

void createFantasyLeagueFlow(BuildContext context, FantasyMode mode) {
  Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CreateFantasyLeagueScreen(mode: mode)));
}
