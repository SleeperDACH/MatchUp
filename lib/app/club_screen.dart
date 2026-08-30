import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/models/models.dart';
import '../core/models/squad_member.dart';
import '../features/favorites/favorites.dart';
import '../features/news/providers.dart';
import '../features/tippspiel/providers.dart';
import '../features/tippspiel/ui/team_badge.dart';
import 'widgets/team_fixture_list.dart';
import 'theme.dart';
import 'widgets/segmented_tab_bar.dart';

/// Vereinsseite: Spielplan, Tabelle, Kader und News eines Klubs.
///
/// Erreichbar über das Vereinswappen — in der Ligatabelle, in den Spielkacheln
/// des Live-Tabs und in den Fantasy-MatchUp-Aufstellungen.
///
/// [leagueId] ist optional: Wer den Screen aus einer Ligatabelle öffnet, kennt
/// die Liga; wer ihn aus einer Fantasy-Aufstellung öffnet, nicht. Fehlt sie,
/// wird sie aus den Wettbewerben des Vereins abgeleitet (siehe
/// [_ligaFuerVerein]) — nur dann kann der Tabellen-Tab etwas anzeigen.
class ClubScreen extends ConsumerWidget {
  const ClubScreen({super.key, required this.team, this.leagueId});

  final TeamRef team;
  final String? leagueId;

  /// Reine Sportmonks-ID (die App führt Team-IDs als `sportmonks:<id>`).
  String get _teamId => team.id.split(':').last;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liga = leagueId ?? _ligaFuerVerein(ref, team.id);

    final tabs = <Tab>[
      const Tab(text: 'Spielplan'),
      if (liga != null) const Tab(text: 'Tabelle'),
      const Tab(text: 'Kader'),
      const Tab(text: 'News'),
    ];
    final views = <Widget>[
      _SpielplanTab(teamId: _teamId),
      if (liga != null) _TabelleTab(leagueId: liga, teamId: team.id),
      _KaderTab(teamId: _teamId),
      _NewsTab(teamId: _teamId, name: team.name, leagueId: liga),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 8,
          title: Row(
            children: [
              TeamBadge(team: team, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(team.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          bottom: SegmentedTabBar(tabs: tabs),
        ),
        body: TabBarView(children: views),
      ),
    );
  }
}

/// Welche Liga führt diesen Verein? Abgeleitet aus den bereits geladenen
/// Saison-Spielplänen (`leagueTeamsProvider` hängt am selben Cache), damit
/// dafür kein zusätzlicher Abruf nötig ist. `null`, solange nichts geladen ist
/// oder der Verein in keiner der geführten Ligen auftaucht — dann entfällt der
/// Tabellen-Tab, statt eine falsche Tabelle zu zeigen.
String? _ligaFuerVerein(WidgetRef ref, String teamId) {
  for (final l in Leagues.all) {
    final teams = ref.watch(leagueTeamsProvider(l.id)).valueOrNull;
    if (teams == null) continue;
    if (teams.any((t) => t.id == teamId)) return l.id;
  }
  return null;
}

// --- Spielplan ------------------------------------------------------------

class _SpielplanTab extends ConsumerWidget {
  const _SpielplanTab({required this.teamId});
  final String teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(teamFixturesProvider(teamId));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => _Fehler(
        text: 'Spielplan konnte nicht geladen werden.',
        onRetry: () => ref.invalidate(teamFixturesProvider(teamId)),
      ),
      data: (fixtures) {
        if (fixtures.isEmpty) return const _Leer('Keine Spiele im Zeitraum.');

        // Gleiche Aufteilung wie im Favoriten-Tab: erst was ansteht, darunter
        // die Ergebnisse (jüngste zuerst). Die Darstellung der Boxen kommt aus
        // `team_fixture_list.dart` — bewusst dieselbe wie dort.
        final kommend = [
          for (final f in fixtures)
            if (f.status != FixtureStatus.finished) f
        ]..sort((a, b) => a.kickoff.compareTo(b.kickoff));
        final ergebnisse = [
          for (final f in fixtures)
            if (f.status == FixtureStatus.finished) f
        ]..sort((a, b) => b.kickoff.compareTo(a.kickoff));

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(teamFixturesProvider(teamId)),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            children: [
              if (kommend.isNotEmpty) ...[
                const FixtureSectionLabel('Nächste Spiele'),
                ...fixturesWithDateHeaders(kommend),
              ],
              if (ergebnisse.isNotEmpty) ...[
                const FixtureSectionLabel('Ergebnisse'),
                ...fixturesWithDateHeaders(ergebnisse),
              ],
            ],
          ),
        );
      },
    );
  }
}

