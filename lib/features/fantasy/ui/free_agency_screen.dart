import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/widgets/pill_selector.dart';
import '../../../core/models/models.dart';
import '../../auth/providers.dart';
import '../logic/fantasy_scoring_engine.dart';
import '../logic/saison_punkte.dart';
import '../logic/waiver_fenster.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';
import 'club_badge.dart';
import 'player_action_buttons.dart';
import 'player_profile_sheet.dart';
import 'waiver_claims_screen.dart';

/// Free Agency & Waiver-Wire.
///
/// * Echte Free Agents (nie gedraftet oder vom Wire gefallen) sind sofort
///   holbar — respektiert Kadergröße (sonst Drop nötig) und die 05.09.-Sperre.
/// * Frisch gedroppte Spieler liegen 24 Stunden auf dem Waiver-Wire und sind
///   nur per Antrag holbar; nach Ablauf werden die Anträge in
///   Prioritätsreihenfolge abgearbeitet, sonst wird der Spieler frei.
/// * **Spieler in fremden Kadern stehen mit drin** — darunter, als zweite
///   Gruppe, mit dem Team des Besitzers und einem Trade-Knopf statt „Holen".
///   Die Spielersuche war bis dahin ein eigener Schirm mit derselben Liste in
///   anderer Reihenfolge; zwei Listen derselben Spieler nebeneinander zu
///   pflegen war die eigentliche Fehlerquelle.
///
/// Sortiert wird in **beiden** Gruppen nach den Punkten der laufenden Saison
/// (`saisonPunkte`). Die Gruppen bleiben getrennt, weil sie verschiedene
/// Handlungen tragen: oben holen, unten fragen.
class FreeAgencyScreen extends ConsumerStatefulWidget {
  const FreeAgencyScreen({super.key, required this.league, this.jetzt});

  final FantasyLeague league;

  /// **Nur für Vorschauen.** Der Schirm rechnet sonst mit `DateTime.now()`,
  /// und damit hinge sein Bild am Wochentag des Testlaufs: „Waiver bis Mo,
  /// 15:00" wird in einer englischen Woche zu „Do, 15:00". Ein fest
  /// eingecheckter Vergleich wäre dann nicht erst am nächsten Tag rot, sondern
  /// an einem beliebigen — und niemand wüsste, warum.
  final DateTime? jetzt;

  @override
  ConsumerState<FreeAgencyScreen> createState() => _FreeAgencyScreenState();
}

class _FreeAgencyScreenState extends ConsumerState<FreeAgencyScreen> {
  String _query = '';
  PlayerPosition? _position;

