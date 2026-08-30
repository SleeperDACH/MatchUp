import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/pill_selector.dart';
import '../logic/fantasy_scoring_engine.dart';
import '../logic/fantasy_scoring_rules.dart';
import '../models/fantasy_models.dart';

/// Erläuterung der Fantasy-Punktevergabe — **nach Position sortiert.**
///
/// Vorher stand die Seite nach Kategorien: „Defensive", „Meilenstein-Boni",
/// und die Position steckte in der Wertespalte („TW +12 · ABW +12",
/// „Def-Aktionen MIT: ≥10 / ≥14"). Wer wissen wollte, wofür sein Stürmer
/// Punkte bekommt, musste sechs Abschnitte lesen und dabei die Kürzel im Kopf
/// filtern. Jetzt wählt man oben die Position und sieht **nur**, was für sie
/// gilt: Ein Stürmer bekommt keine Zeile über Zu-Null-Prämien mehr zu sehen.
///
/// **Die Zahlen kommen aus [FantasyScoringRules], nicht aus dem Text.** Vorher
/// standen sie als Zeichenketten hier („+16"); eine Änderung an der Wertung
/// hätte die Erklärung stillschweigend zur Lüge gemacht. Das ist dieselbe
/// Doppelung, die bei `tip_scoring.dart` und der SQL-View eine ausdrückliche
/// Warnung in CLAUDE.md hat — hier ließ sie sich vermeiden.
class ScoringInfoScreen extends StatefulWidget {
  const ScoringInfoScreen({super.key});

  @override
  State<ScoringInfoScreen> createState() => _ScoringInfoScreenState();
}

class _ScoringInfoScreenState extends State<ScoringInfoScreen> {
  static const _regeln = FantasyScoringRules();
  PlayerPosition _position = PlayerPosition.gk;