// --- Tabelle --------------------------------------------------------------

class _TabelleTab extends ConsumerWidget {
  const _TabelleTab({required this.leagueId, required this.teamId});
  final String leagueId;
  final String teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(liveLeagueTableProvider(leagueId));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => _Fehler(
        text: 'Tabelle konnte nicht geladen werden.',
        onRetry: () => _tabelleNeuLaden(ref, leagueId),
      ),
      data: (rows) {
        if (rows.isEmpty) return const _Leer('Noch keine Tabelle verfügbar.');
        return RefreshIndicator(
          onRefresh: () async => _tabelleNeuLaden(ref, leagueId),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
            itemCount: rows.length,
            itemBuilder: (context, i) =>
                _TabellenZeile(row: rows[i], eigene: rows[i].team.id == teamId),
          ),
        );
      },
    );
  }
}

class _TabellenZeile extends StatelessWidget {
  const _TabellenZeile({required this.row, required this.eigene});
  final StandingRow row;
  final bool eigene;

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
              child: Text('${row.rank}',
                  style: const TextStyle(fontWeight: FontWeight.w600))),
          TeamBadge(team: row.team, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(row.team.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontWeight:
                        eigene ? FontWeight.bold : FontWeight.normal)),
          ),
          SizedBox(
              width: 28, child: Text('${row.played}', textAlign: TextAlign.end)),
          SizedBox(
              width: 38,
              child: Text(diff > 0 ? '+$diff' : '$diff',
                  textAlign: TextAlign.end)),
          SizedBox(
            width: 32,
            child: Text('${row.points}',
                textAlign: TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// --- Kader ----------------------------------------------------------------

class _KaderTab extends ConsumerWidget {
  const _KaderTab({required this.teamId});
  final String teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(teamSquadProvider(teamId));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => _Fehler(
        text: 'Kader konnte nicht geladen werden.',
        onRetry: () => ref.invalidate(teamSquadProvider(teamId)),
      ),
      data: (kader) {
        if (kader.isEmpty) return const _Leer('Kein Kader hinterlegt.');

        // Nach Positionsgruppen bündeln; innerhalb der Gruppe bleibt die
        // Reihenfolge der Function (Trikotnummer aufsteigend).
        final gruppen = <String, List<SquadMember>>{};
        for (final m in kader) {
          gruppen.putIfAbsent(squadGroupLabel(m.position), () => []).add(m);
        }
        final eintraege = <Widget>[];
        for (final g in squadGroupOrder) {
          final list = gruppen[g];
          if (list == null || list.isEmpty) continue;
          eintraege.add(_GruppenKopf(titel: g, anzahl: list.length));
          eintraege.addAll([for (final m in list) _KaderZeile(member: m)]);
        }

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(teamSquadProvider(teamId)),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
            children: eintraege,
          ),
        );
      },
    );
  }
}

class _GruppenKopf extends StatelessWidget {
  const _GruppenKopf({required this.titel, required this.anzahl});
  final String titel;
  final int anzahl;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
        child: Row(
          children: [
            Text(titel,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(width: 8),
            Text('$anzahl',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      );
}

class _KaderZeile extends StatelessWidget {
  const _KaderZeile({required this.member});
  final SquadMember member;

  @override
  Widget build(BuildContext context) {
    final gedaempft = Theme.of(context).colorScheme.onSurfaceVariant;
    final alter = member.age;
    final teile = [
      if (member.nationality != null) member.nationality!,
      if (alter != null) '$alter Jahre',
    ];
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: SizedBox(
        width: 34,
        child: Text(
          member.jerseyNumber?.toString() ?? '–',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontWeight: FontWeight.bold, fontSize: 16, color: gedaempft),
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(member.name,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if (member.captain) ...[
            const SizedBox(width: 6),
            const Text('C',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    color: MatchUpColors.green)),
          ],
        ],
      ),
      subtitle: teile.isEmpty ? null : Text(teile.join(' · ')),
    );
  }
}

// --- News -----------------------------------------------------------------

class _NewsTab extends ConsumerWidget {
  const _NewsTab({required this.teamId, required this.name, this.leagueId});
  final String teamId;
  final String name;
  final String? leagueId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = (teamId: teamId, name: name, leagueId: leagueId);
    final async = ref.watch(teamNewsProvider(args));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => _Fehler(
        text: 'News konnten nicht geladen werden.',
        onRetry: () => ref.invalidate(teamNewsProvider(args)),
      ),
      data: (items) {
        if (items.isEmpty) return const _Leer('Aktuell keine Meldungen.');
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(teamNewsProvider(args)),
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final n = items[i];
              final datum = n.publishedAt;
              return ListTile(
                title: Text(n.title),
                subtitle: Text([
                  if (n.source != null && n.source!.isNotEmpty) n.source!,
                  if (datum != null)
                    DateFormat('d. MMM', 'de_DE').format(datum.toLocal()),
                ].join(' · ')),
                trailing: const Icon(Icons.open_in_new, size: 18),
                onTap: () => launchUrl(Uri.parse(n.url),
                    mode: LaunchMode.externalApplication),
              );
            },
          ),
        );
      },
    );
  }
}

