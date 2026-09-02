import 'package:flutter/material.dart';
import '../../../app/widgets/punktzahl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers.dart';
import '../logic/fantasy_scoring_engine.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';
import 'club_badge.dart';
import 'player_profile_sheet.dart';
import '../../../core/logic/vereins_kuerzel.dart';
import '../logic/naechstes_spiel.dart';
import '../../../core/models/models.dart';
import '../../../app/typografie.dart';

// Reihenfolge der Positionsblöcke (TW zuerst).
const _order = [
  PlayerPosition.gk,
  PlayerPosition.def,
  PlayerPosition.mid,
  PlayerPosition.fwd,
];

/// Aufbereitete Startelf/Bank einer Seite für einen Spieltag.
class MatchupSideData {
  MatchupSideData(
    this.starters,
    this.bench,
    this.points,
    this.total,
    this.gespielt,
  );

  final List<FantasyPlayer> starters;
  final List<FantasyPlayer> bench;
  final Map<String, double> points;
  final double total;

  /// Wer an diesem Spieltag **schon gespielt hat**.
  ///
  /// Ohne diese Auskunft ist eine 0 doppeldeutig: „hat gespielt und nichts
  /// geholt" sieht aus wie „ist noch gar nicht dran gewesen". Genau daran
  /// hing die Hervorhebung — ein Spieler ohne Anpfiff „führte" gegen einen mit
  /// drei Gegentoren und Gelb, weil 0 größer ist als −10.
  final Set<String> gespielt;

  List<FantasyPlayer> startersAt(PlayerPosition pos) => [
    for (final p in starters)
      if (p.position == pos) p,
  ]..sort((a, b) => (points[b.id] ?? 0).compareTo(points[a.id] ?? 0));
}

/// Startelf + Bank + Punkte einer Seite (gespeicherte Aufstellung, sonst
/// automatische beste Elf) — identisch zur Wertung im MatchUp-Tab.
MatchupSideData computeSideData({
  required FantasyLeague league,
  required int round,
  required String managerId,
  required Map<String, FantasyPlayer> byId,
  required List<RosterEntry> roster,
  required List<FantasyLineup> lineups,
  required Map<String, PlayerMatchStats> stats,
}) {
  final rosterPlayers = [
    for (final r in roster)
      if (r.managerId == managerId && byId[r.playerId] != null)
        byId[r.playerId]!,
  ];
  final saved = lineups
      .where((l) => l.managerId == managerId && l.round == round)
      .map((l) => l.playerIds)
      .firstOrNull;
  final kaderPunkte = {
    for (final p in rosterPlayers)
      p: scorePlayer(
        stats[p.id] ?? const PlayerMatchStats(),
        p.position,
        league.scoring,
      ),
  };
  final starterIds = (saved != null && saved.isNotEmpty)
      ? {
          for (final id in saved)
            if (byId.containsKey(id)) id,
        }
      : bestEleven(kaderPunkte, league.roster).starterIds;

  // **Die gespeicherte Elf ist die Auskunft, nicht der heutige Kader.**
  //
  // Vorher wurden die Startelf-Spieler aus `rosterPlayers` gefiltert — also
  // aus dem Bestand von *jetzt*. Wer nach dem Anpfiff abgegeben oder getradet
  // wurde, fiel damit rückwirkend aus der Elf und nahm seine Punkte mit.
  // Gemeldet als „einen Spieler droppen beeinflusst im Nachhinein die Punkte".
  //
  // Wer zum Anpfiff in der Elf stand, punktet für diesen Spieltag — auch wenn
  // er inzwischen woanders spielt. Der Server schreibt in `fantasy_lineups`
  // ohnehin nur Spieler, die dem Manager zum Zeitpunkt des Speicherns
  // gehörten (`fantasy_set_lineup`); geprüft wird beim **Schreiben**, nicht
  // beim Lesen.
  final starters = [
    for (final id in starterIds)
      if (byId[id] != null) byId[id]!,
  ]..sort((a, b) => a.position.index.compareTo(b.position.index));
  // Gewertet wird **Kader plus Startelf** — ein Spieler, der die Elf nach dem
  // Anpfiff verlassen hat, steht in keinem Kader mehr und hätte sonst keine
  // Punkte.
  final pointsByPlayer = {
    ...kaderPunkte,
    for (final p in starters)
      p: scorePlayer(
        stats[p.id] ?? const PlayerMatchStats(),
        p.position,
        league.scoring,
      ),
  };
  final bench =
      [
        for (final p in rosterPlayers)
          if (!starterIds.contains(p.id)) p,
      ]..sort(
        (a, b) => a.position.index != b.position.index
            ? a.position.index.compareTo(b.position.index)
            : (pointsByPlayer[b] ?? 0).compareTo(pointsByPlayer[a] ?? 0),
      );

  final points = {for (final e in pointsByPlayer.entries) e.key.id: e.value};
  final total = [
    for (final p in starters) points[p.id] ?? 0.0,
  ].fold<double>(0, (a, b) => a + b);
  final gespielt = {
    for (final p in pointsByPlayer.keys)
      if (stats[p.id]?.hasContribution ?? false) p.id,
  };
  return MatchupSideData(starters, bench, points, total, gespielt);
}

