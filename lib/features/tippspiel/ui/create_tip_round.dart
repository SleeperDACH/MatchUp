import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/league_screen.dart';
import '../../../core/models/models.dart';
import '../models/tip.dart';
import '../providers.dart';

/// Erstellen einer Tipprunde: Name, Wettbewerb, Basiswertung und die frei
/// kombinierbaren Modi (Quoten-Bonus, Alleinstellungs-Bonus, Head-to-Head).
class CreateTipRoundScreen extends ConsumerStatefulWidget {
  const CreateTipRoundScreen({super.key});

  @override
  ConsumerState<CreateTipRoundScreen> createState() =>
      _CreateTipRoundScreenState();
}

class _CreateTipRoundScreenState extends ConsumerState<CreateTipRoundScreen> {
  // Punkte, die der Alleinstellungs-Bonus vergibt, wenn er aktiv ist.
  static const _soloPoints = 3;

  final _name = TextEditingController();
  LeagueInfo _league = Leagues.all.first;

  // Basiswertung.
  int _exact = 4;
  int _goalDiff = 3;
  int _tendency = 2;

  // Modi (alle standardmäßig aus — nur aktiv, wenn bewusst gewählt).
  bool _oddsBonus = false;
  double _odds1 = 3.0;
  int _points1 = 1;
  double _odds2 = 5.0;
  int _points2 = 5;
  bool _solo = false;
  bool _headToHead = false;
  bool _bonusTips = false;
  final Set<String> _bonusTipKeys = {for (final o in bonusTipQuestions) o.$1};
  int _bonusPoints = 5;

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  ScoringRules get _rules => ScoringRules(
        exact: _exact,
        goalDiff: _goalDiff,
        tendency: _tendency,
        oddsBonus: _oddsBonus,
        oddsOdds1: _odds1,
        oddsPoints1: _points1,
        oddsOdds2: _odds2,
        oddsPoints2: _points2,
        solo: _solo ? _soloPoints : 0,
        headToHead: _headToHead,
        bonusTips: _bonusTips
            ? [for (final o in bonusTipQuestions) if (_bonusTipKeys.contains(o.$1)) o.$1]
            : const [],
        bonusPoints: _bonusPoints,
      );

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
          Text('Basiswertung', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Punkte je Tipp — exaktes Ergebnis, richtige Tordifferenz, '
            'nur richtige Tendenz.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          _PointsStepper(
            label: 'Exaktes Ergebnis',
            value: _exact,
            onChanged: (v) => setState(() => _exact = v),
          ),
          _PointsStepper(
            label: 'Tordifferenz',
            value: _goalDiff,
            onChanged: (v) => setState(() => _goalDiff = v),
          ),
          _PointsStepper(
            label: 'Tendenz',
            value: _tendency,
            onChanged: (v) => setState(() => _tendency = v),
          ),
          const SizedBox(height: 24),
          Text('Modi', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Frei kombinierbar — beliebig viele gleichzeitig aktivieren.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          _ModeSwitch(
            icon: Icons.trending_up,
            title: 'Quoten-Bonus',
            subtitle:
                'Extrapunkte für richtig getippte Außenseiter — je höher die Quote, desto mehr.',
            value: _oddsBonus,
            onChanged: (v) => setState(() => _oddsBonus = v),
          ),
          if (_oddsBonus) _oddsConfig(scheme),
          _ModeSwitch(
            icon: Icons.workspace_premium_outlined,
            title: 'Alleinstellungs-Bonus',
            subtitle:
                'Wer als Einzige/r das exakte Ergebnis trifft, bekommt +$_soloPoints Punkte.',
            value: _solo,
            onChanged: (v) => setState(() => _solo = v),
          ),
          _ModeSwitch(
            icon: Icons.bolt_outlined,
            title: 'Head-to-Head',
            subtitle:
                'Jeder Spieltag als Duell zwischen zwei Mitgliedern (Sieg/Niederlage).',
            value: _headToHead,
            onChanged: (v) => setState(() => _headToHead = v),
          ),
          _ModeSwitch(
            icon: Icons.emoji_events_outlined,
            title: 'Bonustipps',
            subtitle:
                'Saison-Prognosen zusätzlich zu den Spieltagen — auswählbar unten.',
            value: _bonusTips,
            onChanged: (v) => setState(() => _bonusTips = v),
          ),
          if (_bonusTips) _bonusTipsConfig(scheme),
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

  /// Konfiguration des Quoten-Bonus: zwei Stufen (Quote + Punkte).
  Widget _oddsConfig(ColorScheme scheme) {
    Widget tier({
      required String title,
      required double odds,
      required int points,
      required ValueChanged<double> onOdds,
      required ValueChanged<int> onPoints,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            _OddsStepper(label: 'Ab Quote', value: odds, onChanged: onOdds),
            _PointsStepper(label: 'Punkte', value: points, onChanged: onPoints),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          tier(
            title: 'Außenseiter',
            odds: _odds1,
            points: _points1,
            onOdds: (v) => setState(() => _odds1 = v),
            onPoints: (v) => setState(() => _points1 = v),
          ),
          const Divider(height: 12),
          tier(
            title: 'Krasser Außenseiter',
            odds: _odds2,
            points: _points2,
            onOdds: (v) => setState(() => _odds2 = v),
            onPoints: (v) => setState(() => _points2 = v),
          ),
        ],
      ),
    );
  }

  /// Auswahl der enthaltenen Bonustipps.
  Widget _bonusTipsConfig(ColorScheme scheme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            for (final (key, label, maxTeams) in bonusTipQuestions)
              CheckboxListTile(
                dense: true,
                value: _bonusTipKeys.contains(key),
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _bonusTipKeys.add(key);
                  } else {
                    _bonusTipKeys.remove(key);
                  }
                }),
                title: Text(label),
                subtitle: maxTeams > 1 ? Text('$maxTeams Teams') : null,
              ),
            const Divider(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _PointsStepper(
                label: 'Punkte je richtiger Bonustipp',
                value: _bonusPoints,
                onChanged: (v) => setState(() => _bonusPoints = v),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kleiner +/- Stepper für einen Punktewert (0–20).
class _PointsStepper extends StatelessWidget {
  const _PointsStepper({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: value > 0 ? () => onChanged(value - 1) : null,
          ),
          SizedBox(
            width: 28,
            child: Text('$value',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: value < 20 ? () => onChanged(value + 1) : null,
          ),
        ],
      ),
    );
  }
}

/// +/- Stepper für eine Quote (1,5–10,0 in 0,5-Schritten).
class _OddsStepper extends StatelessWidget {
  const _OddsStepper({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: value > 1.5 ? () => onChanged(value - 0.5) : null,
          ),
          SizedBox(
            width: 34,
            child: Text(value.toStringAsFixed(1),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: value < 10.0 ? () => onChanged(value + 0.5) : null,
          ),
        ],
      ),
    );
  }
}

/// Ein Modus-Umschalter (unabhängig kombinierbar).
class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: value ? scheme.primary.withValues(alpha: 0.12) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: value ? scheme.primary : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        secondary: Icon(icon,
            color: value ? scheme.primary : scheme.onSurfaceVariant),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
      ),
    );
  }
}
