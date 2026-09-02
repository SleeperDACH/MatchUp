import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/typografie.dart';
import '../../../app/widgets/leise_reiter.dart';
import '../../../app/widgets/team_fixture_list.dart';
import '../../../core/models/models.dart';
import '../../../core/models/team_fixture.dart';

import '../../../core/ui/app_avatar.dart';
import '../../auth/providers.dart';
import '../logic/aufstellungs_prognose.dart';
import '../logic/fantasy_scoring_engine.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';
import 'club_badge.dart';
import 'pitch_painter.dart';
import 'trade_screen.dart';
import '../logic/waiver_fenster.dart';
import 'player_action_buttons.dart';
import '../../../app/widgets/punktzahl.dart';
import '../logic/spieler_schnitt.dart';

/// Öffnet das Spielerprofil (Kopf + Leistungstabelle je Spieltag; für eigene
/// Spieler zusätzlich „Droppen"). [isMine] steuert den Drop-Button.
Future<void> showPlayerProfile(
  BuildContext context, {
  required FantasyLeague league,
  required FantasyPlayer player,
  String? clubIcon,
  required bool isMine,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _PlayerProfileSheet(
      league: league,
      player: player,
      clubIcon: clubIcon,
      isMine: isMine,
    ),
  );
}

class _PlayerProfileSheet extends ConsumerWidget {
  const _PlayerProfileSheet({
    required this.league,
    required this.player,
    required this.clubIcon,
    required this.isMine,
  });

  final FantasyLeague league;
  final FantasyPlayer player;
  final String? clubIcon;
  final bool isMine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final statsAsync = ref.watch(seasonStatsProvider);
    final cutoff = DateTime(league.season, 8, 1);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Kopf: Wappen, Name, Verein/Position/Alter.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                ClubBadge(club: player.club, iconUrl: clubIcon, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        player.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          PositionPill(pos: player.position),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${player.club} · ${player.ageOn(cutoff)} J.',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                      // **Hier steht der genaue Grund.** Auf der Karte ist nur
                      // Platz für ein Symbol; wer wissen will, ob es ein
                      // Kreuzbandriss oder eine Prellung ist, kommt hierher.
                      _Ausfallzeile(playerId: player.id),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // **Vier Reiter statt einer Tabelle.** Seit das Wappen kein Link
          // mehr auf die Vereinsseite ist, muss das Profil hergeben, wofür man
          // dorthin ging: Spielplan und Kader des Vereins — plus die Leistung,
          // die es schon zeigte. Dazu die **voraussichtliche Aufstellung**:
          // Vor dem Aufstellen ist „spielt er überhaupt?" die erste Frage, und
          // sie stand vorher nirgends in der App.
          DefaultTabController(
            length: 4,
            child: Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const LeiseReiter(
                    titel: ['Leistung', 'Aufstellung', 'Spielplan', 'Kader'],
                    horizontal: 12,
                  ),
                  Flexible(
                    child: TabBarView(
                      children: [
                        statsAsync.when(
                          loading: () => const Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                          error: (e, _) => Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'Stats konnten nicht geladen werden.\n$e',
                              textAlign: TextAlign.center,
                            ),
                          ),
                          data: (season) => _table(context, season),
                        ),
                        _Prognose(league: league, player: player),
                        _Spielplan(club: player.club),
                        _Vereinskader(
                          league: league,
                          club: player.club,
                          aktiv: player.id,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          _actions(context, ref),
        ],
      ),
    );
  }

