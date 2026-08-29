import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

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
import 'trade_screen.dart';

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
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
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
                      Text(player.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold)),
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
                      titel: [
                        'Leistung',
                        'Aufstellung',
                        'Spielplan',
                        'Kader'
                      ],
                      horizontal: 12),
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
                                textAlign: TextAlign.center),
                          ),
                          data: (season) => _table(context, season),
                        ),
                        _Prognose(player: player),
                        _Spielplan(club: player.club),
                        _Vereinskader(
                            league: league, club: player.club, aktiv: player.id),
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
    final roster = ref.watch(leagueRosterProvider(league.id)).valueOrNull ??
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
      // Freier Spieler (kein Besitzer) — hier keine Trade-/Drop-Aktion.
      return const SizedBox.shrink();
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
    nav.push(MaterialPageRoute(
      builder: (_) => TradeComposeScreen(
        league: league,
        partner: owner,
        initialRequest: {player.id},
      ),
    ));
  }

  /// Eigenen Spieler traden: Partner wählen, dann Compose mit dem Spieler
  /// bereits im Angebot.
  Future<void> _tradeMine(BuildContext context, WidgetRef ref,
      List<FantasyManager> managers, String? myId) async {
    final others = managers.where((m) => m.userId != myId).toList();
    if (others.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Keine anderen Manager in der Liga.')));
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
                    child: Text(m.display,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
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
    nav.push(MaterialPageRoute(
      builder: (_) => TradeComposeScreen(
        league: league,
        partner: partner,
        initialOffer: {player.id},
      ),
    ));
  }

  Widget _table(
      BuildContext context, Map<int, Map<String, PlayerMatchStats>> season) {
    final scheme = Theme.of(context).colorScheme;
    final rounds = season.keys.toList()..sort();
    if (rounds.isEmpty) {
      return const _Leer('Noch keine gewerteten Spieltage.');
    }
    final defensive = player.position == PlayerPosition.gk ||
        player.position == PlayerPosition.def;
    final rows = [
      for (final r in rounds)
        (r, season[r]?[player.id] ?? const PlayerMatchStats())
    ];
    final total = rows.fold<double>(
        0, (s, e) => s + scorePlayer(e.$2, player.position, league.scoring));
    final games = rows.where((e) => e.$2.played).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      children: [
        Row(
          children: [
            _summary(context, formatPoints(total), 'Punkte', scheme.primary),
            const SizedBox(width: 10),
            _summary(context, '$games', 'Spiele', scheme.tertiary),
          ],
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
      BuildContext context, int runde, PlayerMatchStats stats) {
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
            Text(value,
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold, color: c)),
            Text(label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
        content: const Text(
            'Der Spieler verlässt deinen Kader und kommt für 24 Stunden auf '
            'den Waiver-Wire. Sein Platz bleibt frei, bis du nachlegst.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
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
          SnackBar(content: Text('${player.name} gedroppt')));
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
    Widget z(String t) =>
        SizedBox(width: zahl, child: Text(t, style: stil, textAlign: TextAlign.center));
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Row(
        children: [
          SizedBox(width: spT, child: Text('SPT', style: stil)),
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
        child: Text(t, style: stil, textAlign: TextAlign.center));
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: _LeistungKopf.spT,
              child: Text('$runde.',
                  style: stil.copyWith(fontWeight: FontWeight.w700)),
            ),
            const Spacer(),
            // Nicht gespielt zeigt „–", nicht „0" — dieselbe Regel wie im
            // MatchUp: Eine Null ist sonst doppeldeutig.
            z(gespielt ? '${stats.minutes}' : '–'),
            z(gespielt ? '${stats.goals}' : '–'),
            z(gespielt ? '${stats.assists}' : '–'),
            if (defensive)
              z(!gespielt ? '–' : (stats.cleanSheet ? '✓' : '–')),
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
            Text(titel,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
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
                              Text('${l.count} ×',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: scheme.onSurfaceVariant)),
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
                                    FontFeature.tabularFigures()
                                  ],
                                  color: l.subtotal < 0
                                      ? scheme.error
                                      : scheme.primary,
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
                          child: Text('Gesamt',
                              style: TextStyle(fontWeight: FontWeight.w800)),
                        ),
                        Text(formatPoints(score.total),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: score.total < 0
                                  ? scheme.error
                                  : scheme.primary,
                            )),
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
        if (f.home.name == club || f.away.name == club) f
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
    final kader = [
      for (final p in pool)
        if (p.club == club) p
    ]..sort((a, b) => a.position.index != b.position.index
        ? a.position.index.compareTo(b.position.index)
        : a.name.compareTo(b.name));
    if (kader.isEmpty) return _Leer('Für $club steht kein Kader im Pool.');

    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      itemCount: kader.length,
      itemBuilder: (context, i) {
        final p = kader[i];
        final ich = p.id == aktiv;
        return ListTile(
          dense: true,
          leading:
              ClubBadge(club: p.club, iconUrl: clubIcons[p.club], size: 28),
          title: Text(p.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontWeight: ich ? FontWeight.w800 : FontWeight.w600)),
          subtitle: Text(p.position.label,
              style: TextStyle(color: scheme.onSurfaceVariant)),
          trailing: ich
              ? Icon(Icons.person, size: 18, color: scheme.primary)
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
          child: Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
  const _Prognose({required this.player});

  final FantasyPlayer player;

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

    final elfAsync =
        ref.watch(prognoseElfProvider((club: player.club, runde: spiel.round)));

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
            _Urteil(drin: elf.enthaelt(player.id)),
            const SizedBox(height: 4),
            ..._elfZeilen(context, ref, elf),
          ],
        ],
      ),
    );
  }

  List<Widget> _elfZeilen(
      BuildContext context, WidgetRef ref, PrognoseElf elf) {
    final scheme = Theme.of(context).colorScheme;
    final pool = ref.watch(playerPoolProvider).valueOrNull ?? const [];
    final nachId = {for (final p in pool) p.id: p};

    return [
      for (final s in elf.elf)
        Builder(builder: (context) {
          final ich = s.playerId == player.id;
          // Die Position kommt aus **unserem** Pool, nicht von Sportmonks:
          // deren `position_id` mischt grobe und feine Positionen (24 Torwart,
          // aber 148 Innenverteidiger), und für die Wertung zählt ohnehin
          // unsere Einteilung.
          final imPool = nachId[s.playerId];
          return Container(
            color: ich ? scheme.primary.withValues(alpha: 0.10) : null,
            child: ListTile(
              dense: true,
              leading: SizedBox(
                width: 28,
                child: Text(
                  s.nummer?.toString() ?? '–',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    fontWeight: FontWeight.w700,
                    color: ich ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
              ),
              title: Text(
                // Kennt der Pool den Spieler nicht (Zugang nach dem letzten
                // Kader-Sync), steht der Name aus der Prognose da — „nicht
                // gefunden" ist ein eigener Zustand, kein leeres Feld.
                imPool?.name ?? s.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontWeight: ich ? FontWeight.w800 : FontWeight.w600),
              ),
              subtitle: imPool == null
                  ? null
                  : Text(imPool.position.label,
                      style: TextStyle(color: scheme.onSurfaceVariant)),
              trailing: ich
                  ? Icon(Icons.person, size: 18, color: scheme.primary)
                  : null,
            ),
          );
        }),
    ];
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
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            [
              '${spiel.roundName} · ${_wannKurz(spiel.kickoff.toLocal())}',
              if (elf?.formation != null) elf!.formation!,
            ].join(' · '),
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
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
  const _Urteil({required this.drin});

  final bool drin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final farbe = drin ? scheme.primary : const Color(0xFFFFC83D);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: drin ? null : farbe.withValues(alpha: 0.10),
        border: Border.all(
          color: farbe.withValues(alpha: drin ? 0.35 : 0.55),
          width: drin ? 0.8 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(drin ? Icons.check_circle_outline : Icons.event_seat_outlined,
              size: 18, color: farbe),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              drin
                  ? 'Voraussichtlich in der Startelf'
                  : 'Nicht in der voraussichtlichen Elf',
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: farbe, fontSize: 13.5),
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
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
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
                    width: 0.8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Zuletzt',
                      style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 0.6,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurfaceVariant)),
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