  /// Farbe je Position — dieselbe Gliederung durch Farbe wie in den
  /// Einstellungen: Sie trennt die Bereiche, statt zu schmücken.
  Color _farbe(PlayerPosition p) => switch (p) {
    PlayerPosition.gk => const Color(0xFFFFC83D),
    PlayerPosition.def => const Color(0xFF5B9DF9),
    PlayerPosition.mid => const Color(0xFF4FC3A1),
    PlayerPosition.fwd => MatchUpColors.red,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = _position;
    final farbe = _farbe(p);

    return Scaffold(
      appBar: AppBar(title: const Text('Punktevergabe')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: PillSelector<PlayerPosition>(
              options: {
                for (final e in PlayerPosition.values) e: _positionsName(e),
              },
              value: p,
              onSelect: (v) => setState(() => _position = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              _einleitung(p),
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
              children: [
                _Gruppe('Einsatz', farbe, [
                  for (final t in _regeln.appearance.reversed)
                    _Zeile(_einsatzText(t), t.points),
                ]),
                _Gruppe('Offensive', farbe, [
                  _Zeile('Tor', _regeln.goal),
                  _Zeile('Tor per Elfmeter', _regeln.penaltyGoal),
                  _Zeile('Vorlage', _regeln.assist),
                  _Zeile('Großchance herausgespielt', _regeln.bigChanceCreated),
                  _Zeile('Torschussvorlage', _regeln.keyPass),
                  _Zeile('Schuss aufs Tor', _regeln.shotOnTarget),
                  _Zeile('Erfolgreiches Dribbling', _regeln.successfulDribble),
                ]),
                _Gruppe('Defensive', farbe, [
                  // Nur zeigen, was für diese Position auch zählt — eine Zeile
                  // mit „0" ist keine Auskunft, sondern eine Falle.
                  if (_regeln.cleanSheet.of(p) != 0)
                    _Zeile(
                      'Zu Null (mindestens '
                      '${_regeln.cleanSheetMinMinutes} Minuten gespielt)',
                      _regeln.cleanSheet.of(p),
                    ),
                  if (_regeln.goalConceded.of(p) != 0)
                    _Zeile(
                      'Gegentor, während er auf dem Platz steht',
                      _regeln.goalConceded.of(p),
                    ),
                  if (p == PlayerPosition.gk) ...[
                    _Zeile('Parade', _regeln.save),
                    _Zeile('Gehaltener Elfmeter', _regeln.penaltySaved),
                  ],
                  _Zeile('Gewonnener Zweikampf', _regeln.tackleWon.of(p)),
                  _Zeile('Abgefangener Ball', _regeln.interception.of(p)),
                  _Zeile('Balleroberung', _regeln.ballRecovery.of(p)),
                  _Zeile('Klärung', _regeln.clearance.of(p)),
                  _Zeile('Geblockter Schuss', _regeln.blockedShot.of(p)),
                ]),
                _Gruppe(
                  'Boni für viele Aktionen',
                  farbe,
                  [
                    if (p == PlayerPosition.gk)
                      for (final m in _regeln.saveMilestones)
                        _Zeile('Ab ${m.atLeast} Paraden im Spiel', m.bonus),
                    for (final m
                        in _regeln.defensiveMilestones[p] ?? const <Milestone>[])
                      _Zeile(
                        'Ab ${m.atLeast} Defensivaktionen im Spiel',
                        m.bonus,
                      ),
                    for (final m
                        in _regeln.passMilestones[p] ?? const <Milestone>[])
                      _Zeile('Ab ${m.atLeast} genauen Pässen im Spiel', m.bonus),
                  ],
                  fussnote:
                      'Die Boni zählen zusammen: Wer die zweite Schwelle '
                      'erreicht, hat den ersten Bonus schon bekommen. '
                      'Defensivaktionen sind Zweikämpfe, abgefangene Bälle, '
                      'Klärungen und geblockte Schüsse zusammengezählt — '
                      'Balleroberungen zählen einzeln, nicht hier mit. Die '
                      'Pass-Schwellen liegen je Position anders — ein Stürmer '
                      'kommt selten über zwanzig genaue Pässe, ein '
                      'Verteidiger fast immer.',
                ),
                _Gruppe('Abzüge', farbe, [
                  _Zeile('Gelbe Karte', _regeln.yellowCard),
                  _Zeile('Gelb-Rot (zusätzlich)', _regeln.secondYellow),
                  _Zeile('Rote Karte', _regeln.redCard),
                  _Zeile('Eigentor', _regeln.ownGoal),
                  _Zeile('Verschossener Elfmeter', _regeln.penaltyMissed),
                  _Zeile('Fehler vor dem Gegentor', _regeln.errorLeadToGoal),
                  _Zeile('Großchance vergeben', _regeln.bigChanceMissed),
                  _Zeile('Abseits', _regeln.offside),
                  _Zeile('Foul', _regeln.foul),
                  _Zeile('Ballverlust', _regeln.possessionLost),
                ]),
                _Gruppe(
                  'Notenbonus',
                  farbe,
                  [
                    for (final (grenze, punkte) in _regeln.ratingTiers)
                      _Zeile(_noteText(grenze), punkte),
                  ],
                  fussnote:
                      'Die Note vergibt Sportmonks nach dem Spiel, von 0 bis '
                      '10. Sie fasst zusammen, was die Einzelwerte oben nicht '
                      'abbilden.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _positionsName(PlayerPosition p) => switch (p) {
    PlayerPosition.gk => 'Torwart',
    PlayerPosition.def => 'Abwehr',
    PlayerPosition.mid => 'Mittelfeld',
    PlayerPosition.fwd => 'Sturm',
  };

  /// Ein Satz, der die Eigenart der Position benennt — das, was man beim
  /// Durchblättern der Tabellen sonst selbst zusammenreimen muss.
  /// Ordnet ein, was die Tabelle darunter genau beziffert.
  ///
  /// **Keine Zahl in diesem Satz.** Sie stünde eine Zeile später noch einmal,
  /// dort aus den Regeln gerechnet — und liefe beim nächsten Balance-Patch
  /// auseinander („ab acht", während unten die Zehn steht). Auch keine
  /// Rangfolge („zählt am meisten"): Ein Tor bringt jeder Position mehr als
  /// die Null hinten. Was der Satz behauptet, kommt deshalb aus den Regeln.
  String _einleitung(PlayerPosition p) {
    final zuNull = _regeln.cleanSheet.of(p) != 0;
    final gegentor = _regeln.goalConceded.of(p) != 0;
    return switch (p) {
      PlayerPosition.gk =>
        'Der Torwart lebt von Paraden und einer Null hinten. Tore und '
            'Vorlagen zählen für ihn genauso viel wie für alle anderen — sie '
            'kommen nur selten vor.',
      PlayerPosition.def =>
        'Die Abwehr punktet über die Null hinten, und jedes Gegentor kostet. '
            'Zweikämpfe und Klärungen bringen dazu stetig kleine Punkte.',
      PlayerPosition.mid => zuNull
          ? 'Das Mittelfeld punktet über Tore, Vorlagen und Defensivarbeit.'
          : 'Das Mittelfeld bekommt nichts für die Null hinten'
                '${gegentor ? '' : ' und verliert nichts durch Gegentore'}. '
                'Punkte kommen aus Toren, Vorlagen und der Defensivarbeit.',
      PlayerPosition.fwd =>
        'Der Sturm lebt von Toren und Vorlagen. Die Null hinten spielt keine '
            'Rolle; Defensivarbeit zählt trotzdem mit.',
    };
  }

  /// „30–59 Minuten gespielt" statt „ab 30" — die Obergrenze steht nicht in
  /// den Regeln, sie ergibt sich aus der nächsthöheren Stufe.
  String _einsatzText(AppearanceTier t) {
    if (t.atLeastMinutes >= 90) return 'Volle 90 Minuten';
    final grenzen = [for (final a in _regeln.appearance) a.atLeastMinutes]
      ..sort();
    final naechste = grenzen
        .where((g) => g > t.atLeastMinutes)
        .cast<int?>()
        .firstOrNull;
    return naechste == null
        ? 'Ab ${t.atLeastMinutes} Minuten'
        : '${t.atLeastMinutes}–${naechste - 1} Minuten gespielt';
  }

  String _noteText(double grenze) =>
      grenze <= 0 ? 'Note unter 5,0' : 'Note ab ${formatPoints(grenze)},0';
}

/// Eine Gruppe der Punkteliste: Kapitelmarke in der Positionsfarbe, darunter
/// die Zeilen. Leere Gruppen fallen weg — für das Mittelfeld gibt es keine
/// Torwart-Boni, und eine leere Überschrift wäre eine offene Frage.
class _Gruppe extends StatelessWidget {
  const _Gruppe(this.titel, this.farbe, this.zeilen, {this.fussnote});

  final String titel;
  final Color farbe;
  final List<Widget> zeilen;
  final String? fussnote;

  @override
  Widget build(BuildContext context) {
    if (zeilen.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                  color: farbe,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 9),
              Text(
                titel.toUpperCase(),
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  height: 0.8,
                  color: scheme.onSurface.withValues(alpha: 0.12),
                ),
              ),
            ],
          ),
        ),
        for (var i = 0; i < zeilen.length; i++) ...[
          if (i > 0)
            Divider(
              height: 1,
              indent: 4,
              endIndent: 4,
              color: scheme.onSurface.withValues(alpha: 0.07),
            ),
          zeilen[i],
        ],
        if (fussnote != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
            child: Text(
              fussnote!,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
              ),
            ),
          ),
      ],
    );
  }
}

/// Eine Zeile: links wofür, rechts wie viel. Der Punktwert steht rechts und
/// in Tabellenziffern, damit die Spalte über alle Zeilen fluchtet — vorher
/// standen dort Zeichenketten wie „TW +12 · ABW +12", die nichts ausrichteten.
class _Zeile extends StatelessWidget {
  const _Zeile(this.was, this.punkte);

  final String was;
  final double punkte;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final positiv = punkte > 0;
    final text = '${positiv ? '+' : ''}${formatPoints(punkte)}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 11),
      child: Row(
        children: [
          Expanded(
            child: Text(
              was,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            text,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: punkte == 0
                  ? scheme.onSurfaceVariant
                  : (positiv ? MatchUpColors.green : MatchUpColors.red),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