// --- gemeinsame Bausteine -------------------------------------------------

class _Fehler extends StatelessWidget {
  const _Fehler({required this.text, required this.onRetry});
  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Erneut laden')),
          ],
        ),
      );
}

class _Leer extends StatelessWidget {
  const _Leer(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Text(text,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}

// --- Navigation von einem Wappen aus --------------------------------------

/// Öffnet die Vereinsseite. Platzhalter der K.-o.-Runde („2H", „ARG/CPV")
/// sind keine echten Vereine und werden ignoriert.
void oeffneVerein(BuildContext context, TeamRef team, {String? leagueId}) {
  if (isPlaceholderTeam(team) || !team.id.startsWith('sportmonks:')) return;
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => ClubScreen(team: team, leagueId: leagueId),
  ));
}

/// Macht ein beliebiges Wappen antippbar.
class ClubLink extends StatelessWidget {
  const ClubLink({
    super.key,
    required this.team,
    required this.child,
    this.leagueId,
  });

  final TeamRef team;
  final Widget child;
  final String? leagueId;

  @override
  Widget build(BuildContext context) {
    final tippbar =
        !isPlaceholderTeam(team) && team.id.startsWith('sportmonks:');
    if (!tippbar) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => oeffneVerein(context, team, leagueId: leagueId),
      child: child,
    );
  }
}

/// Tokens, die keinen Verein unterscheiden — Rechtsform, Gründungsjahr,
/// Vereinspräfixe. Ohne die würde „Borussia Dortmund" auf „Borussia
/// Mönchengladbach" passen.
const _namensBallast = {
  'fc', 'sv', 'sc', 'vfb', 'vfl', 'tsg', 'fsv', 'rb', 'sg', 'tsv', 'bv',
  'borussia', 'eintracht', 'sportverein', 'verein', '1', '04', '05', '07',
  '09', '1846', '1899', '1900', 'du', 'die',
};

Set<String> _kennTokens(String name) => name
    .toLowerCase()
    .replaceAll('ä', 'a')
    .replaceAll('ö', 'o')
    .replaceAll('ü', 'u')
    .replaceAll('ß', 'ss')
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .split(' ')
    .where((t) => t.isNotEmpty && !_namensBallast.contains(t))
    .toSet();

/// Sucht zu einem Vereinsnamen (Fantasy führt den kanonischen
/// OpenLigaDB-Namen) den Sportmonks-[TeamRef] der Bundesliga.
///
/// Nötig, weil die Fantasy-Seite nur Namen kennt, die Vereinsseite aber eine
/// Team-ID braucht. Verglichen werden die unterscheidenden Namensbestandteile
/// („SV Werder Bremen" ↔ „Werder Bremen" über `werder`/`bremen`).
///
/// **Bleibt die Zuordnung mehrdeutig oder leer, gibt es keinen Treffer** — das
/// Wappen ist dann schlicht nicht antippbar. Lieber kein Link als der falsche
/// Verein.
final clubTeamRefProvider =
    Provider.family<TeamRef?, String>((ref, clubName) {
  final teams = ref.watch(leagueTeamsProvider('bundesliga')).valueOrNull;
  if (teams == null) return null;
  final gesucht = _kennTokens(clubName);
  if (gesucht.isEmpty) return null;
  final treffer =
      teams.where((t) => _kennTokens(t.name).intersection(gesucht).isNotEmpty);
  return treffer.length == 1 ? treffer.first : null;
});

/// Aktualisiert die Tabelle. Beide Quellen müssen neu geladen werden: die
/// API-Standings **und** der Spielplan, aus dem die laufenden Spiele in die
/// Tabelle überlagert werden.
void _tabelleNeuLaden(WidgetRef ref, String leagueId) {
  ref.invalidate(leagueTableProvider(leagueId));
  ref.invalidate(leagueSeasonFixturesProvider(leagueId));
}
