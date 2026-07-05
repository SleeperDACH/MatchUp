import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers.dart';
import '../../messaging/providers.dart';
import '../../messaging/ui/conversation_screen.dart';
import '../logic/playoff.dart';
import '../models/fantasy_models.dart';
import '../models/trade.dart';
import '../providers.dart';
import 'club_badge.dart';

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
  const TradeComposeScreen({
    super.key,
    required this.league,
    required this.partner,
    this.initialOffer = const {},
    this.initialRequest = const {},
    this.counterOf,
  });

  final FantasyLeague league;
  final FantasyManager partner;

  /// Vorauswahl (z. B. beim Kontern eines Angebots).
  final Set<String> initialOffer;
  final Set<String> initialRequest;

  /// ID des ursprünglichen Angebots, das hiermit gekontert (geschlossen) wird.
  final String? counterOf;

  @override
  ConsumerState<TradeComposeScreen> createState() =>
      _TradeComposeScreenState();
}

class _TradeComposeScreenState extends ConsumerState<TradeComposeScreen> {
  late final Set<String> _offer = {...widget.initialOffer}; // ich gebe ab
  late final Set<String> _request = {...widget.initialRequest}; // ich will
  final _msgCtrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

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
            counterOf: widget.counterOf,
          );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Fehlgeschlagen: $e')));
      if (mounted) setState(() => _sending = false);
      return;
    }

    // Beim Kontern das Original als „gekontert" auffrischen.
    if (widget.counterOf != null) {
      ref.invalidate(tradeDetailProvider(widget.counterOf!));
      ref.invalidate(leagueTradesProvider(widget.league.id));
    }

    // Direktnachricht als Träger der Trade-Karte (ohne vorgefertigten Text).
    // Existiert noch kein Chat, entsteht er automatisch; sonst wird angehängt.
    try {
      await ref
          .read(messagingRepositoryProvider)
          .sendMessage(widget.partner.userId, 'Trade-Angebot', tradeId: tradeId);
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
    final scheme = Theme.of(context).colorScheme;
    final myId = ref.watch(currentUserProvider)?.id;
    final poolAsync = ref.watch(playerPoolProvider);
    final roster = ref.watch(leagueRosterProvider(widget.league.id)).valueOrNull ??
        const <RosterEntry>[];
    final clubIcons =
        ref.watch(clubIconsProvider).valueOrNull ?? const <String, String?>{};

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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                child: Text(
                  'Tippe auf beiden Seiten die Spieler an, die getauscht werden '
                  'sollen.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _RosterColumn(
                        title: 'Du gibst',
                        accent: scheme.primary,
                        players: mine,
                        selected: _offer,
                        clubIcons: clubIcons,
                        onToggle: (id) => setState(() =>
                            _offer.contains(id) ? _offer.remove(id) : _offer.add(id)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _RosterColumn(
                        title: '${widget.partner.username} gibt',
                        accent: scheme.tertiary,
                        players: theirs,
                        selected: _request,
                        clubIcons: clubIcons,
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
    required this.accent,
    required this.players,
    required this.selected,
    required this.clubIcons,
    required this.onToggle,
  });

  final String title;
  final Color accent;
  final List<FantasyPlayer> players;
  final Set<String> selected;
  final Map<String, String?> clubIcons;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selCount = players.where((p) => selected.contains(p.id)).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.14),
            border: Border(bottom: BorderSide(color: accent, width: 2)),
          ),
          child: Column(
            children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold, color: accent)),
              Text(selCount == 0 ? 'nichts gewählt' : '$selCount ausgewählt',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
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
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: players.length,
                  itemBuilder: (context, i) =>
                      _tile(context, players[i], selected.contains(players[i].id)),
                ),
        ),
      ],
    );
  }

  Widget _tile(BuildContext context, FantasyPlayer p, bool sel) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Material(
        color: sel
            ? accent.withValues(alpha: 0.18)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => onToggle(p.id),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: sel ? accent : Colors.transparent,
                width: 1.6,
              ),
            ),
            child: Column(
              children: [
                Stack(
                  alignment: Alignment.topRight,
                  clipBehavior: Clip.none,
                  children: [
                    ClubBadge(club: p.club, iconUrl: clubIcons[p.club], size: 40),
                    if (sel)
                      Positioned(
                        right: -6,
                        top: -6,
                        child: Container(
                          decoration: BoxDecoration(
                            color: accent,
                            shape: BoxShape.circle,
                            border: Border.all(color: scheme.surface, width: 1.5),
                          ),
                          padding: const EdgeInsets.all(1),
                          child: const Icon(Icons.check,
                              size: 12, color: Colors.white),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _lastName(p.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                PositionPill(pos: p.position),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _lastName(String name) {
    final parts = name.trim().split(' ');
    return parts.length > 1 ? parts.last : name;
  }
}

class _OffersTab extends ConsumerWidget {
  const _OffersTab({required this.league});

  final FantasyLeague league;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trades = ref.watch(leagueTradesProvider(league.id)).valueOrNull ??
        const <TradeOffer>[];

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

    // Dieselbe Karte wie im Chat (holt Angebot + Positionen selbst).
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 6),
      children: [
        for (final t in sorted) TradeCard(tradeId: t.id, inList: true),
      ],
    );
  }
}

/// Wiederverwendbare Trade-Karte (Chat & „Angebote"-Tab): lädt Angebot +
/// Positionen selbst und zeigt Status; der Empfänger kann annehmen/ablehnen/
/// kontern, der Absender zurückziehen. [inList] = volle Breite (Listen-Kontext)
/// statt Sprechblasen-Breite (Chat).
class TradeCard extends ConsumerWidget {
  const TradeCard({super.key, required this.tradeId, this.inList = false});

  final String tradeId;
  final bool inList;

  Future<void> _respond(
      BuildContext context, WidgetRef ref, TradeOffer trade, bool accept) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(fantasyLeagueRepositoryProvider)
          .respondTrade(tradeId, accept);
      ref.invalidate(tradeDetailProvider(tradeId));
      ref.invalidate(leagueTradesProvider(trade.leagueId));
      messenger.showSnackBar(SnackBar(
          content: Text(accept ? 'Trade angenommen.' : 'Angebot abgelehnt.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Fehlgeschlagen: $e')));
    }
  }

  Future<void> _cancel(
      BuildContext context, WidgetRef ref, TradeOffer trade) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(fantasyLeagueRepositoryProvider).cancelTrade(tradeId);
      ref.invalidate(tradeDetailProvider(tradeId));
      ref.invalidate(leagueTradesProvider(trade.leagueId));
      messenger.showSnackBar(
          const SnackBar(content: Text('Angebot zurückgezogen.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Fehlgeschlagen: $e')));
    }
  }

  /// Gegenangebot: den Trade-Compose mit vertauschter Vorauswahl öffnen.
  void _counter(BuildContext context, WidgetRef ref, TradeOffer trade,
      List<TradeItem> items) {
    final league = ref.read(draftLeagueProvider(trade.leagueId)).valueOrNull;
    final managers =
        ref.read(fantasyManagersProvider(trade.leagueId)).valueOrNull ??
            const <FantasyManager>[];
    FantasyManager? sender;
    for (final m in managers) {
      if (m.userId == trade.fromManager) {
        sender = m;
        break;
      }
    }
    if (league == null || sender == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kontern gerade nicht möglich.')));
      return;
    }
    final myGive = {
      for (final it in items)
        if (it.giver == trade.toManager) it.playerId
    };
    final theirGive = {
      for (final it in items)
        if (it.giver == trade.fromManager) it.playerId
    };
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TradeComposeScreen(
        league: league,
        partner: sender!,
        initialOffer: myGive,
        initialRequest: theirGive,
        counterOf: trade.id,
      ),
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final myId = ref.watch(currentUserProvider)?.id;
    final detailAsync = ref.watch(tradeDetailProvider(tradeId));
    final pool =
        ref.watch(playerPoolProvider).valueOrNull ?? const <FantasyPlayer>[];
    final nameById = {for (final p in pool) p.id: p.name};

    return detailAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => const SizedBox.shrink(),
      data: (d) {
        if (d == null) {
          return _shell(context,
              child: Text('Angebot nicht mehr verfügbar.',
                  style: TextStyle(color: scheme.onSurfaceVariant)));
        }
        final trade = d.trade;
        final offered = [
          for (final it in d.items)
            if (it.giver == trade.fromManager)
              nameById[it.playerId] ?? it.playerId
        ];
        final requested = [
          for (final it in d.items)
            if (it.giver == trade.toManager)
              nameById[it.playerId] ?? it.playerId
        ];
        final incoming = trade.toManager == myId;
        // Liga (Name + fürs Kontern) & Manager laden.
        final leagueName =
            ref.watch(draftLeagueProvider(trade.leagueId)).valueOrNull?.name;
        ref.watch(fantasyManagersProvider(trade.leagueId));

        return _shell(
          context,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.swap_horiz, size: 18, color: scheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Trade-Angebot',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        if (leagueName != null)
                          Text(leagueName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  _statusChip(context, trade.status),
                ],
              ),
              const SizedBox(height: 8),
              _line(context, 'Du bekommst',
                  incoming ? offered : requested, scheme.primary),
              const SizedBox(height: 2),
              _line(context, 'Du gibst',
                  incoming ? requested : offered, scheme.tertiary),
              if (trade.message != null && trade.message!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('„${trade.message}"',
                    style: TextStyle(
                        fontStyle: FontStyle.italic,
                        color: scheme.onSurfaceVariant)),
              ],
              if (trade.status.isPending && incoming) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: scheme.error,
                          side: BorderSide(
                              color: scheme.error.withValues(alpha: 0.5)),
                        ),
                        onPressed: () => _respond(context, ref, trade, false),
                        child: const Text('Ablehnen'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => _respond(context, ref, trade, true),
                        child: const Text('Annehmen'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _counter(context, ref, trade, d.items),
                    icon: const Icon(Icons.swap_calls, size: 18),
                    label: const Text('Kontern'),
                  ),
                ),
              ] else if (trade.status.isPending) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text('Warten auf Antwort …',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant)),
                    const Spacer(),
                    TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: scheme.error),
                      onPressed: () => _cancel(context, ref, trade),
                      icon: const Icon(Icons.undo, size: 18),
                      label: const Text('Zurückziehen'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _shell(BuildContext context, {required Widget child}) {
    final scheme = Theme.of(context).colorScheme;
    final card = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.25)),
      ),
      child: child,
    );
    if (inList) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: card,
      );
    }
    return Container(
      constraints:
          BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
      margin: const EdgeInsets.only(top: 2, bottom: 6, left: 4, right: 4),
      child: card,
    );
  }

  Widget _line(
      BuildContext context, String label, List<String> players, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 82,
          child: Text(label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
        Expanded(
          child: Text(players.isEmpty ? '—' : players.join(', '),
              style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  Widget _statusChip(BuildContext context, TradeStatus status) {
    final scheme = Theme.of(context).colorScheme;
    final (Color bg, Color fg) = switch (status) {
      TradeStatus.pending => (scheme.secondaryContainer, scheme.onSecondaryContainer),
      TradeStatus.accepted => (scheme.primaryContainer, scheme.onPrimaryContainer),
      TradeStatus.rejected => (scheme.errorContainer, scheme.onErrorContainer),
      TradeStatus.cancelled => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
      TradeStatus.countered => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Text(status.label,
          style:
              TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}
