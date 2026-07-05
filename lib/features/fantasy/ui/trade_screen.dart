import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers.dart';
import '../../messaging/providers.dart';
import '../../messaging/ui/conversation_screen.dart';
import '../logic/playoff.dart';
import '../models/fantasy_models.dart';
import '../models/trade.dart';
import '../providers.dart';
import 'player_flag.dart';

/// Trade-Zentrale einer Liga: neue Angebote erstellen (Kader nebeneinander)
/// und ein- wie ausgehende Angebote verwalten (annehmen / ablehnen /
/// zurückziehen). Annahme tauscht die Spieler sofort.
class TradeScreen extends ConsumerWidget {
  const TradeScreen({super.key, required this.league});

  final FantasyLeague league;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myId = ref.watch(currentUserProvider)?.id;
    final trades = ref.watch(leagueTradesProvider(league.id)).valueOrNull ??
        const <TradeOffer>[];
    final openCount = trades
        .where((t) => t.status == TradeStatus.pending && t.toManager == myId)
        .length;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Trade'),
          bottom: TabBar(tabs: [
            const Tab(text: 'Neuer Trade'),
            Tab(text: openCount > 0 ? 'Angebote ($openCount)' : 'Angebote'),
          ]),
        ),
        body: TabBarView(
          children: [
            _PartnerList(league: league),
            _OffersTab(league: league),
          ],
        ),
      ),
    );
  }
}

/// Trades gesperrt, wenn die Trade-Deadline (Playoff-Einstellungen)
/// überschritten ist. Ohne Playoffs sind sie immer offen.
bool _tradesClosed(FantasyLeague league, int? currentRound) {
  if (!league.hasPlayoffs || currentRound == null) return false;
  final plan = computePlayoffPlan(
    teams: league.playoffTeams!,
    weeksPerRound: league.playoffWeeks ?? 1,
    tradeDeadlineOffset: league.tradeDeadlineOffset ?? 5,
  );
  return plan.isValid && currentRound > plan.tradeDeadlineRound;
}

class _PartnerList extends ConsumerWidget {
  const _PartnerList({required this.league});

  final FantasyLeague league;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myId = ref.watch(currentUserProvider)?.id;
    final managersAsync = ref.watch(fantasyManagersProvider(league.id));
    final currentRound = ref.watch(fantasyCurrentRoundProvider).valueOrNull;
    final closed = _tradesClosed(league, currentRound);

    return managersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler: $e')),
      data: (managers) {
        final others = managers.where((m) => m.userId != myId).toList();
        if (others.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Noch keine anderen Manager in der Liga.',
                  textAlign: TextAlign.center),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (closed)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('Die Trade-Deadline ist überschritten — '
                      'neue Angebote sind nicht mehr möglich.'),
                ),
              ),
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 8, 4, 8),
              child: Text('Mit wem möchtest du traden?'),
            ),
            for (final m in others)
              Card(
                child: ListTile(
                  leading: CircleAvatar(child: Text(_initial(m.username))),
                  title: Text(m.username),
                  trailing: const Icon(Icons.chevron_right),
                  enabled: !closed,
                  onTap: closed
                      ? null
                      : () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) =>
                              TradeComposeScreen(league: league, partner: m))),
                ),
              ),
          ],
        );
      },
    );
  }

  static String _initial(String name) =>
      name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();
}

/// Angebot erstellen: eigener Kader links, Partner-Kader rechts. Auf beiden
/// Seiten die Spieler antippen, die getauscht werden sollen.
class TradeComposeScreen extends ConsumerStatefulWidget {
  const TradeComposeScreen(
      {super.key, required this.league, required this.partner});

  final FantasyLeague league;
  final FantasyManager partner;

  @override
  ConsumerState<TradeComposeScreen> createState() =>
      _TradeComposeScreenState();
}

class _TradeComposeScreenState extends ConsumerState<TradeComposeScreen> {
  final _offer = <String>{}; // eigene Spieler, die ich abgebe
  final _request = <String>{}; // Spieler des Partners, die ich will
  final _msgCtrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  /// Namen der ausgewählten Spieler für die Nachricht auflösen.
  String _names(Set<String> ids, Map<String, FantasyPlayer> byId) => ids.isEmpty
      ? '—'
      : ids.map((id) => byId[id]?.name ?? id).join(', ');