/// Spieler-Gegenüberstellung einer Head-to-Head-Paarung: beide Aufstellungen
/// positionsweise nebeneinander mit den (Live-)Punkten je Spieler, darunter
/// die ausklappbare Bank. Bei einem Bye (`away == null`) nur die eigene Seite.
/// Rendert als [Column] — passt in eine umgebende [ListView].
class MatchupLineups extends ConsumerWidget {
  const MatchupLineups({
    super.key,
    required this.league,
    required this.runde,
    required this.home,
    required this.away,
    required this.homeId,
    required this.awayId,
    required this.homeName,
    this.awayName,
  });

  final FantasyLeague league;

  /// Spieltag, um den es geht — für „wann spielt er als Nächstes?".
  final int runde;
  final MatchupSideData home;
  final MatchupSideData? away;
  final String homeId;
  final String? awayId;
  final String homeName;
  final String? awayName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clubIcons =
        ref.watch(clubIconsProvider).valueOrNull ?? const <String, String?>{};
    final myId = ref.watch(currentUserProvider)?.id;
    // Der Spielplan sagt, wer wann anpfeift — nicht der Statistik-Datensatz.
    final spiele =
        ref.watch(fantasySeasonFixturesProvider).valueOrNull ??
        const <Fixture>[];
    final jetzt = DateTime.now();
    bool angepfiffen(String verein) {
      final s = naechstesSpiel(spiele, runde, verein);
      return s != null && !s.anpfiff.isAfter(jetzt);
    }

    final homeMine = homeId == myId;
    final awayMine = awayId != null && awayId == myId;

    void openPlayer(FantasyPlayer p, bool mine) => showPlayerProfile(
      context,
      league: league,
      player: p,
      clubIcon: clubIcons[p.club],
      isMine: mine,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final pos in _order)
          ..._positionBlock(
            context,
            pos: pos,
            home: home,
            away: away,
            homeMine: homeMine,
            awayMine: awayMine,
            clubIcons: clubIcons,
            spiele: spiele,
            angepfiffen: angepfiffen,
            onTap: openPlayer,
          ),
        const SizedBox(height: 12),
        // **Keine Bank über nichts.** Steht auf keiner Seite jemand auf der
        // Bank, gibt es auch nichts aufzuklappen — die Zeile hätte nur
        // gesagt, dass sie leer ist.
        if (home.bench.isNotEmpty || (away?.bench.isNotEmpty ?? false))
          _BenchSection(
            home: home,
            away: away,
            homeName: homeName,
            awayName: awayName,
            clubIcons: clubIcons,
            homeMine: homeMine,
            awayMine: awayMine,
            onTap: openPlayer,
          ),
      ],
    );
  }

  /// Ein Positionsblock: Überschrift + zeilenweise Gegenüberstellung der
  /// Starter beider Seiten (nach Index innerhalb der Position gepaart).
  List<Widget> _positionBlock(
    BuildContext context, {
    required PlayerPosition pos,
    required MatchupSideData home,
    required MatchupSideData? away,
    required bool homeMine,
    required bool awayMine,
    required Map<String, String?> clubIcons,
    required List<Fixture> spiele,
    required bool Function(String verein) angepfiffen,
    required void Function(FantasyPlayer, bool) onTap,
  }) {
    final hs = home.startersAt(pos);
    final as = away?.startersAt(pos) ?? const <FantasyPlayer>[];
    if (hs.isEmpty && as.isEmpty) return const [];
    final rows = <Widget>[];
    final n = hs.length > as.length ? hs.length : as.length;
    for (var i = 0; i < n; i++) {
      final h = i < hs.length ? hs[i] : null;
      final a = i < as.length ? as[i] : null;
      final hp = h == null ? null : (home.points[h.id] ?? 0.0);
      final ap = a == null ? null : (away?.points[a.id] ?? 0.0);
      rows.add(
        _PlayerRow(
          home: h,
          away: a,
          homePts: hp,
          awayPts: ap,
          // **Angepfiffen, nicht „hat Statistiken".** Vorher entschied das
          // Vorhandensein einer Statistikzeile darüber, ob Punkte statt eines
          // Strichs erscheinen — und die war schon vor dem Anstoß da. Genau
          // deshalb standen zum Start des Spieltags überall 0,0 Punkte.
          homeGespielt: h != null && angepfiffen(h.club),
          awayGespielt: a != null && angepfiffen(a.club),
          homeSpiel: h == null ? null : naechstesSpiel(spiele, runde, h.club),
          awaySpiel: a == null ? null : naechstesSpiel(spiele, runde, a.club),
          homeMine: homeMine,
          awayMine: awayMine,
          clubIcons: clubIcons,
          onTap: onTap,
        ),
      );
    }
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: positionColor(pos),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              pos.label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: positionColor(pos),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
      ...rows,
    ];
  }
}

