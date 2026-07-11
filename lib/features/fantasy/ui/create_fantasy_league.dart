import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/fantasy_models.dart';
import '../providers.dart';
import 'fantasy_league_screen.dart';

/// Erstellen einer Fantasy-Liga: Modus (Liga/Dynasty), Name und Pickzeit.
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
  DraftPickTime _pickTime = DraftPickTime.m1;

  // Liga-Einstellungen (in die Erstell-Maske gezogen).
  static const _minTeams = 2;
  static const _maxTeams = 18;
  static const _minRounds = 14;
  static const _maxRounds = 30;
  int _teams = 10; // Standard-Teilnehmerzahl
  int _rounds = RosterConfig.standard.squadSize; // Kadergröße = Draft-Runden
  String _orderMode = 'auto'; // 'auto' = zufällig, 'manual' = per Reihenfolge
  bool _pauseOn = false; // Slow-Draft-Nachtpause
  bool _playoffsOn = false;

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String get _draftSummary =>
      '$_rounds Spieler · ${_orderMode == 'manual' ? 'Manuell' : 'Zufällig'} · '
      '${_pickTime.label}${_pauseOn ? ' · Nachtpause' : ''}';

  /// Öffnet die gebündelten Draft-Einstellungen in einem eigenen Fenster und
  /// übernimmt die Auswahl.
  Future<void> _openDraftSettings() async {
    final result = await Navigator.of(context).push<_DraftConfig>(
      MaterialPageRoute(
        builder: (_) => _DraftSettingsScreen(
          rounds: _rounds,
          minRounds: _minRounds,
          maxRounds: _maxRounds,
          orderMode: _orderMode,
          pauseOn: _pauseOn,
          pickTime: _pickTime,
        ),
      ),
    );
    if (result == null) return;
    setState(() {
      _rounds = result.rounds;
      _orderMode = result.orderMode;
      _pauseOn = result.pauseOn;
      _pickTime = result.pickTime;
    });
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
                pickTime: _pickTime,
                roster: RosterConfig.standard.withRounds(_rounds),
                maxTeams: _teams,
                draftOrderMode: _orderMode,
                // Nachtpause 23–8 Uhr, wenn aktiviert (Minuten seit Mitternacht).
                pauseStart: _pauseOn ? 23 * 60 : null,
                pauseEnd: _pauseOn ? 8 * 60 : null,
                // Playoffs: Standard 4 Teams · 1-Wochen-Partien.
                playoffTeams: _playoffsOn ? 4 : null,
                playoffWeeks: _playoffsOn ? 1 : null,
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
          Text('Modus', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final mode in FantasyMode.values)
            _ModeCard(
              mode: mode,
              selected: _mode == mode,
              onTap: () => setState(() => _mode = mode),
            ),
          const SizedBox(height: 20),
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
          const SizedBox(height: 4),
          Text(
            'Wie viele Teams die Liga hat. Team 1 bist du; die übrigen Teams '
            'werden angelegt und mit beitretenden Spielern aufgefüllt.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          _StepperRow(
            label: 'Teams',
            value: _teams,
            min: _minTeams,
            max: _maxTeams,
            onChanged: (v) => setState(() => _teams = v),
          ),
          const SizedBox(height: 20),
          // Draft-Einstellungen gebündelt in einem eigenen Fenster.
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.sports_esports_outlined),
              title: const Text('Draft-Einstellungen'),
              subtitle: Text(_draftSummary),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openDraftSettings,
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _playoffsOn,
            onChanged: (v) => setState(() => _playoffsOn = v),
            title: const Text('Playoffs'),
            subtitle: const Text('4 Teams · 1-Wochen-Partien (später änderbar).'),
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

/// Ergebnis der gebündelten Draft-Einstellungen.
class _DraftConfig {
  const _DraftConfig({
    required this.rounds,
    required this.orderMode,
    required this.pauseOn,
    required this.pickTime,
  });

  final int rounds;
  final String orderMode;
  final bool pauseOn;
  final DraftPickTime pickTime;
}

/// Eigenes Fenster für die Draft-Einstellungen beim Erstellen einer Liga:
/// Kadergröße, Reihenfolge, Pickzeit und Slow-Draft-Nachtpause.
class _DraftSettingsScreen extends StatefulWidget {
  const _DraftSettingsScreen({
    required this.rounds,
    required this.minRounds,
    required this.maxRounds,
    required this.orderMode,
    required this.pauseOn,
    required this.pickTime,
  });

  final int rounds;
  final int minRounds;
  final int maxRounds;
  final String orderMode;
  final bool pauseOn;
  final DraftPickTime pickTime;

  @override
  State<_DraftSettingsScreen> createState() => _DraftSettingsScreenState();
}

class _DraftSettingsScreenState extends State<_DraftSettingsScreen> {
  late int _rounds = widget.rounds;
  late String _orderMode = widget.orderMode;
  late bool _pauseOn = widget.pauseOn;
  late DraftPickTime _pickTime = widget.pickTime;

  @override
  Widget build(BuildContext context) {
    final onVariant = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(title: const Text('Draft-Einstellungen')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Kadergröße', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '11 in der Startelf + ${_rounds - 11} auf der Bank '
            '(= $_rounds Draft-Runden).',
            style:
                Theme.of(context).textTheme.bodySmall?.copyWith(color: onVariant),
          ),
          const SizedBox(height: 8),
          _StepperRow(
            label: 'Spieler je Kader',
            value: _rounds,
            min: widget.minRounds,
            max: widget.maxRounds,
            onChanged: (v) => setState(() => _rounds = v),
          ),
          const SizedBox(height: 20),
          Text('Draft-Reihenfolge',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'auto', label: Text('Zufällig')),
              ButtonSegment(value: 'manual', label: Text('Manuell')),
            ],
            selected: {_orderMode},
            onSelectionChanged: (s) => setState(() => _orderMode = s.first),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _pauseOn,
            onChanged: (v) => setState(() => _pauseOn = v),
            title: const Text('Slow-Draft-Nachtpause'),
            subtitle: const Text('Draft pausiert nachts von 23 bis 8 Uhr.'),
          ),
          const SizedBox(height: 20),
          Text('Pickzeit im Draft',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Wie lange jeder Manager pro Pick Zeit hat. Kurze Zeiten = '
            'Live-Draft, lange Zeiten = Slow-Draft über Tage.',
            style:
                Theme.of(context).textTheme.bodySmall?.copyWith(color: onVariant),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<DraftPickTime>(
            initialValue: _pickTime,
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(horizontal: 12),
            ),
            items: [
              for (final t in DraftPickTime.values)
                DropdownMenuItem(
                  value: t,
                  child: Row(
                    children: [
                      Text(t.label),
                      const SizedBox(width: 8),
                      _Chip(text: t.isLive ? 'Live' : 'Slow'),
                    ],
                  ),
                ),
            ],
            onChanged: (t) => setState(() => _pickTime = t ?? _pickTime),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.check),
            label: const Text('Übernehmen'),
            onPressed: () => Navigator.of(context).pop(_DraftConfig(
              rounds: _rounds,
              orderMode: _orderMode,
              pauseOn: _pauseOn,
              pickTime: _pickTime,
            )),
          ),
        ],
      ),
    );
  }
}

/// Kompakte +/–-Zeile für Zahlenwerte (Teilnehmer, Kadergröße).
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

class _Chip extends StatelessWidget {
  const _Chip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
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
