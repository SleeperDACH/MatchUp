import '../../../app/erklaerungen.dart';
import 'package:flutter/material.dart';

import '../../../app/typografie.dart';
import '../../../core/ui/einstellungs_zeile.dart';
import '../../../core/ui/form_section.dart';
import '../../../core/ui/wert_stepper.dart';
import '../models/tip.dart';

/// Wiederverwendbares Formular für Basiswertung + kombinierbare Modi einer
/// Tipprunde. Genutzt beim Erstellen und in den Liga-Einstellungen. Meldet
/// jede Änderung als komplette [ScoringRules] über [onChanged]; Name und
/// Wettbewerb liegen bewusst außerhalb (die sind nicht Teil der Wertung).
/// Welcher Teil gezeigt wird — beim Anlegen in Schritten stehen Punkte und
/// Modi auf verschiedenen Seiten (29.10.2026).
enum TipRulesTeil { alles, punkte, modi }

class TipRulesEditor extends StatefulWidget {
  const TipRulesEditor({
    super.key,
    required this.initial,
    required this.onChanged,
    this.lockedBonusTips = const {},
    this.oddsAvailable = true,
    this.teil = TipRulesTeil.alles,
  });

  /// Nur Punkte, nur Modi oder beides. Zwei Editoren für dieselben Regeln
  /// (je ein Teil) bleiben gleich, weil jeder ein neues [initial] übernimmt
  /// (`didUpdateWidget`) — sonst schriebe der eine die Werte des anderen mit
  /// seinem alten Stand zurück.
  final TipRulesTeil teil;

  final ScoringRules initial;
  final ValueChanged<ScoringRules> onChanged;

  /// Ob für die gewählten Wettbewerbe überhaupt Quoten existieren. Beim
  /// DFB-Pokal (keine Quoten) wird der Quoten-Bonus ausgeblendet.
  final bool oddsAvailable;

  /// Bereits aktive Bonustipps, die nicht mehr entfernt werden dürfen (nur
  /// hinzufügen). Beim Erstellen leer; in den Liga-Einstellungen die schon
  /// gewählten Fragen.
  final Set<String> lockedBonusTips;

  @override
  State<TipRulesEditor> createState() => _TipRulesEditorState();
}

class _TipRulesEditorState extends State<TipRulesEditor> {
  late int _exact = widget.initial.exact;
  late int _goalDiff = widget.initial.goalDiff;
  late int _tendency = widget.initial.tendency;
  late int _wrongTip = widget.initial.wrongTip;

  late bool _oddsBonus = widget.initial.oddsBonus;
  late double _odds1 = widget.initial.oddsOdds1;
  late int _points1 = widget.initial.oddsPoints1;
  late double _odds2 = widget.initial.oddsOdds2;
  late int _points2 = widget.initial.oddsPoints2;

  late bool _solo = widget.initial.solo > 0;
  // Punkte des Alleinstellungs-Bonus (Bestand erhalten, sonst Standard 3).
  late final int _soloValue = widget.initial.solo > 0 ? widget.initial.solo : 3;

  late bool _headToHead = widget.initial.headToHead;

  late bool _bonusTips = widget.initial.bonusTips.isNotEmpty;
  late final Set<String> _bonusTipKeys = widget.initial.bonusTips.isNotEmpty
      ? {...widget.initial.bonusTips}
      : {for (final o in bonusTipQuestions) o.$1};
  late int _bonusPoints = widget.initial.bonusPoints;

  ScoringRules get _rules => ScoringRules(
    exact: _exact,
    goalDiff: _goalDiff,
    tendency: _tendency,
    wrongTip: _wrongTip,
    oddsBonus: _oddsBonus,
    oddsOdds1: _odds1,
    oddsPoints1: _points1,
    oddsOdds2: _odds2,
    oddsPoints2: _points2,
    solo: _solo ? _soloValue : 0,
    headToHead: _headToHead,
    bonusTips: _bonusTips
        ? [
            for (final o in bonusTipQuestions)
              if (_bonusTipKeys.contains(o.$1)) o.$1,
          ]
        : const [],
    bonusPoints: _bonusPoints,
  );