  /// Aktionsleiste: eigener Spieler → Traden + Droppen; fremder (gehört einem
  /// anderen Manager) → Traden (mit dem Besitzer). Freie Spieler: keine Aktion.
  Widget _actions(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final myId = ref.watch(currentUserProvider)?.id;
    final roster =
        ref.watch(leagueRosterProvider(league.id)).valueOrNull ??
        const <RosterEntry>[];
    final managers =
        ref.watch(fantasyManagersProvider(league.id)).valueOrNull ??
        const <FantasyManager>[];
    final ownerId = roster
        .where((r) => r.playerId == player.id)
        .map((r) => r.managerId)
        .firstOrNull;
    final ownerMgr = ownerId == null
        ? null
        : managers.where((m) => m.userId == ownerId).firstOrNull;

    final List<Widget> children;
    if (isMine) {
      children = [
        Expanded(
          child: FilledButton.icon(
            onPressed: () => _tradeMine(context, ref, managers, myId),
            icon: const Icon(Icons.swap_horiz),
            label: const Text('Traden'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: scheme.error,
              side: BorderSide(color: scheme.error.withValues(alpha: 0.5)),
            ),
            onPressed: () => _drop(context, ref),
            icon: const Icon(Icons.person_remove_outlined),
            label: const Text('Droppen'),
          ),
        ),
      ];
    } else if (ownerMgr != null && ownerId != myId) {
      children = [
        Expanded(
          child: FilledButton.icon(
            onPressed: () => _tradeRequest(context, ownerMgr),
            icon: const Icon(Icons.swap_horiz),
            label: Text('Mit ${ownerMgr.display} traden'),
          ),
        ),
      ];
    } else {
      // **Freie Spieler bekommen ihren Knopf.** Vorher endete das Profil hier
      // ohne Aktion: Man sah, dass jemand frei ist, und musste zurück in die
      // Free Agency, um ihn zu holen.
      //
      // Gebaut wird er von `PlayerActionButton` in seiner breiten Fassung —
      // damit gelten hier dieselben Regeln wie in der Liste (Waiver,
      // U20-Sperre, voller Kader mit Abgabe-Blatt), ohne sie zu wiederholen.
      final spiele =
          ref.watch(fantasySeasonFixturesProvider).valueOrNull ??
          const <Fixture>[];
      final onWaivers =
          ref.watch(waiverPlayersProvider(league.id)).valueOrNull ??
          const <String>{};
      final claims =
          ref.watch(myWaiverClaimsProvider(league.id)).valueOrNull ??
          const <WaiverClaim>[];
      final offen = claims.where((c) => c.status.isPending).toList();
      final pool =
          ref.watch(playerPoolProvider).valueOrNull ?? const <FantasyPlayer>[];
      final nachId = {for (final p in pool) p.id: p};
      children = [
        Expanded(
          child: PlayerActionButton(
            breit: true,
            league: league,
            player: player,
            ownerId: null,
            onWaiver: onWaivers.contains(player.id),
            aufWire: vereinAufWire(player.club, spiele, DateTime.now()),
            claimed: offen.any((c) => c.addPlayerId == player.id),
            myPlayers: [
              for (final r in roster)
                if (r.managerId == myId && nachId[r.playerId] != null)
                  nachId[r.playerId]!,
            ],
            nextRank: offen.length + 1,
            myId: myId,
          ),
        ),
      ];
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(children: children),
      ),
    );
  }

  /// Trade um diesen (fremden) Spieler: Compose mit dem Besitzer, Spieler ist
  /// bereits als Anforderung vorausgewählt.
  void _tradeRequest(BuildContext context, FantasyManager owner) {
    final nav = Navigator.of(context);
    nav.pop();
    nav.push(
      MaterialPageRoute(
        builder: (_) => TradeComposeScreen(
          league: league,
          partner: owner,
          initialRequest: {player.id},
        ),
      ),
    );
  }

  /// Eigenen Spieler traden: Partner wählen, dann Compose mit dem Spieler
  /// bereits im Angebot.
  Future<void> _tradeMine(
    BuildContext context,
    WidgetRef ref,
    List<FantasyManager> managers,
    String? myId,
  ) async {
    final others = managers.where((m) => m.userId != myId).toList();
    if (others.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keine anderen Manager in der Liga.')),
      );
      return;
    }
    final partner = await showDialog<FantasyManager>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Mit wem traden?'),
        children: [
          for (final m in others)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(m),
              child: Row(
                children: [
                  AppAvatar(
                    imageUrl: m.avatarUrl,
                    emoji: m.avatarEmoji,
                    colorHex: m.avatarColor,
                    fallbackText: m.display,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      m.display,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
    if (partner == null || !context.mounted) return;
    final nav = Navigator.of(context);
    nav.pop();
    nav.push(
      MaterialPageRoute(
        builder: (_) => TradeComposeScreen(
          league: league,
          partner: partner,
          initialOffer: {player.id},
        ),
      ),
    );
  }

  Widget _table(
    BuildContext context,
    Map<int, Map<String, PlayerMatchStats>> season,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final rounds = season.keys.toList()..sort();
    if (rounds.isEmpty) {
      return const _Leer('Noch keine gewerteten Spieltage.');
    }
    final defensive =
        player.position == PlayerPosition.gk ||
        player.position == PlayerPosition.def;
    final rows = [
      for (final r in rounds)
        (r, season[r]?[player.id] ?? const PlayerMatchStats()),
    ];
    final total = rows.fold<double>(
      0,
      (s, e) => s + scorePlayer(e.$2, player.position, league.scoring),
    );
    final games = rows.where((e) => e.$2.played).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      children: [
        Row(
          children: [
            // Die Punktzahl ist der Inhalt, kein Signal — sie stand hier in
            // Signalgrün und war damit das Lauteste im Reiter.
            _summary(context, formatPoints(total), 'Punkte', scheme.onSurface),
            const SizedBox(width: 10),
            _summary(context, '$games', 'Spiele', scheme.onSurfaceVariant),
          ],
        ),
        const SizedBox(height: 10),
        _Schnitte(
          schnitt: spielerSchnitt(
            saison: season,
            spielerId: player.id,
            position: player.position,
            regeln: league.scoring,
          ),
        ),
        const SizedBox(height: 12),
        _LeistungKopf(defensive: defensive),
        // **Jede Zeile ist antippbar.** Eine Punktzahl allein sagt nicht,
        // woher sie kommt — 6 Punkte können ein halbes Spiel oder ein Tor
        // minus zwei Gegentore sein. Der Tipp öffnet die Aufschlüsselung.
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final (i, (r, st)) in rows.indexed) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    color: scheme.onSurface.withValues(alpha: 0.07),
                  ),
                _LeistungZeile(
                  runde: r,
                  stats: st,
                  defensive: defensive,
                  punkte: scorePlayer(st, player.position, league.scoring),
                  onTap: () => _zeigeAufschluesselung(context, r, st),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Die Punkte eines Spieltags im Einzelnen.
  void _zeigeAufschluesselung(
    BuildContext context,
    int runde,
    PlayerMatchStats stats,
  ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _Aufschluesselung(
        titel: '${player.name} · $runde. Spieltag',
        score: scorePlayerDetailed(stats, player.position, league.scoring),
        gespielt: stats.hasContribution,
      ),
    );
  }

  Widget _summary(BuildContext context, String value, String label, Color c) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.withValues(alpha: 0.35)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: c,
              ),
            ),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _drop(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${player.name} droppen?'),
        // **Was mit einer laufenden Aufstellung passiert, gehört hierher.**
        // „Er bleibt in der Elf" ist die Auskunft, nach der man sonst rät —
        // und die Frage stellt sich genau in dem Moment, in dem man droppt.
        content: const Text(
          'Der Spieler verlässt deinen Kader und kommt für 24 Stunden auf '
          'den Waiver-Wire. Sein Platz bleibt frei, bis du nachlegst.\n\n'
          'Hat sein Spiel schon angepfiffen, bleibt er für diesen Spieltag '
          'in deiner Elf und punktet weiter für dich.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Droppen'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref
          .read(fantasyLeagueRepositoryProvider)
          .dropPlayer(league.id, player.id);
      // Realtime greift bei RPC-Moves nicht zuverlässig — sofort auffrischen.
      ref.invalidate(leagueRosterProvider(league.id));
      ref.invalidate(waiverPlayersProvider(league.id));
      ref.invalidate(leagueLineupsProvider(league.id));
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('${player.name} gedroppt')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Fehlgeschlagen: $e')));
    }
  }
}