  Future<void> _send() async {
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final note = _msgCtrl.text.trim();
    final String tradeId;
    try {
      tradeId = await ref.read(fantasyLeagueRepositoryProvider).proposeTrade(
            widget.league.id,
            widget.partner.userId,
            offerPlayers: _offer.toList(),
            requestPlayers: _request.toList(),
            message: note.isEmpty ? null : note,
          );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Fehlgeschlagen: $e')));
      if (mounted) setState(() => _sending = false);
      return;
    }

    // Trade steht — dazu eine Direktnachricht mit der Zusammenfassung senden.
    // Existiert noch kein Chat mit dem Partner, entsteht er automatisch;
    // sonst wird die Nachricht an die bestehende Konversation angehängt.
    try {
      final pool = ref.read(playerPoolProvider).valueOrNull ??
          const <FantasyPlayer>[];
      final byId = {for (final p in pool) p.id: p};
      final body = StringBuffer('🔄 Trade-Angebot in ${widget.league.name}\n'
          'Ich biete: ${_names(_offer, byId)}\n'
          'Dafür möchte ich: ${_names(_request, byId)}');
      if (note.isNotEmpty) body.write('\n„$note"');
      await ref
          .read(messagingRepositoryProvider)
          .sendMessage(widget.partner.userId, body.toString(), tradeId: tradeId);
    } catch (_) {
      // Chat-Nachricht ist optional — Trade wurde bereits gesendet.
    }

    if (!mounted) return;
    // Compose-Screen durch den Direktnachrichten-Chat ersetzen.
    navigator.pushReplacement(MaterialPageRoute(
        builder: (_) => ConversationScreen(
              partnerId: widget.partner.userId,
              partnerName: widget.partner.username,
            )));
  }

