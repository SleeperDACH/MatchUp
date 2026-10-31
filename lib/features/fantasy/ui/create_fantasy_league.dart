import '../../../core/ui/schritt_formular.dart';
import '../../../app/widgets/pill_selector.dart';
import '../logic/playoff.dart';
import '../../../app/widgets/competition_picker.dart';
import '../../../core/models/models.dart';
import '../../tippspiel/models/tip.dart' show ScoringRules;
import '../../tippspiel/providers.dart'
    show tipRoundRepositoryProvider, fantasyTipRoundProvider, myRoundsProvider;
import '../../tippspiel/ui/tip_rules_editor.dart';
import '../../../app/erklaerungen.dart';
import '../../../app/widgets/info_knopf.dart';
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

/// Erstellen einer Fantasy-Liga **in vier Schritten** (29.10.2026, auf
/// Ansage): Liga (Name, Teams) · Draft · Saison · Mitspieler, zuletzt
/// „Liga erstellen". Jede Einstellung steht offen da — auch Draft-Zeit,
/// Runden, Reihenfolge und Playoffs, die es vorher nur nachträglich in den
/// Liga-Einstellungen gab.
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

  /// **Ligainternes Tippspiel gleich mit einrichten** (30.10.2026, auf
  /// Ansage): Wer es einschaltet, sieht darunter sofort Wettbewerbe, Punkte
  /// und Modi — und die Tipprunde entsteht zusammen mit der Liga, statt
  /// später über einen eigenen Schirm.
  final Set<String> _tipLigen = {Leagues.tippspiel.first.id};
  ScoringRules _tipRegeln = const ScoringRules();

  List<LeagueInfo> get _tipWettbewerbe => [
    for (final l in Leagues.tippspiel)
      if (_tipLigen.contains(l.id)) l,
  ];

  /// Unentschieden bei knappem Ausgang — neue Ligen starten mit 10
  /// (16.10.2026), änderbar oder abschaltbar.
  double? _remisGrenze = FantasyLeague.remisGrenzeStandard;
  bool _resetAktiv = false;

  // Draft (vorher feste Standards, nur nachträglich änderbar).
  static const _minRunden = 14;
  static const _maxRunden = 30;
  DraftPickTime _pickTime = DraftPickTime.m1;
  int _runden = RosterConfig.standard.squadSize;
  String _reihenfolge = 'auto';

  // Playoffs — dieselben Grenzen wie in den Playoff-Einstellungen.
  int _playoffTeams = 4;
  int _playoffWochen = 1;
  int _tradeDeadline = 5;

  PlayoffPlan get _plan => computePlayoffPlan(
    teams: _playoffTeams,
    weeksPerRound: _playoffWochen,
    tradeDeadlineOffset: _tradeDeadline,
  );

  /// **Kader-Limits, schon beim Anlegen.** `null` = keine Einschränkung, und
  /// das ist der Standard: Eine stillschweigend eingeführte Obergrenze wäre
  /// eine Regel, die niemand gewählt hat. Wer sie will, schaltet sie hier ein
  /// — oder später in den Einstellungen unter Draft.
  /// Vereins-Limit (0153), `null` = ohne.
  int? _vereinsLimit;

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
    bench: RosterConfig.standard.withRounds(_runden).bench,
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
    maxJeVerein: _vereinsLimit,
  );

  bool get _limitsTragenDenKader =>
      KaderLimitsEditor.reichtFuerKader(_rosterMitLimits, _limits);

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
            pickTime: _pickTime,
            roster: _rosterMitLimits,
            maxTeams: _teams,
            draftOrderMode: _reihenfolge,
            playoffTeams: _playoffTeams,
            playoffWeeks: _playoffWochen,
            tradeDeadlineOffset: _tradeDeadline,
            visibility: _visibility,
            joinPolicy: _joinPolicy,
            tipEnabled: _tipEnabled,
            remisGrenze: _remisGrenze,
            resetAktiv: _resetAktiv,
          );
      if (_tipEnabled) await _tippspielAnlegen(league.id);
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

  /// Legt die Tipprunde an und koppelt sie an die Liga — derselbe Weg wie
  /// „Ligainternes Tippspiel" (`CreateTipRoundScreen` mit Liga). Scheitert
  /// das, steht die Liga trotzdem; das Tippspiel lässt sich dann über die
  /// Liga-Übersicht nachholen.
  Future<void> _tippspielAnlegen(String ligaId) async {
    try {
      final repo = ref.read(tipRoundRepositoryProvider);
      final ligen = _tipWettbewerbe;
      final runde = await repo.createRound(
        name: _name.text,
        leagues: ligen,
        season: ligen.first.seasonFor(DateTime.now()),
        rules: _tipRegeln,
        visibility: 'private',
        joinPolicy: 'open',
      );
      await repo.linkFantasyTipRound(runde.id, ligaId);
      ref.invalidate(fantasyTipRoundProvider(ligaId));
      ref.invalidate(myRoundsProvider);
    } catch (_) {
      // Die Liga ist angelegt; das Tippspiel bleibt eingeschaltet und wird
      // auf der Übersicht angeboten.
    }
  }

  String? _pruefeName() => _name.text.trim().length < 3
      ? 'Bitte einen Namen mit mind. 3 Zeichen wählen.'
      : null;

  String? _pruefeDraft() => _limitsTragenDenKader
      ? null
      : 'Die Kader-Limits ergeben zusammen weniger Plätze, als der Kader hat.';

  String? _pruefeSaison() => _plan.isValid
      ? null
      : 'So passen die Playoffs nicht in die Saison — weniger Teams oder '
            'kürzere Partien wählen.';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final oeffentlich = _visibility == 'public';
    const wertStil = TextStyle(
      fontSize: Schrift.text,
      fontWeight: FontWeight.w800,
    );
    final stufen = DraftPickTime.values;
    final stufe = stufen.indexOf(_pickTime);
    final plan = _plan;
    final roster = _rosterMitLimits;

    // **Jede Einstellung ist dieselbe Zeile** (18.10.2026): Bezeichnung
    // links in Textgröße, Bedienung rechts, höchstens eine kurze Zeile
    // darunter. Seit dem 29.10.2026 auf vier Seiten statt zugeklappt.
    return SchrittFormular(
      titel: 'Fantasy-Liga erstellen',
      abschluss: 'Liga erstellen',
      busy: _busy,
      fehler: _error,
      onAbschluss: _create,
      // Was ist eine Fantasy-Liga? — als Fragezeichen (Punkt 3).
      aktionen: [
        InfoKnopf(
          titel: erklaerungFantasy.titel,
          text: erklaerungFantasy.text,
          frage: true,
          groesse: 22,
        ),
        const SizedBox(width: 4),
      ],
      schritte: [
        Schritt(
          titel: 'Liga',
          pruefe: _pruefeName,
          inhalt: [
            FormSection(
              titel: 'Name und Teams',
              kinder: [
                Padding(
                  // **Ein Feld, das man als Feld erkennt** (30.10.2026, auf
                  // Ansage): eigener Rahmen und Beschriftung statt eines
                  // grauen Beispieltexts auf der Fläche.
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: TextField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    style: einstellungsStil,
                    decoration: const InputDecoration(
                      labelText: 'Name der Liga',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const EinstellungsTrenner(),
                EinstellungsZeile(
                  label: 'Teams',
                  unter: 'So viele Mitspieler passen in die Liga',
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
          ],
        ),
        Schritt(
          titel: 'Draft',
          pruefe: _pruefeDraft,
          inhalt: [
            // Punkt 9: Der Draft ist kein Termin — der Satz zieht mit der
            // Zeit je Pick mit.
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Text(
                _pickTime.ablaufSatz,
                style: TextStyle(
                  fontSize: Schrift.text,
                  height: 1.35,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            FormSection(
              titel: 'Draft',
              erklaerung: erklaerungDraft,
              kinder: [
                EinstellungsZeile(
                  label: 'Zeit je Pick',
                  unter: _pickTime.ablauf,
                  rechts: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Zeit je Pick verringern',
                        visualDensity: VisualDensity.compact,
                        onPressed: stufe > 0
                            ? () =>
                                  setState(() => _pickTime = stufen[stufe - 1])
                            : null,
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      SizedBox(
                        width: 92,
                        child: Text(
                          _pickTime.label,
                          textAlign: TextAlign.center,
                          style: wertStil,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Zeit je Pick erhöhen',
                        visualDensity: VisualDensity.compact,
                        onPressed: stufe < stufen.length - 1
                            ? () =>
                                  setState(() => _pickTime = stufen[stufe + 1])
                            : null,
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                ),
                const EinstellungsTrenner(),
                EinstellungsZeile(
                  label: 'Runden',
                  unter: '11 Startelf + ${_runden - 11} Bank',
                  rechts: WertStepper(
                    label: 'Runden',
                    value: _runden,
                    min: _minRunden,
                    max: _maxRunden,
                    onChanged: (v) => setState(() => _runden = v),
                  ),
                ),
                const EinstellungsTrenner(),
                EinstellungsZeile(
                  label: 'Reihenfolge',
                  unter: _reihenfolge == 'manual'
                      ? 'Legst du vor dem Start fest'
                      : 'Wird beim Start ausgelost',
                  rechts: SizedBox(
                    width: 190,
                    child: PillSelector<String>(
                      options: const {'auto': 'Zufällig', 'manual': 'Manuell'},
                      value: _reihenfolge,
                      onSelect: (v) => setState(() => _reihenfolge = v),
                    ),
                  ),
                ),
              ],
            ),
            FormSection(
              titel: 'Kader-Limits',
              erklaerung: erklaerungKaderLimits,
              kinder: [
                KaderLimitsEditor(
                  roster: roster,
                  limits: _limits,
                  onChanged: (neu) => setState(() {
                    _limits
                      ..clear()
                      ..addAll(neu);
                  }),
                ),
                if (!_limitsTragenDenKader)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 4),
                    child: Text(
                      KaderLimitsEditor.hinweisText(roster, _limits),
                      style: TextStyle(
                        fontSize: Schrift.label,
                        color: scheme.error,
                      ),
                    ),
                  ),
              ],
            ),
            FormSection(
              titel: 'Vereins-Limit',
              erklaerung: erklaerungVereinsLimit,
              kinder: [
                VereinsLimitEditor(
                  wert: _vereinsLimit,
                  onChanged: (v) => setState(() => _vereinsLimit = v),
                ),
              ],
            ),
          ],
        ),
        Schritt(
          titel: 'Saison',
          pruefe: _pruefeSaison,
          inhalt: [
            FormSection(
              titel: 'Unentschieden',
              erklaerung: erklaerungUnentschieden,
              kinder: [
                RemisGrenzeEditor(
                  wert: _remisGrenze,
                  onChanged: (v) => setState(() => _remisGrenze = v),
                ),
              ],
            ),
            FormSection(
              titel: 'Playoffs',
              erklaerung: erklaerungPlayoffs,
              kinder: [
                EinstellungsZeile(
                  label: 'Playoff-Teams',
                  unter: plan.isValid
                      ? 'Ab Spieltag ${plan.startRound}'
                            '${plan.topSeedBye ? ' · Platz 1 hat ein Freilos' : ''}'
                      : 'Passt so nicht in die Saison',
                  rechts: WertStepper(
                    label: 'Playoff-Teams',
                    value: _playoffTeams,
                    min: 4,
                    max: 8,
                    onChanged: (v) => setState(() => _playoffTeams = v),
                  ),
                ),
                const EinstellungsTrenner(),
                EinstellungsZeile(
                  label: 'Partie-Dauer',
                  rechts: SizedBox(
                    width: 220,
                    child: PillSelector<int>(
                      options: const {1: '1 Woche', 2: '2 Wochen'},
                      value: _playoffWochen,
                      onSelect: (v) => setState(() => _playoffWochen = v),
                    ),
                  ),
                ),
                const EinstellungsTrenner(),
                EinstellungsZeile(
                  label: 'Trade-Deadline',
                  unter: plan.isValid
                      ? 'Spieltag ${plan.tradeDeadlineRound} · '
                            '$_tradeDeadline vor den Playoffs'
                      : 'Spieltage vor den Playoffs',
                  rechts: WertStepper(
                    label: 'Trade-Deadline',
                    value: _tradeDeadline,
                    min: 5,
                    max: 10,
                    onChanged: (v) => setState(() => _tradeDeadline = v),
                  ),
                ),
              ],
            ),
            FormSection(
              titel: 'Winterpause',
              erklaerung: erklaerungWinterpause,
              kinder: [
                EinstellungsSchalter(
                  label: 'Reset',
                  unter: 'Am 24.12. neuer Draft, die Tabelle bleibt',
                  wert: _resetAktiv,
                  onChanged: (v) => setState(() => _resetAktiv = v),
                ),
              ],
            ),
          ],
        ),
        Schritt(
          titel: 'Mitspieler & Tippspiel',
          inhalt: [
            FormSection(
              titel: 'Sichtbarkeit',
              erklaerung: erklaerungSichtbarkeit,
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
              titel: 'Tippspiel',
              erklaerung: erklaerungLigaTippspiel,
              kinder: [
                EinstellungsSchalter(
                  label: 'Ligainternes Tippspiel',
                  unter: 'Mit denselben Mitgliedern',
                  wert: _tipEnabled,
                  onChanged: (v) => setState(() => _tipEnabled = v),
                ),
              ],
            ),
            if (_tipEnabled) ...[
              FormSection(
                titel: 'Wettbewerbe',
                kinder: [
                  CompetitionPicker(
                    leagues: Leagues.tippspiel,
                    selected: _tipLigen,
                    onToggle: (id) => setState(() {
                      if (!_tipLigen.remove(id)) {
                        _tipLigen.add(id);
                      } else if (_tipLigen.isEmpty) {
                        _tipLigen.add(id); // mindestens einer
                      }
                    }),
                  ),
                ],
              ),
              TipRulesEditor(
                initial: _tipRegeln,
                oddsAvailable: _tipWettbewerbe.any(
                  (l) => l.oddsSportKey != null,
                ),
                onChanged: (r) => setState(() => _tipRegeln = r),
              ),
            ],
          ],
        ),
      ],
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