/// Eine Vergleichszeile: links Heim-Spieler, rechts Gast-Spieler, die Punkte
/// jeweils zur Mitte hin. Der punktbessere wird hervorgehoben.
class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.home,
    required this.away,
    required this.homePts,
    required this.awayPts,
    required this.homeGespielt,
    required this.awayGespielt,
    required this.homeSpiel,
    required this.awaySpiel,
    required this.homeMine,
    required this.awayMine,
    required this.clubIcons,
    required this.onTap,
  });

  final FantasyPlayer? home;
  final FantasyPlayer? away;
  final double? homePts;
  final double? awayPts;

  /// **Hat sein Verein schon angepfiffen?** Erst dann sind Punkte eine
  /// Auskunft; vorher steht in der Box, gegen wen und wann er spielt.
  final bool homeGespielt;
  final bool awayGespielt;

  /// Sein Spiel an diesem Spieltag — `null`, wenn sein Verein frei hat.
  final NaechstesSpiel? homeSpiel;
  final NaechstesSpiel? awaySpiel;

  final bool homeMine;
  final bool awayMine;
  final Map<String, String?> clubIcons;
  final void Function(FantasyPlayer, bool) onTap;

  @override
  Widget build(BuildContext context) {
    // **Die Hervorhebung heißt „führt in dieser Paarung" — und das darf nur
    // sagen, wer auch gespielt hat.** Vorher zählte allein die Punktzahl:
    // Ein Spieler ohne Anpfiff steht bei 0, und 0 ist mehr als die −10 eines
    // Verteidigers mit drei Gegentoren und Gelb. Also bekam der Umrahmung, der
    // noch gar nicht dran war, und der, der gespielt hatte, keine. Wer noch
    // nicht gespielt hat, führt nicht — er hat noch nicht angefangen.
    final lead = (homePts != null && awayPts != null)
        ? (homePts! > awayPts! && homeGespielt
              ? 1
              : awayPts! > homePts! && awayGespielt
              ? -1
              : 0)
        : 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: _cell(
              context,
              player: home,
              pts: homePts,
              mine: homeMine,
              highlight: lead > 0,
              gespielt: homeGespielt,
              spiel: homeSpiel,
              start: true,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _cell(
              context,
              player: away,
              pts: awayPts,
              mine: awayMine,
              highlight: lead < 0,
              gespielt: awayGespielt,
              spiel: awaySpiel,
              start: false,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(
    BuildContext context, {
    required FantasyPlayer? player,
    required double? pts,
    required bool mine,
    required bool highlight,
    required bool gespielt,
    required NaechstesSpiel? spiel,
    required bool start,
  }) {
    final scheme = Theme.of(context).colorScheme;
    if (player == null) {
      return const SizedBox(height: 60);
    }
    final pos = positionColor(player.position);
    final ptsBox = Container(
      constraints: const BoxConstraints(minWidth: 36),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: highlight
            ? scheme.primary.withValues(alpha: 0.22)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
      ),
      // **Vor dem Anpfiff steht hier das Spiel, nicht ein Strich.** „Noch
      // nicht gespielt" ist kein Nullpunktespiel — vorher stand in beiden
      // Fällen „0", dann ein Strich. Ein Strich sagt nichts Falsches, aber
      // auch nichts; die Frage vor einem Spieltag ist „gegen wen und wann?".
      //
      // `formatPoints` statt roher Interpolation: Die Wertung kennt −0,4 je
      // Foul, und `0.4`-Summen tragen sonst einen Fließkomma-Rattenschwanz
      // hinter sich her.
      child: gespielt
          ? _punkte(
              gespielt,
              pts,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: highlight ? scheme.primary : scheme.onSurface,
              ),
            )
          : _AnstossHinweis(spiel: spiel),
    );
    final badge = ClubBadge(
      club: player.club,
      iconUrl: clubIcons[player.club],
      size: 34,
    );
    final info = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: start
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      children: [
        Text(
          shortPlayerName(player.name),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: start ? TextAlign.start : TextAlign.end,
          style: TextStyle(
            fontSize: 14,
            fontWeight: mine ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          player.position.label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.3,
            color: pos,
          ),
        ),
      ],
    );

    final children = start
        ? [
            badge,
            const SizedBox(width: 9),
            Expanded(child: info),
            const SizedBox(width: 8),
            ptsBox,
          ]
        : [
            ptsBox,
            const SizedBox(width: 8),
            Expanded(child: info),
            const SizedBox(width: 9),
            badge,
          ];

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onTap(player, mine),
        child: Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            // Karten-Look: dezenter Verlauf mit Positions-Ton.
            gradient: LinearGradient(
              begin: start ? Alignment.centerLeft : Alignment.centerRight,
              end: start ? Alignment.centerRight : Alignment.centerLeft,
              colors: [
                pos.withValues(alpha: highlight ? 0.22 : 0.13),
                scheme.surfaceContainerHighest.withValues(alpha: 0.35),
              ],
            ),
            border: Border.all(
              color: highlight
                  ? scheme.primary.withValues(alpha: 0.7)
                  : scheme.outlineVariant.withValues(alpha: 0.5),
              width: highlight ? 1.5 : 1,
            ),
            boxShadow: highlight
                ? [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.18),
                      blurRadius: 8,
                      spreadRadius: -2,
                    ),
                  ]
                : null,
          ),
          child: Row(children: children),
        ),
      ),
    );
  }
}