  @override
  void didUpdateWidget(TipRulesEditor alt) {
    super.didUpdateWidget(alt);
    if (identical(alt.initial, widget.initial)) return;
    final r = widget.initial;
    _exact = r.exact;
    _goalDiff = r.goalDiff;
    _tendency = r.tendency;
    _wrongTip = r.wrongTip;
    _oddsBonus = r.oddsBonus;
    _odds1 = r.oddsOdds1;
    _points1 = r.oddsPoints1;
    _odds2 = r.oddsOdds2;
    _points2 = r.oddsPoints2;
    _solo = r.solo > 0;
    _headToHead = r.headToHead;
    _bonusTips = r.bonusTips.isNotEmpty;
    if (r.bonusTips.isNotEmpty) {
      _bonusTipKeys
        ..clear()
        ..addAll(r.bonusTips);
    }
    _bonusPoints = r.bonusPoints;
  }

  /// setState + Änderung nach oben melden.
  void _set(VoidCallback change) {
    setState(change);
    widget.onChanged(_rules);
  }

  @override
  Widget build(BuildContext context) {
    // **Dieselben Zeilen wie überall** (18.10.2026, auf Ansage „fürs
    // Tippspiel gilt das gleiche"): Vorher trug jeder Modus eine eigene
    // Kachel mit Symbol und grünem Hauch, Quoten und Bonustipps lagen in
    // grauen Kästen darunter, und vier Abschnitte erklärten sich in Sätzen.
    // Jetzt eine Zeile je Wert, Untereinstellungen als weitere Zeilen direkt
    // unter ihrem Schalter.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.teil != TipRulesTeil.modi)
          FormSection(
            titel: 'Punkte je Tipp',
            erklaerung: erklaerungPunkteJeTipp,
            kinder: [
              _punkte('Exaktes Ergebnis', _exact, (v) => _exact = v),
              const EinstellungsTrenner(),
              _punkte('Tordifferenz', _goalDiff, (v) => _goalDiff = v),
              const EinstellungsTrenner(),
              _punkte('Tendenz', _tendency, (v) => _tendency = v),
              const EinstellungsTrenner(),
              _punkte(
                'Falscher Tipp',
                _wrongTip,
                (v) => _wrongTip = v,
                min: -5,
                max: 0,
              ),
            ],
          ),
        if (widget.teil != TipRulesTeil.punkte)
          FormSection(
            titel: 'Modi',
            erklaerung: erklaerungModi,
            kinder: [
              // Quoten-Bonus nur, wenn die gewählten Wettbewerbe Quoten haben
              // (DFB-Pokal: keine Quoten → Modus ausgeblendet).
              if (widget.oddsAvailable) ...[
                EinstellungsSchalter(
                  label: 'Quoten-Bonus',
                  unter: 'Extrapunkte für Außenseiter',
                  wert: _oddsBonus,
                  onChanged: (v) => _set(() => _oddsBonus = v),
                ),
                if (_oddsBonus) ..._quotenZeilen(),
                const EinstellungsTrenner(),
              ],
              EinstellungsSchalter(
                label: 'Alleinstellungs-Bonus',
                unter: '+$_soloValue für den einzigen exakten Tipp',
                wert: _solo,
                onChanged: (v) => _set(() => _solo = v),
              ),
              const EinstellungsTrenner(),
              EinstellungsSchalter(
                label: 'Head-to-Head',
                unter: 'Jeder Spieltag ein Duell',
                wert: _headToHead,
                onChanged: (v) => _set(() => _headToHead = v),
              ),
              const EinstellungsTrenner(),
              EinstellungsSchalter(
                label: 'Bonustipps',
                unter: widget.lockedBonusTips.isEmpty
                    ? 'Saison-Prognosen'
                    : 'Aktiv — weitere lassen sich ergänzen',
                wert: _bonusTips,
                // Wenn schon Bonustipps aktiv sind, lässt sich der Modus nicht
                // mehr abschalten (nur hinzufügen).
                onChanged: widget.lockedBonusTips.isEmpty
                    ? (v) => _set(() => _bonusTips = v)
                    : null,
              ),
              if (_bonusTips) ..._bonusTippZeilen(),
            ],
          ),
      ],
    );
  }

  Widget _punkte(
    String label,
    int wert,
    void Function(int) setze, {
    int min = 0,
    int max = 20,
  }) => EinstellungsZeile(
    label: label,
    rechts: WertStepper(
      label: label,
      value: wert,
      min: min,
      max: max,
      onChanged: (v) => _set(() => setze(v)),
    ),
  );

  /// Die zwei Stufen des Quoten-Bonus — vier Zeilen statt eines Kastens.
  List<Widget> _quotenZeilen() => [
    const EinstellungsTrenner(),
    EinstellungsZeile(
      label: 'Außenseiter ab Quote',
      rechts: _QuotenStepper(
        label: 'Außenseiter ab Quote',
        value: _odds1,
        onChanged: (v) => _set(() => _odds1 = v),
      ),
    ),
    _punkte('Außenseiter: Punkte', _points1, (v) => _points1 = v),
    const EinstellungsTrenner(),
    EinstellungsZeile(
      label: 'Krasser Außenseiter ab Quote',
      rechts: _QuotenStepper(
        label: 'Krasser Außenseiter ab Quote',
        value: _odds2,
        onChanged: (v) => _set(() => _odds2 = v),
      ),
    ),
    _punkte('Krasser Außenseiter: Punkte', _points2, (v) => _points2 = v),
  ];

  /// Die enthaltenen Bonustipps und ihre Punkte — als Zeilen unter dem
  /// Schalter, nicht in einem eigenen Kasten.
  List<Widget> _bonusTippZeilen() => [
    for (final (key, label, maxTeams) in bonusTipQuestions) ...[
      const EinstellungsTrenner(),
      Builder(
        builder: (context) {
          final locked = widget.lockedBonusTips.contains(key);
          return CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _bonusTipKeys.contains(key),
            // Bereits aktive Bonustipps bleiben gesetzt und lassen sich
            // nicht mehr entfernen.
            onChanged: locked
                ? null
                : (v) => _set(() {
                    if (v == true) {
                      _bonusTipKeys.add(key);
                    } else {
                      _bonusTipKeys.remove(key);
                    }
                  }),
            title: Text(label, style: einstellungsStil),
            subtitle: locked
                ? const Text('bereits aktiv')
                : (maxTeams > 1 ? Text('$maxTeams Teams') : null),
          );
        },
      ),
    ],
    const EinstellungsTrenner(),
    _punkte('Punkte je Bonustipp', _bonusPoints, (v) => _bonusPoints = v),
  ];
}

/// +/− für eine Quote (1,5–10,0 in 0,5-Schritten) — gleich gebaut wie
/// `WertStepper`, nur mit Kommazahl.
class _QuotenStepper extends StatelessWidget {
  const _QuotenStepper({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    // Mit Komma, nicht mit Punkt: „2.5" spräche die Vorlesehilfe als „zwei
    // Punkt fünf" aus — und im Bild ist es dieselbe Schreibweise.
    final text = value.toStringAsFixed(1).replaceAll('.', ',');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: '$label verringern',
          visualDensity: VisualDensity.compact,
          onPressed: value > 1.5 ? () => onChanged(value - 0.5) : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(
          width: 36,
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: Schrift.titel,
            ),
          ),
        ),
        IconButton(
          tooltip: '$label erhöhen',
          visualDensity: VisualDensity.compact,
          onPressed: value < 10.0 ? () => onChanged(value + 0.5) : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }
}
