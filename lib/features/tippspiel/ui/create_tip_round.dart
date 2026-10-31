import '../../../core/ui/schritt_formular.dart';
import '../../../app/erklaerungen.dart';
import '../../../app/widgets/info_knopf.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/widgets/competition_picker.dart';
import '../../../core/ui/einstellungs_zeile.dart';
import '../../../core/ui/form_section.dart';

import '../../../app/league_screen.dart';
import '../../../core/models/models.dart';
import '../models/tip.dart';
import '../providers.dart';
import 'tip_rules_editor.dart';

/// Erstellen einer Tipprunde **in drei Schritten** (29.10.2026, auf Ansage):
/// Tippspiel (Name, Wettbewerbe) · Punkte · Extras (Modi, Sichtbarkeit),
/// zuletzt „Tipprunde erstellen". Dieselbe Form wie bei der Fantasy-Liga.
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

  List<LeagueInfo> get _selectedLeagues => [
    for (final l in Leagues.tippspiel)
      if (_leagueIds.contains(l.id)) l,
  ];

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
        MaterialPageRoute(builder: (_) => LeagueScreen(round: round)),
      );
    } catch (e) {
      setState(() => _error = 'Tipprunde konnte nicht erstellt werden: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _pruefeStart() {
    if (!_linked && _name.text.trim().length < 3) {
      return 'Bitte einen Namen mit mind. 3 Zeichen wählen.';
    }
    if (_selectedLeagues.isEmpty) {
      return 'Bitte mindestens einen Wettbewerb wählen.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final oeffentlich = _visibility == 'public';
    // Quoten-Modi nur, wenn ein Wettbewerb mit Quoten dabei ist
    // (Bundesliga/2. Bundesliga); DFB-Pokal hat keine Quoten.
    final quoten = _selectedLeagues.any((l) => l.oddsSportKey != null);
    return SchrittFormular(
      titel: _linked ? 'Ligainternes Tippspiel' : 'Tippspiel erstellen',
      abschluss: _linked ? 'Tippspiel aktivieren' : 'Tipprunde erstellen',
      busy: _busy,
      fehler: _error,
      onAbschluss: _create,
      aktionen: [
        InfoKnopf(
          titel: erklaerungTippspiel.titel,
          text: erklaerungTippspiel.text,
          frage: true,
          groesse: 22,
        ),
        const SizedBox(width: 4),
      ],
      schritte: [
        Schritt(
          titel: 'Tippspiel',
          pruefe: _pruefeStart,
          inhalt: [
            // Ligainternes Tippspiel übernimmt den Liga-Namen.
            if (!_linked)
              FormSection(
                titel: 'Name',
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
                        labelText: 'Name des Tippspiels',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            FormSection(
              titel: 'Wettbewerbe',
              kinder: [
                CompetitionPicker(
                  leagues: Leagues.tippspiel,
                  selected: _leagueIds,
                  onToggle: (id) => setState(() {
                    if (!_leagueIds.remove(id)) {
                      _leagueIds.add(id);
                    } else if (_leagueIds.isEmpty) {
                      // Mindestens einer muss bleiben.
                      _leagueIds.add(id);
                    }
                  }),
                ),
              ],
            ),
          ],
        ),
        Schritt(
          titel: 'Punkte',
          inhalt: [
            TipRulesEditor(
              teil: TipRulesTeil.punkte,
              initial: _rules,
              oddsAvailable: quoten,
              onChanged: (r) => setState(() => _rules = r),
            ),
          ],
        ),
        Schritt(
          titel: 'Extras',
          inhalt: [
            TipRulesEditor(
              teil: TipRulesTeil.modi,
              initial: _rules,
              oddsAvailable: quoten,
              onChanged: (r) => setState(() => _rules = r),
            ),
            if (!_linked)
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
              )
            else
              const FormSection(
                titel: 'Mitglieder',
                kinder: [
                  EinstellungsZeile(
                    label: 'Alle Mitglieder der Fantasy-Liga',
                    rechts: SizedBox.shrink(),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}
