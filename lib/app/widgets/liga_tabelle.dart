import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/neu_laden.dart';
import '../../core/models/models.dart';
import '../../features/tippspiel/providers.dart';
import '../../features/tippspiel/ui/team_badge.dart';
import '../theme.dart';
import 'tabellen_punkte.dart';

/// **Die Ligatabelle — einmal gebaut, überall dieselbe.**
///
/// Sie stand als privates Widget in der Vereinsseite. Als das Spielerprofil
/// sie ebenfalls zeigen sollte (Ansage vom 19.09.2026: „Kann man im
/// Spielerprofil statt dem Kader bitte die Tabelle anzeigen?"), gab es zwei
/// Wege: kopieren oder teilen. Kopieren hieße, dieselbe Liste an zwei Stellen
/// zu pflegen — dieselbe Falle, die in dieser App schon dreimal zugeschnappt
/// ist (Spielplan, Bank, Zeitköpfe).
///
/// [eigenesTeam] wird hervorgehoben: In achtzehn Zeilen sucht man sonst.
class LigaTabelle extends ConsumerWidget {
  const LigaTabelle({
    super.key,
    required this.leagueId,
    required this.eigenesTeam,
  });

  final String leagueId;

  /// Team-ID in der Schreibweise der App (`sportmonks:<id>`); leer = keine
  /// Hervorhebung.
  final String eigenesTeam;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(liveLeagueTableProvider(leagueId));
    // Wer gerade spielt, trägt seine Punkte in Rot — die Tabelle rechnet
    // laufende Spiele ohnehin mit, sichtbar war es nicht.
    final laufend = laufendeTeams(
      ref.watch(leagueSeasonFixturesProvider(leagueId)).valueOrNull ?? const [],
    );
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Tabelle konnte nicht geladen werden.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => tabelleNeuLaden(ref, leagueId),
              child: const Text('Erneut laden'),
            ),
          ],
        ),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return Center(
            child: Text(
              'Noch keine Tabelle verfügbar.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () => neuLaden(() => tabelleNeuLaden(ref, leagueId)),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
            itemCount: rows.length,
            itemBuilder: (context, i) => TabellenZeile(
              row: rows[i],
              eigene: rows[i].team.id == eigenesTeam,
              live: laufend.contains(rows[i].team.id),
            ),
          ),
        );
      },
    );
  }
}

/// **Beide Quellen auffrischen, nicht nur die halbe.** Die Tabelle rechnet
/// live: Sie braucht die Standings **und** den Spielplan, aus dem die
/// laufenden Spiele überlagert werden.
void tabelleNeuLaden(WidgetRef ref, String leagueId) {
  ref.invalidate(leagueTableProvider(leagueId));
  ref.invalidate(leagueSeasonFixturesProvider(leagueId));
}

/// Eine Zeile der Tabelle: Platz, Wappen, Name, Spiele, Differenz, Punkte.
class TabellenZeile extends StatelessWidget {
  const TabellenZeile({
    super.key,
    required this.row,
    required this.eigene,
    this.live = false,
  });

  final StandingRow row;
  final bool eigene;

  /// Läuft gerade ein Spiel dieser Mannschaft?
  final bool live;

  @override
  Widget build(BuildContext context) {
    final diff = row.goalsFor - row.goalsAgainst;
    return Container(
      // Die eigene Mannschaft hervorheben — sonst sucht man sie in 18 Zeilen.
      color: eigene
          ? MatchUpColors.green.withValues(alpha: 0.12)
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '${row.rank}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          TeamBadge(team: row.team, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              row.team.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: eigene ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          SizedBox(
            width: 28,
            child: Text('${row.played}', textAlign: TextAlign.end),
          ),
          SizedBox(
            width: 38,
            child: Text(
              diff > 0 ? '+$diff' : '$diff',
              textAlign: TextAlign.end,
            ),
          ),
          SizedBox(
            width: 32,
            child: TabellenPunkte(punkte: row.points, live: live),
          ),
        ],
      ),
    );
  }
}
