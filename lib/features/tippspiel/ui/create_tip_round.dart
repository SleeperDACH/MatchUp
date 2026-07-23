import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/league_screen.dart';
import '../../../core/models/models.dart';
import '../../leagues/ui/visibility_picker.dart';
import '../models/tip.dart';
import '../providers.dart';
import 'tip_rules_editor.dart';

/// Erstellen einer Tipprunde: Name, Wettbewerb und (über [TipRulesEditor])
/// Basiswertung samt der frei kombinierbaren Modi.
///
/// Ist [fantasyLeagueId] gesetzt, wird die Runde als **ligainternes Tippspiel**
/// an die Fantasy-Liga gekoppelt: Sichtbarkeit entfällt (Mitglieder = aktive
/// Fantasy-Mitglieder), der Name ist vorbelegt.
class CreateTipRoundScreen extends ConsumerStatefulWidget {
  const CreateTipRoundScreen({
    super.key,
    this.fantasyLeagueId,
    this.initialName,
  });

  /// Wenn gesetzt: Tipprunde an diese Fantasy-Liga koppeln.
  final String? fantasyLeagueId;

  /// Vorbelegter Name (z. B. der Fantasy-Liga-Name).
  final String? initialName;

  @override
  ConsumerState<CreateTipRoundScreen> createState() =>
      _CreateTipRoundScreenState();
}

class _CreateTipRoundScreenState extends ConsumerState<CreateTipRoundScreen> {
  final _name = TextEditingController();
  // Ausgewählte Wettbewerbe (mind. einer). Mehrere lassen sich kombinieren.
  final Set<String> _leagueIds = {Leagues.tippspiel.first.id};

  List<LeagueInfo> get _selectedLeagues =>
      [for (final l in Leagues.tippspiel) if (_leagueIds.contains(l.id)) l];

  // Wertung + Modi — alle Standardwerte (Modi aus), vom Editor gepflegt.
  ScoringRules _rules = const ScoringRules();

  String _visibility = 'private';
  String _joinPolicy = 'open';

  bool _busy = false;
  String? _error;

  bool get _linked => widget.fantasyLeagueId != null;

  @override
  void initState() {
    super.initState();
    if (widget.initialName != null) _name.text = widget.initialName!;
  }

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
    final leagues = _selectedLeagues;
    if (leagues.isEmpty) {
      setState(() => _error = 'Bitte mindestens einen Wettbewerb wählen.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = ref.read(tipRoundRepositoryProvider);
      // Gekoppelte Runden sind immer privat (Mitglieder = Fantasy-Mitglieder).
      var round = await repo.createRound(
            name: _name.text,
            leagues: leagues,
            season: leagues.first.seasonFor(DateTime.now()),
            rules: _rules,
            visibility: _linked ? 'private' : _visibility,
            joinPolicy: _linked ? 'open' : _joinPolicy,
          );
      // An die Fantasy-Liga koppeln und deren Mitglieder übernehmen. Danach
      // die Runde neu laden, damit fantasy_league_id gesetzt ist (kein
      // Chat-Tab bei gekoppelten Runden).
      if (_linked) {
        await repo.linkFantasyTipRound(round.id, widget.fantasyLeagueId!);
        ref.invalidate(fantasyTipRoundProvider(widget.fantasyLeagueId!));
        round = await repo.fetchRound(round.id);
      }
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
      appBar: AppBar(
          title: Text(_linked
              ? 'Ligainternes Tippspiel'
              : 'Tippspiel erstellen')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Ligainternes Tippspiel übernimmt den Liga-Namen — kein eigenes
          // Namensfeld nötig.
          if (!_linked) ...[
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Name der Tipprunde',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              ),
            ),
            const SizedBox(height: 20),
          ],
          Text('Wettbewerbe', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Wähle einen oder mehrere Wettbewerbe — die Spiele zählen '
            'gemeinsam in einer Tabelle.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final league in Leagues.tippspiel)
                FilterChip(
                  label: Text(league.name),
                  selected: _leagueIds.contains(league.id),
                  onSelected: (sel) => setState(() {
                    if (sel) {
                      _leagueIds.add(league.id);
                    } else if (_leagueIds.length > 1) {
                      _leagueIds.remove(league.id);
                    }
                  }),
                ),
            ],
          ),
          const SizedBox(height: 24),
          TipRulesEditor(
            initial: _rules,
            // Quoten-Modi nur, wenn ein Wettbewerb mit Quoten dabei ist
            // (Bundesliga/2. Bundesliga); DFB-Pokal hat keine Quoten.
            oddsAvailable:
                _selectedLeagues.any((l) => l.oddsSportKey != null),
            onChanged: (r) => _rules = r,
          ),
          if (_linked) ...[
            const SizedBox(height: 24),
            Text('Mitglieder',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Es spielen automatisch alle Mitglieder deiner Fantasy-Liga mit '
              '— kein eigener Beitritt nötig.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ] else ...[
            const SizedBox(height: 24),
            Text('Sichtbarkeit',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            VisibilityPicker(
              visibility: _visibility,
              joinPolicy: _joinPolicy,
              onChanged: (v, p) => setState(() {
                _visibility = v;
                _joinPolicy = p;
              }),
            ),
          ],
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
            label: Text(_linked ? 'Tippspiel aktivieren' : 'Tipprunde erstellen'),
            onPressed: _busy ? null : _create,
          ),
        ],
      ),
    );
  }
}