/// Spaltenköpfe der Leistungstabelle. Die Breiten stehen hier und werden von
/// [_LeistungZeile] gelesen — zwei Zahlen an zwei Stellen liefen beim nächsten
/// Feinschliff auseinander.
class _LeistungKopf extends StatelessWidget {
  const _LeistungKopf({required this.defensive});

  final bool defensive;

  static const spT = 42.0;
  static const zahl = 34.0;
  static const punkte = 52.0;

  @override
  Widget build(BuildContext context) {
    final stil = TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.8,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    Widget z(String t) => SizedBox(
      width: zahl,
      child: Text(t, style: stil, textAlign: TextAlign.center),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Row(
        children: [
          SizedBox(
            width: spT,
            child: Text('SPT', style: stil),
          ),
          const Spacer(),
          z('MIN'),
          z('T'),
          z('V'),
          if (defensive) z('ZN'),
          SizedBox(
            width: punkte,
            child: Text('PKT', style: stil, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

/// Eine Zeile der Leistungstabelle — antippbar für die Aufschlüsselung.
class _LeistungZeile extends StatelessWidget {
  const _LeistungZeile({
    required this.runde,
    required this.stats,
    required this.defensive,
    required this.punkte,
    required this.onTap,
  });

  final int runde;
  final PlayerMatchStats stats;
  final bool defensive;
  final double punkte;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final gespielt = stats.hasContribution;
    final stil = TextStyle(
      fontSize: 13,
      fontFeatures: const [FontFeature.tabularFigures()],
      color: gespielt ? scheme.onSurface : scheme.onSurfaceVariant,
    );
    Widget z(String t) => SizedBox(
      width: _LeistungKopf.zahl,
      child: Text(t, style: stil, textAlign: TextAlign.center),
    );
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: _LeistungKopf.spT,
              child: Text(
                '$runde.',
                style: stil.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const Spacer(),
            // Nicht gespielt zeigt „–", nicht „0" — dieselbe Regel wie im
            // MatchUp: Eine Null ist sonst doppeldeutig.
            z(gespielt ? '${stats.minutes}' : '–'),
            z(gespielt ? '${stats.goals}' : '–'),
            z(gespielt ? '${stats.assists}' : '–'),
            if (defensive) z(!gespielt ? '–' : (stats.cleanSheet ? '✓' : '–')),
            SizedBox(
              width: _LeistungKopf.punkte,
              child: Text(
                gespielt ? formatPoints(punkte) : '–',
                textAlign: TextAlign.right,
                style: stil.copyWith(fontWeight: FontWeight.w800, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Die Punkte eines Spieltags im Einzelnen: jede Zeile der Wertung mit Anzahl,
/// Einzelwert und Summe.
///
/// Eine Punktzahl allein sagt nicht, woher sie kommt — 6 Punkte können ein
/// halbes Spiel sein oder ein Tor minus zwei Gegentore. Die Aufschlüsselung
/// kommt aus derselben Funktion, die auch wertet (`scorePlayerDetailed`); eine
/// zweite Rechnung fürs Anzeigen wäre eine zweite Wahrheit.
class _Aufschluesselung extends StatelessWidget {
  const _Aufschluesselung({
    required this.titel,
    required this.score,
    required this.gespielt,
  });

  final String titel;
  final PlayerScore score;
  final bool gespielt;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              titel,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (!gespielt)
              const _Leer('An diesem Spieltag nicht eingesetzt.')
            else if (score.breakdown.isEmpty)
              const _Leer('Keine wertbaren Aktionen.')
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final l in score.breakdown)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: [
                            Expanded(child: Text(l.label)),
                            if (l.count != 1) ...[
                              Text(
                                '${l.count} ×',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            SizedBox(
                              width: 56,
                              child: Text(
                                formatPoints(l.subtotal),
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                  // Rot markiert den Abzug — die Ausnahme.
                                  // Der Normalfall braucht keine Farbe.
                                  color: l.subtotal < 0
                                      ? scheme.error
                                      : scheme.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const Divider(height: 18),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Gesamt',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        Text(
                          formatPoints(score.total),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: score.total < 0
                                ? scheme.error
                                : scheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Spielplan des Vereins, zu dem der Spieler gehört.
///
/// Er war bisher nur über die Vereinsseite erreichbar — also über den Tipp
/// aufs Wappen, den es hier nicht mehr gibt. Benutzt dieselbe Zeilenform wie
/// Live-Tab, Favoriten und Liga-Übersicht (`fixturesWithDateHeaders`); vier
/// Darstellungen derselben Liste wären drei zu viel.
class _Spielplan extends ConsumerWidget {
  const _Spielplan({required this.club});

  final String club;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alle = ref.watch(fantasySeasonFixturesProvider).valueOrNull;
    if (alle == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final seine = [
      for (final f in alle)
        if (f.home.name == club || f.away.name == club) f,
    ]..sort((a, b) => a.kickoff.compareTo(b.kickoff));
    if (seine.isEmpty) {
      return _Leer('Für $club liegt kein Spielplan vor.');
    }
    final liga = Leagues.byId(seine.first.leagueId);
    final umgewandelt = [
      for (final f in seine)
        TeamFixture(
          id: f.id,
          kickoff: f.kickoff,
          status: f.status,
          leagueName: liga.name,
          round: f.round,
          home: f.home,
          away: f.away,
          homeScore: f.homeScore,
          awayScore: f.awayScore,
        ),
    ];
    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      children: fixturesWithDateHeaders(umgewandelt),
    );
  }
}

/// Der Vereinskader — alle Poolspieler desselben Vereins, nach Position.
///
/// Antippen öffnet **deren** Profil: Der Weg von einem Spieler zu seinen
/// Mitspielern führte vorher über die Vereinsseite.
class _Vereinskader extends ConsumerWidget {
  const _Vereinskader({
    required this.league,
    required this.club,
    required this.aktiv,
  });

  final FantasyLeague league;
  final String club;

  /// Der Spieler, dessen Profil gerade offen ist — er wird hervorgehoben.
  final String aktiv;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final pool = ref.watch(playerPoolProvider).valueOrNull;
    if (pool == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final clubIcons =
        ref.watch(clubIconsProvider).valueOrNull ?? const <String, String?>{};
    final kader =
        [
          for (final p in pool)
            if (p.club == club) p,
        ]..sort(
          (a, b) => a.position.index != b.position.index
              ? a.position.index.compareTo(b.position.index)
              : a.name.compareTo(b.name),
        );
    if (kader.isEmpty) return _Leer('Für $club steht kein Kader im Pool.');

    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      itemCount: kader.length,
      itemBuilder: (context, i) {
        final p = kader[i];
        final ich = p.id == aktiv;
        return ListTile(
          dense: true,
          leading: ClubBadge(
            club: p.club,
            iconUrl: clubIcons[p.club],
            size: 28,
          ),
          title: Text(
            p.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: ich ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
          subtitle: Text(
            p.position.label,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          // Kein Grün für „du bist hier" — das ist kein laufender Vorgang.
          trailing: ich
              ? Icon(Icons.person, size: 18, color: scheme.onSurfaceVariant)
              : const Icon(Icons.chevron_right, size: 18),
          onTap: ich
              ? null
              : () {
                  Navigator.of(context).pop();
                  showPlayerProfile(
                    context,
                    league: league,
                    player: p,
                    clubIcon: clubIcons[p.club],
                    isMine: false,
                  );
                },
        );
      },
    );
  }
}

/// Leerzustand eines Reiters — sagt, was fehlt, statt weiß zu bleiben.
class _Leer extends StatelessWidget {
  const _Leer(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ),
  );
}

/// **Die voraussichtliche Aufstellung** des Vereins für das nächste Spiel.
///
/// Die Frage, für die dieser Reiter da ist, hat genau eine Zeile: *Steht mein
/// Spieler in der Elf?* Sie steht deshalb ganz oben und nicht als Fußnote
/// unter einer Liste. Die restlichen zehn sind Zusammenhang, kein Ersatz
/// dafür.
class _Prognose extends ConsumerWidget {
  const _Prognose({required this.league, required this.player});

  final FantasyLeague league;
  final FantasyPlayer player;

  /// **Ein Name auf dem Feld führt ins Profil**, genau wie in der Kaderliste
  /// nebenan. Wer sieht, dass statt seines Stürmers ein anderer aufläuft, will
  /// als Nächstes wissen, wer das ist — und muss dafür nicht in die Free
  /// Agency zurück.
  ///
  /// Getippt wird nur, wen der Pool kennt: Sportmonks meldet gelegentlich
  /// einen Spieler, den der letzte Kader-Sync noch nicht hat. Ein Tipp, der
  /// nichts öffnet, wäre schlimmer als keiner — deshalb entscheidet der
  /// Aufrufer anhand von [oeffnet], ob die Zeile überhaupt reagiert.
  void _oeffne(BuildContext context, WidgetRef ref, String playerId) {
    final ziel = _ausPool(ref, playerId);
    if (ziel == null) return;
    final icons =
        ref.read(clubIconsProvider).valueOrNull ?? const <String, String?>{};
    final myId = ref.read(currentUserProvider)?.id;
    final roster = ref.read(leagueRosterProvider(league.id)).valueOrNull ??
        const <RosterEntry>[];
    final meiner =
        roster.any((r) => r.playerId == ziel.id && r.managerId == myId);
    Navigator.of(context).pop();
    showPlayerProfile(
      context,
      league: league,
      player: ziel,
      clubIcon: icons[ziel.club],
      isMine: meiner,
    );
  }

  /// Alle Spieler des Vereins, die **nicht** in der Startelf stehen — aus
  /// unserem Pool, nicht aus der Aufstellung.
  ///
  /// **Die gemeldete Ersatzbank wäre die kleinere Auskunft.** Sie gibt es erst
  /// kurz vor Anpfiff, sie umfasst neun Namen, und wer gar nicht im Kader für
  /// dieses Spiel steht, fehlte darin ganz. Gefragt ist aber, wer sonst noch
  /// da ist — vor dem Aufstellen ist das die Anschlussfrage an „steht mein
  /// Spieler drin?".
  ///
  /// Abgewanderte bleiben draußen: Sie stehen für keinen Verein mehr auf dem
  /// Platz (Migration 0117).
  List<FantasyPlayer> _uebrige(WidgetRef ref, PrognoseElf elf) {
    final pool =
        ref.watch(playerPoolProvider).valueOrNull ?? const <FantasyPlayer>[];
    final drin = {for (final s in elf.elf) s.playerId};
    return [
      for (final p in pool)
        if (p.club == player.club && !p.abgewandert && !drin.contains(p.id)) p,
    ]..sort((a, b) => a.position.index != b.position.index
        ? a.position.index.compareTo(b.position.index)
        : a.name.compareTo(b.name));
  }

  FantasyPlayer? _ausPool(WidgetRef ref, String playerId) {
    final pool =
        ref.read(playerPoolProvider).valueOrNull ?? const <FantasyPlayer>[];
    for (final p in pool) {
      if (p.id == playerId) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spiele = ref.watch(fantasySeasonFixturesProvider).valueOrNull;
    if (spiele == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final spiel = spielFuerPrognose(spiele, player.club);
    if (spiel == null) {
      return const _Leer('Für diese Saison steht kein Spiel mehr an.');
    }

    final elfAsync = ref.watch(
      prognoseElfProvider((club: player.club, runde: spiel.round)),
    );

    return elfAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) =>
          _Leer('Die Aufstellung konnte nicht geladen werden.\n$e'),
      data: (elf) => ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 16),
        children: [
          _PrognoseKopf(spiel: spiel, elf: elf),
          if (elf == null)
            _NochKeinePrognose(player: player, spiel: spiel)
          else ...[
            _Urteil(
              drin: elf.enthaelt(player.id),
              bank: elf.aufBank(player.id),
              bestaetigt: elf.bestaetigt,
            ),
            _Formationsfeld(
              elf: elf,
              ich: player.id,
              oeffnet: (id) => _ausPool(ref, id) != null,
              onTip: (id) => _oeffne(context, ref, id),
            ),
            _NichtInDerElf(
              uebrige: _uebrige(ref, elf),
              ich: player.id,
              onTip: (id) => _oeffne(context, ref, id),
            ),
          ],
        ],
      ),
    );
  }
}

/// **Die Elf, wie sie auf dem Platz steht.**
///
/// Eine Liste beantwortet „wer spielt", aber nicht „wo" — und genau das ist
/// die Frage, wenn man eine Aufstellung liest. Gezeichnet wird auf demselben
/// Feld wie der Aufstellungs-Editor, der Draft-Raum und das Manager-Profil
/// (`pitchGradient` + [PitchLinesPainter]); ein eigener Feldlook an einer
/// fünften Stelle wäre nur ein weiterer Dialekt.
///
/// Die Reihen kommen aus dem Raster von Sportmonks, nicht aus einer eigenen
/// Rechnung — [PrognoseElf.reihen]. Torwart unten, Angriff oben, wie überall
/// sonst in der App.
class _Formationsfeld extends StatelessWidget {
  const _Formationsfeld({
    required this.elf,
    required this.ich,
    required this.oeffnet,
    required this.onTip,
  });

  final PrognoseElf elf;

  /// Der Spieler, dessen Profil offen ist.
  final String ich;

  /// Kennt der Pool diesen Spieler? Nur dann reagiert seine Karte.
  final bool Function(String playerId) oeffnet;
  final void Function(String playerId) onTip;

  @override
  Widget build(BuildContext context) {
    final reihen = elf.reihen;
    // Von hinten nach vorn gerechnet, von vorn nach hinten gezeichnet.
    final vonVorn = reihen.reversed.toList();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      height: 340,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: pitchGradient,
      ),
      child: CustomPaint(
        painter: const PitchLinesPainter(),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
          child: Column(
            children: [
              for (final reihe in vonVorn)
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (final s in reihe)
                        Flexible(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: s.playerId == ich || !oeffnet(s.playerId)
                                ? null
                                : () => onTip(s.playerId),
                            child: _Feldspieler(
                              spieler: s,
                              hervor: s.playerId == ich,
                            ),
                          ),
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

/// Ein Spieler auf dem Feld: Rückennummer im Kreis, Name darunter.
///
/// Hervorgehoben wird **hell**, nicht grün: Grün heißt in dieser App „hier
/// läuft etwas", und dass man gerade das eigene Profil ansieht, läuft nicht.
class _Feldspieler extends StatelessWidget {
  const _Feldspieler({required this.spieler, required this.hervor});

  final PrognoseSpieler spieler;
  final bool hervor;

  @override
  Widget build(BuildContext context) {
    const schnee = Color(0xFFEDEFF4);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: hervor ? schnee : Colors.black.withValues(alpha: 0.42),
            border: Border.all(
              color: schnee.withValues(alpha: hervor ? 1 : 0.45),
              width: hervor ? 2 : 1,
            ),
          ),
          child: Text(
            spieler.nummer?.toString() ?? '–',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: hervor ? const Color(0xFF12141C) : schnee,
            ),
          ),
        ),
        const SizedBox(height: 3),
        // Der Name schrumpft, statt zu kappen — dieselbe Regel wie im
        // Live-Tab: „Schlotterb…" sagt nichts.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _kurzerName(spieler.name),
              maxLines: 1,
              style: TextStyle(
                fontSize: 10,
                height: 1.15,
                fontWeight: hervor ? FontWeight.w800 : FontWeight.w600,
                color: schnee.withValues(alpha: hervor ? 1 : 0.85),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// „Nico Schlotterbeck" → „N. Schlotterbeck". Auf einem Feld mit fünf Spielern
/// nebeneinander ist der Nachname das, was zählt.
String _kurzerName(String voll) {
  final teile = voll.trim().split(RegExp(r'\s+'));
  if (teile.length < 2) return voll;
  return '${teile.first.characters.first}. ${teile.sublist(1).join(' ')}';
}

/// **Wer sonst noch da ist.**
///
/// Unter dem Feld stehen alle Spieler des Vereins, die nicht in der Startelf
/// stehen — der Kader aus unserem Pool, nicht die gemeldete Ersatzbank. Die
/// wäre die kleinere Auskunft: Es gibt sie erst kurz vor Anpfiff, sie zählt
/// neun Namen, und wer für dieses Spiel gar nicht im Kader steht, fehlte darin
/// ganz. Vor dem Aufstellen ist aber genau das die Anschlussfrage an „steht
/// mein Spieler drin?" — wer könnte statt seiner spielen.
///
/// Sie stehen unter dem Feld und nicht darauf: Wer nicht aufgestellt ist, hat
/// keinen Platz im Raster, und ein zwölfter Kreis am Spielfeldrand wäre eine
/// Behauptung über eine Position, die es nicht gibt.
class _NichtInDerElf extends StatelessWidget {
  const _NichtInDerElf({
    required this.uebrige,
    required this.ich,
    required this.onTip,
  });

  final List<FantasyPlayer> uebrige;
  final String ich;
  final void Function(String playerId) onTip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nicht in der Startelf',
            style: TextStyle(
              fontSize: Schrift.klein,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          if (uebrige.isEmpty)
            Text(
              'Aus dem Kader dieses Vereins steht niemand sonst im Pool.',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                height: 1.35,
                fontSize: Schrift.koerperKlein,
              ),
            )
          else
            for (final p in uebrige)
              _Uebriger(
                spieler: p,
                hervor: p.id == ich,
                onTap: p.id == ich ? null : () => onTip(p.id),
              ),
        ],
      ),
    );
  }
}

/// Eine Zeile darunter: Position, Name, Pfeil ins Profil.
class _Uebriger extends StatelessWidget {
  const _Uebriger({
    required this.spieler,
    required this.hervor,
    required this.onTap,
  });

  final FantasyPlayer spieler;
  final bool hervor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: Text(
                spieler.position.short,
                style: TextStyle(
                  fontSize: Schrift.klein,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                spieler.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: Schrift.koerper,
                  fontWeight: hervor ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
            Icon(
              hervor ? Icons.person : Icons.chevron_right,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// Kopf des Reiters: welches Spiel, welche Formation, wie frisch.
class _PrognoseKopf extends StatelessWidget {
  const _PrognoseKopf({required this.spiel, required this.elf});

  final Fixture spiel;
  final PrognoseElf? elf;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${spiel.home.name} – ${spiel.away.name}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            [
              '${spiel.roundName} · ${_wannKurz(spiel.kickoff.toLocal())}',
              if (elf?.formation != null) elf!.formation!,
            ].join(' · '),
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Die eine Zeile, für die es den Reiter gibt.
///
/// Farbe trägt nur der Fall, in dem etwas zu tun ist: Steht der Spieler
/// **nicht** in der Elf, muss der Manager seine Aufstellung ändern. Steht er
/// drin, ist nichts zu tun — dann bleibt es beim ruhigen Haken.
class _Urteil extends StatelessWidget {
  const _Urteil({
    required this.drin,
    required this.bank,
    required this.bestaetigt,
  });

  final bool drin;

  /// Er sitzt auf der Bank — das gibt es nur bei einer gemeldeten
  /// Aufstellung, und es ist eine andere Auskunft als „nicht dabei": Er kann
  /// eingewechselt werden und Punkte holen.
  final bool bank;

  /// Gemeldet statt vorhergesagt. Dann fällt das „voraussichtlich" weg — es
  /// wäre eine Unsicherheit, die es nicht mehr gibt.
  final bool bestaetigt;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // **Farbe trägt nur der Fall, der etwas will.** Steht der Spieler nicht in
    // der Elf, muss die Aufstellung geändert werden — Gold. Steht er drin, ist
    // nichts zu tun, und die Zeile bleibt still. Grün wäre hier doppelt
    // falsch: Es heißt in dieser App „hier läuft etwas", und es lief schon
    // einmal als Dauerfarbe durch dieses Profil.
    final farbe = drin ? scheme.onSurfaceVariant : const Color(0xFFFFC83D);
    final text = drin
        ? (bestaetigt ? 'In der Startelf' : 'Voraussichtlich in der Startelf')
        : bank
            ? 'Auf der Bank'
            : bestaetigt
                ? 'Nicht im Kader für dieses Spiel'
                : 'Nicht in der voraussichtlichen Elf';
    return Container(
      margin: EdgeInsets.fromLTRB(12, 0, 12, drin ? 2 : 8),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: drin ? 6 : 10),
      decoration: drin
          ? null
          : BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: farbe.withValues(alpha: 0.10),
              border: Border.all(color: farbe.withValues(alpha: 0.55)),
            ),
      child: Row(
        children: [
          Icon(
            drin
                ? Icons.check_circle_outline
                : bank
                    ? Icons.event_seat_outlined
                    : Icons.remove_circle_outline,
            size: 18,
            color: farbe,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontWeight: drin ? FontWeight.w600 : FontWeight.w700,
                color: farbe,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Der Zustand, den es die meiste Zeit der Woche gibt.
///
/// **Gemessen am 29.08.2026:** Sportmonks liefert die Prognose erst ein bis
/// zwei Tage vor Anpfiff — für Partien desselben und des nächsten Tages lagen
/// je 22 Einträge vor, für den vierten und siebten Tag keiner. Zwischen
/// Abpfiff und nächster Prognose liegen also mehrere Tage.
///
/// Eine leere Liste wäre hier der schlimmste Ausgang: Sie sähe aus wie „keiner
/// spielt" — derselbe Fehler wie das leere Feld im Draft-Brett. Deshalb sagt
/// der Zustand, *warum* nichts dasteht, und trägt mit der letzten
/// tatsächlichen Einsatzzeit die einzige belastbare Auskunft nach, die es zu
/// diesem Zeitpunkt gibt.
class _NochKeinePrognose extends ConsumerWidget {
  const _NochKeinePrognose({required this.player, required this.spiel});

  final FantasyPlayer player;
  final Fixture spiel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final spiele = ref.watch(fantasySeasonFixturesProvider).valueOrNull ?? [];
    final zuletzt = letztesGespieltes(spiele, player.club);
    final saison = ref.watch(seasonStatsProvider).valueOrNull;
    final stats = (zuletzt == null || saison == null)
        ? null
        : saison[zuletzt.round]?[player.id];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule, size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Noch keine Aufstellung',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Die voraussichtliche Elf steht in der Regel ein bis zwei Tage '
            'vor Anpfiff.',
            style: TextStyle(color: scheme.onSurfaceVariant, height: 1.35),
          ),
          if (stats != null && zuletzt != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: scheme.onSurface.withValues(alpha: 0.12),
                  width: 0.8,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Zuletzt',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    stats.minutes > 0
                        ? '${stats.minutes} Minuten · ${zuletzt.roundName}'
                        : 'Ohne Einsatz · ${zuletzt.roundName}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _wannKurz(DateTime d) =>
    DateFormat('E, d. MMM, HH:mm', 'de_DE').format(d);

/// Sagt im Profil, warum ein Spieler ausfällt — und seit wann.
///
/// Die Karte trägt nur ein Symbol (dort ist für „Verletzung der hinteren
/// Oberschenkelmuskulatur" kein Platz). Der Unterschied zwischen einer
/// Prellung und einem Kreuzbandriss entscheidet aber, ob man den Spieler hält
/// oder abgibt — deshalb steht er hier im Wortlaut.
class _Ausfallzeile extends ConsumerWidget {
  const _Ausfallzeile({required this.playerId});

  final String playerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = (ref.watch(absencesProvider).valueOrNull ?? const {})[playerId];
    if (a == null) return const SizedBox.shrink();
    final farbe = a.gesperrt
        ? const Color(0xFFF23030)
        : const Color(0xFFFFC83D);

    final teile = <String>[
      if (a.seit != null)
        'seit ${DateFormat('d. MMMM y', 'de_DE').format(a.seit!)}',
      if ((a.spieleVerpasst ?? 0) > 0)
        a.spieleVerpasst == 1
            ? 'ein Spiel verpasst'
            : '${a.spieleVerpasst} Spiele verpasst',
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: farbe.withValues(alpha: 0.10),
          border: Border.all(color: farbe.withValues(alpha: 0.45)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              a.gesperrt ? Icons.block : Icons.medical_services_outlined,
              size: 15,
              color: farbe,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${a.gesperrt ? 'Gesperrt' : 'Verletzt'} · ${a.grund}',
                    style: TextStyle(
                      color: farbe,
                      fontWeight: FontWeight.w700,
                      fontSize: Schrift.koerperKlein,
                    ),
                  ),
                  if (teile.isNotEmpty)
                    Text(
                      teile.join(' · '),
                      style: TextStyle(
                        fontSize: Schrift.klein,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// **Die beiden Schnitte nebeneinander.**
///
/// „⌀ je Spieltag" ist der Erwartungswert für nächste Woche, „⌀ je Einsatz",
/// was er kann, wenn er spielt. Beide zu zeigen ist keine Unentschlossenheit:
/// Bei einem Stammspieler stehen dort zwei gleiche Zahlen, bei einem
/// Ergänzungsspieler zwei sehr verschiedene — und **dieser Unterschied** ist
/// die Auskunft vor einem Pick-up.
class _Schnitte extends StatelessWidget {
  const _Schnitte({required this.schnitt});

  final SpielerSchnitt schnitt;

  @override
  Widget build(BuildContext context) {
    if (!schnitt.hatDaten) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final s = schnitt;

    Widget spalte(String titel, String minuten, String punkte, String fuss) =>
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titel.toUpperCase(),
                style: TextStyle(
                  fontSize: Schrift.mikro,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    punkte,
                    style: TextStyle(
                      fontSize: Schrift.h3,
                      fontWeight: FontWeight.w800,
                      fontFeatures: gleichbreiteZiffern,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Pkt',
                    style: TextStyle(
                      fontSize: Schrift.winzig,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    minuten,
                    style: TextStyle(
                      fontSize: Schrift.koerper,
                      fontWeight: FontWeight.w700,
                      fontFeatures: gleichbreiteZiffern,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    'Min',
                    style: TextStyle(
                      fontSize: Schrift.winzig,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              Text(
                fuss,
                style: TextStyle(
                  fontSize: Schrift.winzig,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          spalte(
            '⌀ je Spieltag',
            s.minutenJeSpieltag.round().toString(),
            formatPoints(s.punkteJeSpieltag),
            '${s.spieltage} Spieltage',
          ),
          // Ohne eine einzige Minute gibt es nichts zu mitteln — dann steht da
          // der Grund und keine 0, die niemand behauptet hat.
          if (s.punkteJeEinsatz == null)
            Expanded(
              child: Text(
                'Noch kein Einsatz',
                style: TextStyle(
                  fontSize: Schrift.klein,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          else
            spalte(
              '⌀ je Einsatz',
              s.minutenJeEinsatz!.round().toString(),
              formatPoints(s.punkteJeEinsatz!),
              '${s.einsaetze} Einsätze',
            ),
        ],
      ),
    );
  }
}