  @override
  Widget build(BuildContext context) {
    final league = widget.league;
    final poolAsync = ref.watch(playerPoolProvider);
    final roster =
        ref.watch(leagueRosterProvider(league.id)).valueOrNull ??
        const <RosterEntry>[];
    final onWaivers =
        ref.watch(waiverPlayersProvider(league.id)).valueOrNull ??
        const <String>{};
    final claims =
        ref.watch(myWaiverClaimsProvider(league.id)).valueOrNull ??
        const <WaiverClaim>[];
    final clubIcons =
        ref.watch(clubIconsProvider).valueOrNull ?? const <String, String?>{};
    final myId = ref.watch(currentUserProvider)?.id;

    // **Welche Vereine spielen gerade?** Dieselbe Regel wie auf dem Server
    // (`fantasy_spieler_laeuft`, Migration 0094): die niedrigste noch nicht
    // vollständig abgepfiffene Runde, und darin der Anpfiff je Verein.
    final spiele =
        ref.watch(fantasySeasonFixturesProvider).valueOrNull ??
        const <Fixture>[];
    final jetzt = widget.jetzt ?? DateTime.now();
    // **Die Waiver-Regel, nicht die Anpfiff-Regel.** Ein Spieler bleibt nach
    // dem Anpfiff seines Vereins bis zur Frist auf dem Waiver — nicht nur, bis
    // der Spieltag durch ist. `wireRunde` liefert `null`, sobald die Frist
    // vorbei ist; dann ist wieder alles direkt zu holen.
    final wireR = wireRunde(spiele, jetzt);
    final frist = wireR == null ? null : waiverFrist(spiele, wireR);
    final ausfaelle =
        ref.watch(absencesProvider).valueOrNull ?? const <String, dynamic>{};

    final pendingClaims = claims.where((c) => c.status.isPending).toList();
    final claimedPlayerIds = {for (final c in pendingClaims) c.addPlayerId};

    final managers =
        ref.watch(fantasyManagersProvider(league.id)).valueOrNull ??
        const <FantasyManager>[];
    final teamName = {for (final m in managers) m.userId: m.display};
    final ownerByPlayer = {for (final r in roster) r.playerId: r.managerId};
    final saison =
        ref.watch(seasonStatsProvider).valueOrNull ??
        const <int, Map<String, PlayerMatchStats>>{};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Free Agency'),
        actions: [
          IconButton(
            tooltip: 'Meine Anträge',
            icon: Badge(
              isLabelVisible: pendingClaims.isNotEmpty,
              label: Text('${pendingClaims.length}'),
              child: const Icon(Icons.assignment_outlined),
            ),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => WaiverClaimsScreen(league: league),
              ),
            ),
          ),
        ],
      ),
      body: poolAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (pool) {
          final playerById = {for (final p in pool) p.id: p};
          final rosteredIds = {for (final r in roster) r.playerId};
          final myPlayers = [
            for (final r in roster)
              if (r.managerId == myId && playerById[r.playerId] != null)
                playerById[r.playerId]!,
          ];

          final punkte = saisonPunkte(
            saison: saison,
            spieler: playerById,
            regeln: league.scoring,
          );

          // **Alle Spieler, nicht nur die freien** — gefiltert wie gehabt,
          // sortiert nach der Regel „freie zuerst, in jeder Gruppe die besten".
          final gefiltert = pool
              .where((p) => _position == null || p.position == _position)
              .where(
                (p) =>
                    _query.isEmpty ||
                    p.name.toLowerCase().contains(_query.toLowerCase()) ||
                    p.club.toLowerCase().contains(_query.toLowerCase()),
              )
              .toList();
          final liste = freieZuerst(
            gefiltert,
            inKadern: rosteredIds,
            punkte: punkte,
          );
          // Wo die zweite Gruppe beginnt — dort steht die Kapitelmarke.
          final ersterImKader = liste.indexWhere(
            (p) => rosteredIds.contains(p.id),
          );

          return Column(
            children: [
              _WaiverBanner(frist: frist),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Spieler oder Verein suchen',
                    contentPadding: EdgeInsets.symmetric(horizontal: 12),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    _chip(
                      'Alle',
                      _position == null,
                      () => setState(() => _position = null),
                    ),
                    for (final pos in PlayerPosition.values)
                      _chip(
                        pos.label,
                        _position == pos,
                        () => setState(() => _position = pos),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: liste.length,
                  itemBuilder: (context, i) {
                    final p = liste[i];
                    final imKader = rosteredIds.contains(p.id);
                    final waiver = onWaivers.contains(p.id);
                    final claimed = claimedPlayerIds.contains(p.id);
                    final aufWire = vereinAufWire(p.club, spiele, jetzt);
                    final zeile = ListTile(
                      // **Der Name führt ins Profil.** Wer entscheiden soll,
                      // ob er einen Spieler holt, braucht mehr als Verein und
                      // Position — Leistung, Spielplan und die
                      // voraussichtliche Aufstellung stehen dort. Die Zeile
                      // reagierte vorher gar nicht; nur der Knopf rechts tat
                      // etwas.
                      onTap: () => showPlayerProfile(
                        context,
                        league: league,
                        player: p,
                        clubIcon: clubIcons[p.club],
                        isMine: false,
                      ),
                      leading: ClubBadge(
                        club: p.club,
                        iconUrl: clubIcons[p.club],
                      ),
                      // **Die Punkte stehen dran, weil danach sortiert
                      // wird.** Eine Reihenfolge ohne sichtbaren Grund liest
                      // sich wie keine. Wer keinen Einsatz hatte, bekommt
                      // nichts hingeschrieben — „0" wäre eine Behauptung über
                      // jemanden, der gar nicht gespielt hat.
                      title: Row(
                        children: [
                          Expanded(child: Text(p.name)),
                          if (punkte[p.id] != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              formatPoints(punkte[p.id]!),
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Row(
                        children: [
                          PositionPill(pos: p.position),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              [
                                p.club,
                                if (imKader)
                                  teamName[ownerByPlayer[p.id]] ?? 'vergeben'
                                else if (waiver || aufWire)
                                  frist == null
                                      ? 'Waiver'
                                      : 'Waiver bis ${fristKurz(frist)}',
                                // **Wer ausfällt, gehört hier genannt.**
                                // Einen verletzten Spieler zu holen ist der
                                // teuerste Fehler in der Free Agency.
                                if (ausfaelle[p.id] != null)
                                  ausfaelle[p.id]!.gesperrt
                                      ? 'gesperrt'
                                      : 'verletzt',
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ausfaelle[p.id] == null
                                  ? null
                                  : TextStyle(
                                      color: ausfaelle[p.id]!.gesperrt
                                          ? const Color(0xFFF23030)
                                          : const Color(0xFFFFC83D),
                                    ),
                            ),
                          ),
                        ],
                      ),
                      trailing: PlayerActionButton(
                        aufWire: aufWire,
                        league: league,
                        player: p,
                        ownerId: ownerByPlayer[p.id],
                        onWaiver: waiver,
                        claimed: claimed,
                        myPlayers: myPlayers,
                        nextRank: pendingClaims.length + 1,
                        myId: myId,
                      ),
                    );
                    // Die Kapitelmarke sitzt **über** der ersten Kaderzeile,
                    // nicht als eigener Eintrag: So bleibt `itemCount` die
                    // Zahl der Spieler, und eine leere Gruppe erzeugt keine
                    // Überschrift über nichts.
                    if (i != ersterImKader || ersterImKader < 0) return zeile;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
                          child: Row(
                            children: [
                              Text(
                                'IN KADERN',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      letterSpacing: 1.2,
                                      fontWeight: FontWeight.w700,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Divider(
                                  height: 1,
                                  color: Theme.of(context).dividerColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        zeile,
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// **Kein `ChoiceChip`.** Es zieht seine Auswahlfarbe aus
  /// `secondaryContainer` — aus dem grünen Seed dieser App wird das ein
  /// stumpfes Oliv, und seine Beschriftung erbt die App-Schrift nicht: In der
  /// ersten Vorschau dieses Schirms standen dort schwarze Balken statt
  /// „Tor", „Abwehr", „Mittelfeld", „Sturm". Die Regel steht seit langem in
  /// CLAUDE.md; dieser Schirm hatte sie nur nie jemand angesehen.
  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: PillChip(label: label, selected: selected, onTap: onTap),
  );
}

/// Hinweis auf die Waiver-Regel — **und darauf, welche Phase gerade läuft.**
///
/// Die beiden Zustände sind verschiedene Spiele: Im Fenster wird beantragt und
/// zur Frist nach Priorität vergeben; danach zählt, wer zuerst tippt. Ein
/// Balken, der immer dasselbe sagt, verschweigt genau den Unterschied.
class _WaiverBanner extends StatelessWidget {
  const _WaiverBanner({required this.frist});

  /// Ende des laufenden Waivers — `null` in der freien Phase.
  final DateTime? frist;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // **Nicht `secondaryContainer`.** Aus dem grünen Seed wird das ein stumpfes
    // Oliv, und ein olivgrüner Balken über der ganzen Breite sagt nichts —
    // hier läuft nichts, hier steht eine Regel. Die Farbe des Waivers ist
    // Gold, und sie trägt nur den Hauch, den ein Hinweis braucht.
    const gold = Color(0xFFFFC83D);
    return Container(
      width: double.infinity,
      color: gold.withValues(alpha: 0.10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.schedule, size: 18, color: gold),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              frist == null
                  ? 'Freie Bahn: Wer frei ist, wird direkt geholt. Ab dem '
                        'Anpfiff seines Vereins liegt er auf dem Waiver.'
                  : 'Waiver bis ${fristKurz(frist!)} — dann werden die Anträge '
                        'nach Priorität vergeben. Gedroppte Spieler liegen '
                        'außerhalb 24 Stunden auf dem Waiver.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