/// Kürzt einen Spielernamen auf den Nachnamen (falls mehrteilig).
String shortPlayerName(String name) {
  final parts = name.trim().split(' ');
  return parts.length > 1 ? parts.last : name;
}

/// Ausklappbare Bank beider Seiten (zählt nicht für die Wertung).
class _BenchSection extends StatelessWidget {
  const _BenchSection({
    required this.home,
    required this.away,
    required this.homeName,
    required this.awayName,
    required this.clubIcons,
    required this.homeMine,
    required this.awayMine,
    required this.onTap,
  });

  final MatchupSideData home;
  final MatchupSideData? away;
  final String homeName;
  final String? awayName;
  final Map<String, String?> clubIcons;
  final bool homeMine;
  final bool awayMine;
  final void Function(FantasyPlayer, bool) onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        title: Text(
          'Bank',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _column(
                  context,
                  homeName,
                  home.bench,
                  home.points,
                  homeMine,
                ),
              ),
              if (awayName != null && away != null)
                Expanded(
                  child: _column(
                    context,
                    awayName!,
                    away!.bench,
                    away!.points,
                    awayMine,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _column(
    BuildContext context,
    String title,
    List<FantasyPlayer> bench,
    Map<String, double> points,
    bool mine,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          if (bench.isEmpty)
            Text(
              '—',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            )
          else
            for (final p in bench)
              InkWell(
                onTap: () => onTap(p, mine),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: positionColor(p.position),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      ClubBadge(
                        club: p.club,
                        iconUrl: clubIcons[p.club],
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          shortPlayerName(p.name),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Punktzahl(
                        points[p.id] ?? 0,
                        stil: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

/// Punkte einer Zeile — oder ein Strich, wenn noch nicht gespielt wurde.
///
/// **Noch nicht gespielt ist kein Nullpunktespiel.** Vorher stand in beiden
/// Fällen „0"; man konnte nicht unterscheiden, ob jemand gespielt und nichts
/// geholt hat oder noch gar nicht dran war.
Widget _punkte(
  bool gespielt,
  double? pts, {
  required TextStyle style,
  TextAlign? textAlign,
}) {
  if (!gespielt) {
    return Text('–', textAlign: textAlign, style: style);
  }
  return Align(
    alignment: textAlign == TextAlign.center
        ? Alignment.center
        : Alignment.centerLeft,
    child: Punktzahl(pts ?? 0, stil: style),
  );
}

/// Was in der Punktebox steht, solange sein Verein nicht angepfiffen hat:
/// **Gegner und Anstoß**, zweizeilig.
///
/// Zwei Zeilen und keine, weil „SVE Sa 15:30" in einer Zeile die Box auf die
/// doppelte Breite zöge — und die Box steht in einer Reihe mit Wappen und
/// Namen, die ihren Platz brauchen. Übereinander bleibt sie so breit wie eine
/// Punktzahl und wächst nur um wenige Punkte in der Höhe, die die Zeile
/// ohnehin hat.
class _AnstossHinweis extends StatelessWidget {
  const _AnstossHinweis({required this.spiel});

  final NaechstesSpiel? spiel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = spiel;
    // **Kein Spiel ist etwas anderes als „noch nicht angepfiffen".** Wessen
    // Verein an diesem Spieltag frei hat, für den gibt es nichts anzukündigen.
    if (s == null) {
      return Text(
        '–',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          vereinsKuerzel(s.gegner),
          maxLines: 1,
          style: TextStyle(
            fontSize: Schrift.klein,
            height: 1.1,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
            color: scheme.onSurface,
          ),
        ),
        Text(
          anpfiffKurz(s.anpfiff),
          maxLines: 1,
          style: TextStyle(
            fontSize: Schrift.mikro,
            height: 1.25,
            fontWeight: FontWeight.w600,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
