import 'package:flutter/material.dart';
import 'remis_grenze_editor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/typografie.dart';
import '../../../core/ui/einstellungs_zeile.dart';
import '../../../core/ui/form_section.dart';

import '../models/fantasy_models.dart';
import '../providers.dart';
import 'kader_limits_editor.dart';
import '../../../core/ui/wert_stepper.dart';
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

  /// Fest: Es gibt nur noch Redraft. Bleibt als Feld, weil die Liga beim
  /// Anlegen einen Modus mitbekommt — die Auswahl davor ist entfallen.
  late final FantasyMode _mode = widget.mode;

  static const _minTeams = 2;
  static const _maxTeams = 18;
  int _teams = 10; // Standard-Teilnehmerzahl

  String _visibility = 'private';
  String _joinPolicy = 'open';
  bool _tipEnabled = false;

  /// Unentschieden bei knappem Ausgang — neue Ligen starten mit 10
  /// (16.10.2026), änderbar oder abschaltbar.
  double? _remisGrenze = FantasyLeague.remisGrenzeStandard;
  bool _resetAktiv = false;

  /// **Kader-Limits, schon beim Anlegen.** `null` = keine Einschränkung, und
  /// das ist der Standard: Eine stillschweigend eingeführte Obergrenze wäre
  /// eine Regel, die niemand gewählt hat. Wer sie will, schaltet sie hier ein
  /// — oder später unter Regeln & Format.
  final Map<PlayerPosition, int?> _limits = {
    for (final pos in PlayerPosition.values) pos: null,
  };

  /// Die Kaderform steht beim Erstellen fest; die Limits hängen daran (die
  /// Untergrenze je Position kommt aus der Startelf).
  RosterConfig get _rosterMitLimits => RosterConfig(
    gk: RosterConfig.standard.gk,
    def: RosterConfig.standard.def,
    mid: RosterConfig.standard.mid,
    fwd: RosterConfig.standard.fwd,
    bench: RosterConfig.standard.bench,
    defMin: RosterConfig.standard.defMin,
    defMax: RosterConfig.standard.defMax,
    midMin: RosterConfig.standard.midMin,
    midMax: RosterConfig.standard.midMax,
    fwdMin: RosterConfig.standard.fwdMin,
    fwdMax: RosterConfig.standard.fwdMax,
    maxGk: _limits[PlayerPosition.gk],
    maxDef: _limits[PlayerPosition.def],
    maxMid: _limits[PlayerPosition.mid],
    maxFwd: _limits[PlayerPosition.fwd],
  );

  bool get _limitsTragenDenKader =>
      KaderLimitsEditor.reichtFuerKader(RosterConfig.standard, _limits);

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
    // **16 Kaderplätze bei Limits, die zusammen 12 ergeben, sind nicht streng,
    // sondern kaputt:** Der Draft fände keinen erlaubten Spieler mehr und
    // beendete sich selbst. Dieselbe Sperre wie in den Einstellungen.
    if (!_limitsTragenDenKader) {
      setState(
        () => _error =
            'Die Kader-Limits ergeben zusammen weniger Plätze, als der Kader '
            'hat. So findet der Draft irgendwann keinen erlaubten Spieler mehr.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final league = await ref
          .read(fantasyLeagueRepositoryProvider)
          .createLeague(
            name: _name.text,
            mode: _mode,
            season: ref.read(fantasySeasonProvider),
            // Draft-Standards (später in den Einstellungen änderbar).
            pickTime: DraftPickTime.m1,
            roster: _rosterMitLimits,
            maxTeams: _teams,
            draftOrderMode: 'auto',
            // Fantasy geht immer in die Playoffs: Standard 4 Teams ·
            // 1-Wochen-Partien. Feinjustierung später in den Einstellungen.
            playoffTeams: 4,
            playoffWeeks: 1,
            visibility: _visibility,
            joinPolicy: _joinPolicy,
            tipEnabled: _tipEnabled,
            remisGrenze: _remisGrenze,
            resetAktiv: _resetAktiv,
          );
      ref.invalidate(myFantasyLeaguesProvider);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => FantasyLeagueScreen(league: league)),
      );
    } catch (e) {
      setState(() => _error = 'Liga konnte nicht erstellt werden: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final oeffentlich = _visibility == 'public';
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Fantasy-Liga erstellen'),
      ),
      // **Jede Einstellung ist dieselbe Zeile** (18.10.2026, auf Ansage: „zu
      // viel Ungleichheit … das muss alles einheitlich aussehen"). Vorher
      // standen drei Titelgrößen, gerahmte Auswahlkästen nur bei der
      // Sichtbarkeit, grüne Symbole bei den Kader-Limits und fünf
      // Erklärsätze untereinander. Jetzt: Bezeichnung links in Textgröße,
      // Bedienung rechts, höchstens eine kurze Zeile darunter.
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          FormSection(
            titel: 'Liga',
            kinder: [
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                style: einstellungsStil,
                decoration: const InputDecoration(
                  hintText: 'Name, z. B. Büro-Liga 26/27',
                  // Der Abschnitt ist die Fläche; das Feld bringt keine
                  // zweite mit.
                  filled: false,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const EinstellungsTrenner(),
              EinstellungsZeile(
                label: 'Teams',
                rechts: WertStepper(
                  label: 'Teams',
                  value: _teams,
                  min: _minTeams,
                  max: _maxTeams,
                  onChanged: (v) => setState(() => _teams = v),
                ),
              ),
            ],
          ),
          // **Keine Modusauswahl mehr.** Es gibt nur noch Redraft (Dynasty ist
          // am 27.09.2026 entfernt worden).
          FormSection(
            titel: 'Sichtbarkeit',
            kinder: [
              EinstellungsSchalter(
                label: 'Öffentlich',
                unter: 'In der Suche findbar',
                wert: oeffentlich,
                onChanged: (v) =>
                    setState(() => _visibility = v ? 'public' : 'private'),
              ),
              if (oeffentlich) ...[
                const EinstellungsTrenner(),
                EinstellungsSchalter(
                  label: 'Nur auf Einladung',
                  unter: 'Beitritt nach deiner Bestätigung',
                  wert: _joinPolicy == 'invite',
                  onChanged: (v) =>
                      setState(() => _joinPolicy = v ? 'invite' : 'open'),
                ),
              ],
            ],
          ),
          FormSection(
            titel: 'Unentschieden',
            kinder: [
              RemisGrenzeEditor(
                wert: _remisGrenze,
                onChanged: (v) => setState(() => _remisGrenze = v),
              ),
            ],
          ),
          // **Reset zur Winterpause** (0143, auf Ansage): am 24.12. neuer
          // Draft für die Rückrunde, die Tabelle bleibt.
          FormSection(
            titel: 'Winterpause',
            kinder: [
              EinstellungsSchalter(
                label: 'Reset',
                unter: 'Am 24.12. neuer Draft, die Tabelle bleibt',
                wert: _resetAktiv,
                onChanged: (v) => setState(() => _resetAktiv = v),
              ),
            ],
          ),
          FormSection(
            titel: 'Kader-Limits',
            kinder: [
              KaderLimitsEditor(
                roster: RosterConfig.standard,
                limits: _limits,
                onChanged: (neu) => setState(() {
                  _limits
                    ..clear()
                    ..addAll(neu);
                }),
              ),
              // Nur wenn es nicht aufgeht — sonst sagen die Zeilen alles.
              if (!_limitsTragenDenKader)
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 4),
                  child: Text(
                    KaderLimitsEditor.hinweisText(
                      RosterConfig.standard,
                      _limits,
                    ),
                    style: TextStyle(
                      fontSize: Schrift.label,
                      color: scheme.error,
                    ),
                  ),
                ),
            ],
          ),
          FormSection(
            titel: 'Tippspiel',
            kinder: [
              EinstellungsSchalter(
                label: 'Ligainternes Tippspiel',
                unter: 'Mit denselben Mitgliedern',
                wert: _tipEnabled,
                onChanged: (v) => setState(() => _tipEnabled = v),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            FormError(text: _error!),
          ],
        ],
      ),
      // Der Knopf steht fest unten, statt ans Ende der Liste zu rutschen.
      bottomNavigationBar: FormActionBar(
        label: 'Liga erstellen',
        busy: _busy,
        onPressed: _busy ? null : _create,
      ),
    );
  }
}

// `_ModeCard` stand hier für die Auswahl zwischen Redraft und Dynasty. Mit
// dem Wegfall des zweiten Modus (27.09.2026) hat sie keinen Aufrufer mehr —
// und eine Auswahlkachel für genau eine Option wäre eine Entscheidung, die
// niemand treffen kann.

// ---------------------------------------------------------------------
// Einstiegs-Flows (vom Homescreen)
// ---------------------------------------------------------------------

void createFantasyLeagueFlow(BuildContext context, FantasyMode mode) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => CreateFantasyLeagueScreen(mode: mode)),
  );
}
