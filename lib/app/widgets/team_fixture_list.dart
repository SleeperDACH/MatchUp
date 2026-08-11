import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/models/models.dart';
import '../../core/models/team_fixture.dart';
import '../../features/tippspiel/ui/team_badge.dart';
import '../match_detail_screen.dart';
import '../theme.dart';
import 'league_logo.dart';

/// Gemeinsame Darstellung eines Team-Spielplans: Datums-Überschriften und
/// Spiel-Boxen mit Wettbewerbslogo, Spieltag, beiden Wappen und Ergebnis.
///
/// Liegt hier und nicht im Favoriten-Tab, weil die Vereinsseite dieselbe
/// Darstellung benutzt. Zwei Kopien wären beim nächsten Feinschliff sofort
/// wieder auseinandergelaufen.

/// Fügt vor jedem neuen Kalendertag eine Datums-Überschrift ein (Datum steht
/// damit außerhalb der Spiel-Box, wie im Live-Tab).
List<Widget> fixturesWithDateHeaders(List<TeamFixture> list) {
  final out = <Widget>[];
  DateTime? lastDay;
  for (final f in list) {
    final lt = f.kickoff.toLocal();
    final day = DateTime(lt.year, lt.month, lt.day);
    if (lastDay == null || lastDay != day) {
      out.add(FixtureDateHeader(date: day));
      lastDay = day;
    }
    out.add(TeamFixtureCard(fixture: f));
  }
  return out;
}


/// Datums-Überschrift zwischen den Spiel-Boxen (z. B. „Samstag, 23.08.").
class FixtureDateHeader extends StatelessWidget {
  const FixtureDateHeader({super.key, required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = DateFormat('EEEE, dd.MM.', 'de_DE').format(date);
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 14, 6, 4),
      child: Text(
        label[0].toUpperCase() + label.substring(1),
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.bold, color: scheme.onSurfaceVariant),
      ),
    );
  }
}


class FixtureSectionLabel extends StatelessWidget {
  const FixtureSectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
      child: Text(text,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
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


class TeamFixtureCard extends StatelessWidget {
  const TeamFixtureCard({super.key, required this.fixture});
  final TeamFixture fixture;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final f = fixture;
    final live = f.status == FixtureStatus.live;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => MatchDetailScreen(fixtureId: f.id))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            // Wettbewerbslogo (DFB-Pokal freigestellt) und – auf gleicher Höhe –
            // der Spieltag bzw. die Pokalrunde.
            Row(
              children: [
                LeagueLogo(
                  logoUrl: f.leagueLogo,
                  name: f.leagueName,
                  size: 26,
                  fallback: Text(f.leagueName,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.bold)),
                ),
                const Spacer(),
                if (matchdayLabel(f) != null)
                  Text(matchdayLabel(f)!,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 44,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    // Name außen, Logo innen (zur Mitte) → Wappen fluchten.
                    child: Row(children: [
                      Expanded(
                        child: Text(f.home.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15)),
                      ),
                      const SizedBox(width: 8),
                      TeamBadge(team: f.home, size: 22),
                    ]),
                  ),
                  // Mitte: Uhrzeit (bzw. Ergebnis) mittig — das Datum steht als
                  // Überschrift außerhalb der Box.
                  SizedBox(
                    width: 62,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (f.hasScore)
                          Text('${f.homeScore}:${f.awayScore}',
                              style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: live
                                      ? MatchUpColors.red
                                      : scheme.onSurface))
                        else
                          Text(
                              DateFormat('HH:mm').format(f.kickoff.toLocal()),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 22, fontWeight: FontWeight.bold)),
                        if (live)
                          const Text('● LIVE',
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: MatchUpColors.red)),
                      ],
                    ),
                  ),
                  Expanded(
                    // Logo innen (zur Mitte), Name außen → Wappen fluchten.
                    child: Row(children: [
                      TeamBadge(team: f.away, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(f.away.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: const TextStyle(fontSize: 15)),
                      ),
                    ]),
                  ),
                ],
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}

