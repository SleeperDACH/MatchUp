import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/models/models.dart';
import '../../core/models/team_fixture.dart';
import '../../features/tippspiel/ui/team_badge.dart';
import '../match_detail_screen.dart';
import '../theme.dart';
import 'pulsing_dot.dart';

/// Gemeinsame Darstellung eines Team-Spielplans: Datums-Überschriften und
/// Spiel-Boxen mit Wettbewerbslogo, Spieltag, beiden Wappen und Ergebnis.
///
/// Liegt hier und nicht im Favoriten-Tab, weil die Vereinsseite dieselbe
/// Darstellung benutzt. Zwei Kopien wären beim nächsten Feinschliff sofort
/// wieder auseinandergelaufen.

/// Setzt vor jedes Spiel eine Zeile mit Datum, Wettbewerb und Spieltag —
/// darunter das Spiel selbst als schmale Zeile.
///
/// Vorher standen beide Angaben getrennt: die Datums-Überschrift **über** der
/// Box, Wettbewerb und Spieltag **in** ihr. Vier Spiele ergaben so acht
/// Blöcke, und der Kopf der Box wiederholte, was daneben ohnehin stand.
List<Widget> fixturesWithDateHeaders(List<TeamFixture> list) {
  final out = <Widget>[];
  DateTime? lastDay;
  for (var i = 0; i < list.length; i++) {
    final f = list[i];
    final lt = f.kickoff.toLocal();
    final day = DateTime(lt.year, lt.month, lt.day);
    if (i > 0 && (lastDay == null || lastDay != day)) {
      out.add(const _Trennlinie());
    } else if (i > 0) {
      out.add(const _Trennlinie());
    }
    out.add(FixtureDateHeader(date: day, fixture: f));
    lastDay = day;
    out.add(TeamFixtureCard(fixture: f));
  }
  return out;
}

/// Haarlinie zwischen zwei Spielen — die Liste kommt ohne Kästen aus.
class _Trennlinie extends StatelessWidget {
  const _Trennlinie();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Container(
      height: 0.8,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.07),
    ),
  );
}

/// Zeile über einem Spiel: Datum, Wettbewerb, Spieltag — alles, was **nicht**
/// die Partie ist, an einem Ort.
class FixtureDateHeader extends StatelessWidget {
  const FixtureDateHeader({super.key, required this.date, this.fixture});

  final DateTime date;

  /// Liefert Wettbewerb und Spieltag. Ohne Spiel bleibt es beim Datum.
  final TeamFixture? fixture;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = DateFormat('E, d. MMM', 'de_DE').format(date);
    final f = fixture;
    final zusatz = f == null
        ? null
        : [f.leagueName, ?matchdayLabel(f)].join(', ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            label[0].toUpperCase() + label.substring(1),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          if (zusatz != null) ...[
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                '· $zusatz',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}


class FixtureSectionLabel extends StatelessWidget {
  const FixtureSectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Dieselbe Kapitelmarke wie im Live-Tab: Wort, dann eine Haarlinie bis an
    // den Rand. Zwei Schirme, die dieselbe Liste zeigen, sollen sie auch
    // gleich gliedern.
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 2),
      child: Row(
        children: [
          Text(
            text.toUpperCase(),
            style: TextStyle(
              color: scheme.onSurfaceVariant,
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
    );
  }
}


/// Spieltag- bzw. Pokalrunden-Bezeichnung eines Team-Spiels (null = unbekannt).
String? matchdayLabel(TeamFixture f) {
  if (f.round <= 0) return null;
  final isCup = f.leagueName.toLowerCase().contains('pokal');
  if (isCup) {
    return switch (f.round) {
      1 => '1. Runde',
      2 => '2. Runde',
      3 => 'Achtelfinale',
      4 => 'Viertelfinale',
      5 => 'Halbfinale',
      6 => 'Finale',
      _ => 'Runde ${f.round}',
    };
  }
  return '${f.round}. Spieltag';
}


/// Ein Spiel des Team-Spielplans als **Zeile**, nicht als Karte.
///
/// Wappen an den Außenkanten, die Namen direkt daneben, Uhrzeit oder Ergebnis
/// in der Mitte — dieselbe Anordnung wie im Live-Tab. Vorher war es genau
/// andersherum (Wappen innen, Namen außen) und dazu eine gerahmte Box mit
/// eigener Kopfzeile für Wettbewerb und Spieltag; zwei Schirme, die dieselbe
/// Liste zeigen, fluchteten dadurch nicht miteinander. Was nicht die Partie
/// ist, steht jetzt in der Zeile darüber ([FixtureDateHeader]).
class TeamFixtureCard extends StatelessWidget {
  const TeamFixtureCard({super.key, required this.fixture});
  final TeamFixture fixture;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final f = fixture;
    final live = f.status == FixtureStatus.live;
    final finished = f.status == FixtureStatus.finished;

    return Material(
      color: live
          ? MatchUpColors.red.withValues(alpha: 0.07)
          : Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => MatchDetailScreen(fixtureId: f.id)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Row(
            children: [
              TeamBadge(team: f.home, size: 22),
              const SizedBox(width: 9),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    f.home.name,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 58,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (f.hasScore)
                      Text(
                        '${f.homeScore}:${f.awayScore}',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: live
                              ? MatchUpColors.red
                              : scheme.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      )
                    else
                      Text(
                        DateFormat('HH:mm').format(f.kickoff.toLocal()),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    if (finished)
                      Text(
                        'beendet',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    f.away.name,
                    maxLines: 1,
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              TeamBadge(team: f.away, size: 22),
              SizedBox(
                width: 13,
                child: live
                    ? const Align(
                        alignment: Alignment.centerRight,
                        child: PulsingDot(size: 7),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