  @override
  Widget build(BuildContext context) {
    final myId = ref.watch(currentUserProvider)?.id;
    final poolAsync = ref.watch(playerPoolProvider);
    final roster = ref.watch(leagueRosterProvider(widget.league.id)).valueOrNull ??
        const <RosterEntry>[];

    return Scaffold(
      appBar: AppBar(title: Text('Trade mit ${widget.partner.username}')),
      body: poolAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (pool) {
          final byId = {for (final p in pool) p.id: p};
          List<FantasyPlayer> playersOf(String uid) => [
                for (final r in roster)
                  if (r.managerId == uid && byId[r.playerId] != null)
                    byId[r.playerId]!
              ]..sort((a, b) => a.position.index != b.position.index
                  ? a.position.index.compareTo(b.position.index)
                  : a.name.compareTo(b.name));

          final mine = myId == null ? <FantasyPlayer>[] : playersOf(myId);
          final theirs = playersOf(widget.partner.userId);
          final canSend =
              (_offer.isNotEmpty || _request.isNotEmpty) && !_sending;

          return Column(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _RosterColumn(
                        title: 'Du gibst',
                        players: mine,
                        selected: _offer,
                        onToggle: (id) => setState(() =>
                            _offer.contains(id) ? _offer.remove(id) : _offer.add(id)),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: _RosterColumn(
                        title: '${widget.partner.username} gibt',
                        players: theirs,
                        selected: _request,
                        onToggle: (id) => setState(() => _request.contains(id)
                            ? _request.remove(id)
                            : _request.add(id)),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Column(
                  children: [
                    TextField(
                      controller: _msgCtrl,
                      minLines: 1,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: 'Nachricht (optional)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: canSend ? _send : null,
                        icon: _sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.send),
                        label: Text(_sending
                            ? 'Sende …'
                            : 'Angebot senden (${_offer.length} ↔ ${_request.length})'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RosterColumn extends StatelessWidget {
  const _RosterColumn({
    required this.title,
    required this.players,
    required this.selected,
    required this.onToggle,
  });

  final String title;
  final List<FantasyPlayer> players;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          color: scheme.surfaceContainerHighest,
          child: Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        Expanded(
          child: players.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Kein Kader', textAlign: TextAlign.center),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: players.length,
                  itemBuilder: (context, i) {
                    final p = players[i];
                    final sel = selected.contains(p.id);
                    return InkWell(
                      onTap: () => onToggle(p.id),
                      child: Container(
                        color: sel
                            ? scheme.primary.withValues(alpha: 0.16)
                            : null,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        child: Row(
                          children: [
                            Icon(
                              sel
                                  ? Icons.check_circle
                                  : Icons.circle_outlined,
                              size: 18,
                              color: sel
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            SizedBox(
                                width: 22,
                                child: PlayerFlag(code: p.nationality)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(p.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13)),
                                  Text('${p.position.short} · ${p.club}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: scheme.onSurfaceVariant)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _OffersTab extends ConsumerWidget {
  const _OffersTab({required this.league});

  final FantasyLeague league;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myId = ref.watch(currentUserProvider)?.id;
    final trades = ref.watch(leagueTradesProvider(league.id)).valueOrNull ??
        const <TradeOffer>[];
    final items = ref.watch(tradeItemsProvider).valueOrNull ??
        const <String, List<TradeItem>>{};
    final pool = ref.watch(playerPoolProvider).valueOrNull ??
        const <FantasyPlayer>[];
    final managers = ref.watch(fantasyManagersProvider(league.id)).valueOrNull ??
        const <FantasyManager>[];

    final byId = {for (final p in pool) p.id: p};
    final names = {for (final m in managers) m.userId: m.username};

    // Offene zuerst, dann nach Datum absteigend.
    final sorted = [...trades]..sort((a, b) {
        if (a.status.isPending != b.status.isPending) {
          return a.status.isPending ? -1 : 1;
        }
        return b.createdAt.compareTo(a.createdAt);
      });

    if (sorted.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Noch keine Trade-Angebote.', textAlign: TextAlign.center),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final t in sorted)
          _TradeCard(
            trade: t,
            items: items[t.id] ?? const [],
            playerById: byId,
            names: names,
            myId: myId,
          ),
      ],
    );
  }
}

class _TradeCard extends ConsumerWidget {
  const _TradeCard({
    required this.trade,
    required this.items,
    required this.playerById,
    required this.names,
    required this.myId,
  });

  final TradeOffer trade;
  final List<TradeItem> items;
  final Map<String, FantasyPlayer> playerById;
  final Map<String, String> names;
  final String? myId;

  Future<void> _respond(BuildContext context, WidgetRef ref, bool accept) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(fantasyLeagueRepositoryProvider).respondTrade(trade.id, accept);
      messenger.showSnackBar(SnackBar(
          content: Text(accept ? 'Trade angenommen.' : 'Angebot abgelehnt.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Fehlgeschlagen: $e')));
    }
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(fantasyLeagueRepositoryProvider).cancelTrade(trade.id);
      messenger.showSnackBar(
          const SnackBar(content: Text('Angebot zurückgezogen.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Fehlgeschlagen: $e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final incoming = trade.toManager == myId;
    final offered = [
      for (final it in items)
        if (it.giver == trade.fromManager) playerById[it.playerId]?.name ?? it.playerId
    ];
    final requested = [
      for (final it in items)
        if (it.giver == trade.toManager) playerById[it.playerId]?.name ?? it.playerId
    ];
    final fromName = names[trade.fromManager] ?? '—';
    final toName = names[trade.toManager] ?? '—';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    incoming
                        ? 'Angebot von $fromName'
                        : 'Dein Angebot an $toName',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                _StatusChip(status: trade.status),
              ],
            ),
            const SizedBox(height: 8),
            _side(context, '$fromName gibt', offered, scheme.primary),
            const SizedBox(height: 4),
            _side(context, '$toName gibt', requested, scheme.tertiary),
            if (trade.message != null && trade.message!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('„${trade.message}"',
                  style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: scheme.onSurfaceVariant)),
            ],
            if (trade.status.isPending) ...[
              const SizedBox(height: 10),
              if (incoming)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _respond(context, ref, false),
                        child: const Text('Ablehnen'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => _respond(context, ref, true),
                        child: const Text('Annehmen'),
                      ),
                    ),
                  ],
                )
              else
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _cancel(context, ref),
                    icon: const Icon(Icons.undo, size: 18),
                    label: const Text('Zurückziehen'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _side(
      BuildContext context, String label, List<String> players, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(label,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
        Expanded(
          child: Text(players.isEmpty ? '—' : players.join(', '),
              style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final TradeStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color bg, Color fg) = switch (status) {
      TradeStatus.pending => (scheme.secondaryContainer, scheme.onSecondaryContainer),
      TradeStatus.accepted => (scheme.primaryContainer, scheme.onPrimaryContainer),
      TradeStatus.rejected => (scheme.errorContainer, scheme.onErrorContainer),
      TradeStatus.cancelled => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Text(status.label,
          style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}
