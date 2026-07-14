import 'package:flutter/material.dart';

/// Übersichtliche Erläuterung der Fantasy-Punktevergabe (Voll-Advanced-Scoring
/// auf Basis der Sportmonks-Spielstatistiken). Rein informativ — die Werte
/// spiegeln scoring/config/scoring.config.json.
class ScoringInfoScreen extends StatelessWidget {
  const ScoringInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Punktevergabe')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
        children: [
          const _Intro(),
          _Section('Einsatz', const [
            _Row('1–29 Min', '+1'),
            _Row('30–59 Min', '+2'),
            _Row('60–89 Min', '+3'),
            _Row('90 Min (komplett)', '+5'),
          ]),
          _Section('Offensive (alle Positionen)', const [
            _Row('Tor', '+8'),
            _Row('Tor per Elfmeter', '+6'),
            _Row('Vorlage', '+6'),
            _Row('Großchance kreiert', '+3'),
            _Row('Key Pass', '+0,75'),
            _Row('Schuss aufs Tor', '+1'),
            _Row('Erfolgreiches Dribbling', '+0,5'),
          ]),
          _Section('Defensive', const [
            _Row('Zu Null (≥60 Min, 0 GT)', 'TW +6 · ABW +6'),
            _Row('Gegentor (je, auf dem Platz)', 'TW −1 · ABW −0,5'),
            _Row('Parade (nur TW)', '+1,5'),
            _Row('Gehaltener Elfmeter (nur TW)', '+6'),
            _Row('Tackling gewonnen', '+0,5'),
            _Row('Balleroberung', '+0,5'),
            _Row('Klärung', '+0,2'),
            _Row('Geblockter Schuss', '+0,5'),
          ]),
          _Section('Meilenstein-Boni (kumulativ, pro Spiel)', const [
            _Row('Paraden (TW): ≥5', '+4'),
            _Row('Paraden (TW): ≥8', '+6 zusätzlich (ges. +10)'),
            _Row('Def-Aktionen TW/ABW: ≥9 / ≥14 / ≥19', 'je +3 (max +9)'),
            _Row('Def-Aktionen MIT: ≥10 / ≥14', 'je +3 (max +6)'),
            _Row('Def-Aktionen ANG: ≥8 / ≥12', 'je +3 (max +6)'),
          ], footnote: 'Def-Aktionen = Tacklings + Balleroberungen + Klärungen + Blocks'),
          _Section('Negativ (alle Positionen)', const [
            _Row('Gelbe Karte', '−2'),
            _Row('Gelb-Rot (zusätzlich)', '−3'),
            _Row('Rote Karte (direkt)', '−5'),
            _Row('Eigentor', '−6'),
            _Row('Verschossener Elfmeter', '−4'),
            _Row('Fehler vor Gegentor', '−3'),
            _Row('Großchance vergeben', '−2'),
            _Row('Abseits', '−0,5'),
            _Row('Foul', '−0,2'),
            _Row('Ballverlust', '−0,2'),
          ]),
          _Section('Match-Rating-Bonus (Sportmonks 0–10)', const [
            _Row('≥ 9,0', '+5'),
            _Row('8,0 – 8,99', '+3'),
            _Row('7,0 – 7,99', '+1,5'),
            _Row('6,0 – 6,99', '0'),
            _Row('5,0 – 5,99', '−1,5'),
            _Row('< 5,0', '−3'),
          ]),
        ],
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        'Jede Aktion zählt flat (immer gleicher Wert, keine Degression, keine '
        'Caps). Die Punkte je Spieler und Spiel ergeben sich aus den echten '
        'Spielstatistiken. Positionen: TW (Torwart), ABW (Abwehr), '
        'MIT (Mittelfeld), ANG (Angriff).',
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.rows, {this.footnote});

  final String title;
  final List<_Row> rows;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 16,
                  decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(width: 8),
                Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(children: rows),
          ),
          if (footnote != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
              child: Text(footnote!,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic)),
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final negative = value.contains('−');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13.5))),
          const SizedBox(width: 10),
          Text(value,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.bold,
                color: negative ? scheme.error : scheme.primary,
              )),
        ],
      ),
    );
  }
}
