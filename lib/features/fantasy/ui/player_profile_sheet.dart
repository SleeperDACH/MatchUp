import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/app_avatar.dart';
import '../../auth/providers.dart';
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
          const Divider(height: 1),
          Flexible(
            child: statsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Stats konnten nicht geladen werden.\n$e',
                    textAlign: TextAlign.center),
              ),
              data: (season) => _table(context, season),
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
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('Noch keine gewerteten Spieltage.',
            textAlign: TextAlign.center),
      );
    }
    final defensive = player.position == PlayerPosition.gk ||
        player.position == PlayerPosition.def;
    final rows = [
      for (final r in rounds)
        (r, season[r]?[player.id] ?? const PlayerMatchStats())
    ];
    final total = rows.fold<int>(
        0, (s, e) => s + scorePlayer(e.$2, player.position, league.scoring));
    final games = rows.where((e) => e.$2.played).length;

    TableRow header() => TableRow(
          decoration: BoxDecoration(color: scheme.surfaceContainerHighest),
          children: [
            _cell('SpT', bold: true),
            _cell('Min', bold: true, align: TextAlign.center),
            _cell('T', bold: true, align: TextAlign.center),
            _cell('V', bold: true, align: TextAlign.center),
            if (defensive) _cell('ZN', bold: true, align: TextAlign.center),
            _cell('Pkt', bold: true, align: TextAlign.right),
          ],
        );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Zusammenfassung.
          Row(
            children: [
              _summary(context, '$total', 'Punkte', scheme.primary),
              const SizedBox(width: 10),
              _summary(context, '$games', 'Spiele', scheme.tertiary),
            ],
          ),
          const SizedBox(height: 12),
          Table(
            border: TableBorder(
              horizontalInside:
                  BorderSide(color: scheme.outlineVariant, width: 0.5),
            ),
            columnWidths: const {
              0: FlexColumnWidth(1.4),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(1),
              3: FlexColumnWidth(1),
            },
            children: [
              header(),
              for (final (r, s) in rows)
                TableRow(
                  children: [
                    _cell('$r.'),
                    _cell(s.played ? '${s.minutes}' : '–',
                        align: TextAlign.center),
                    _cell('${s.goals}', align: TextAlign.center),
                    _cell('${s.assists}', align: TextAlign.center),
                    if (defensive)
                      _cell(s.cleanSheet && s.played ? '✓' : '–',
                          align: TextAlign.center),
                    _cell(
                      '${scorePlayer(s, player.position, league.scoring)}',
                      align: TextAlign.right,
                      bold: true,
                    ),
                  ],
                ),
            ],
          ),
        ],
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

  Widget _cell(String text,
      {bool bold = false, TextAlign align = TextAlign.left}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
      child: Text(
        text,
        textAlign: align,
        style: TextStyle(
            fontSize: 13,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal),
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
