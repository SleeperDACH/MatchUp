import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/form_section.dart';

import '../../leagues/ui/visibility_picker.dart';
import 'league_colors.dart';
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
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
          centerTitle: true, title: const Text('Fantasy-Liga erstellen')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          FormSection(
            titel: 'Name',
            kinder: [
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'z. B. Büro-Liga 26/27',
                  // Der Abschnitt ist die Fläche; das Feld bringt keine
                  // zweite mit.
                  filled: false,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          FormSection(
            titel: 'Teams',
            hinweis: 'So viele Manager passen in die Liga. Später änderbar, '
                'solange der Draft nicht läuft.',
            kinder: [
              _StepperRow(
                label: 'Teams',
                value: _teams,
                min: _minTeams,
                max: _maxTeams,
                onChanged: (v) => setState(() => _teams = v),
              ),
            ],
          ),
          FormSection(
            titel: 'Modus',
            kinder: [
              for (final mode in FantasyMode.values)
                Padding(
                  padding: EdgeInsets.only(
                      bottom: mode == FantasyMode.values.last ? 0 : 10),
                  child: _ModeCard(
                    mode: mode,
                    selected: _mode == mode,
                    onTap: () => setState(() => _mode = mode),
                  ),
                ),
            ],
          ),
          FormSection(
            titel: 'Sichtbarkeit',
            kinder: [
              VisibilityPicker(
                visibility: _visibility,
                joinPolicy: _joinPolicy,
                onChanged: (v, p) => setState(() {
                  _visibility = v;
                  _joinPolicy = p;
                }),
              ),
            ],
          ),
          FormSection(
            titel: 'Tippspiel',
            kinder: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _tipEnabled,
                onChanged: (v) => setState(() => _tipEnabled = v),
                title: const Text('Ligainternes Tippspiel',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text(
                    'Zusätzlich ein Tippspiel mit denselben Mitgliedern. '
                    'Lässt sich auch später einschalten.'),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Draft- und Playoff-Einstellungen legst du später in den '
              'Liga-Einstellungen fest.',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            FormError(text: _error!),
          ],
        ],
      ),
      // Der Knopf steht fest unten, statt ans Ende der Liste zu rutschen:
      // wer oben etwas ändert, muss nicht erst nach unten scrollen, um zu
      // sehen, dass es weitergeht.
      bottomNavigationBar: FormActionBar(
        label: 'Liga erstellen',
        busy: _busy,
        onPressed: _busy ? null : _create,
      ),
    );
  }
}

/// Auswahl des Modus. Die gewählte Karte trägt die Farbe **ihres** Modus —
/// Redraft grün, Dynasty rot, dieselbe Zuordnung wie auf dem Homescreen. So
/// lernt man die Farbe schon beim Anlegen.
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
    final farbe = leagueColor(mode);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? farbe.withValues(alpha: 0.14) : null,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? farbe.withValues(alpha: 0.75)
                  : scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: Row(
            children: [
              Icon(
                mode == FantasyMode.dynasty
                    ? Icons.auto_awesome
                    : Icons.calendar_today,
                size: 20,
                color: selected ? farbe : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(mode.label,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                    Text(mode.tagline,
                        style: TextStyle(
                            color: scheme.onSurfaceVariant, fontSize: 12.5)),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                color: selected ? farbe : scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
    // Ohne eigene Fläche: der umgebende [FormSection] bringt sie mit, sonst
    // steht ein Kasten im Kasten.
    return SizedBox(
      height: 40,
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
