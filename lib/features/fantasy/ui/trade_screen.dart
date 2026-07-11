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
                  leading: CircleAvatar(child: Text(_initial(m.display))),
                  title: Text(m.display),
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
              partnerName: widget.partner.display,
            )));
  }

  /// Zeigt das finale Angebot zur Bestätigung (inkl. optionaler Nachricht) und
  /// sendet erst nach Bestätigung.
  Future<void> _confirmAndSend(
    BuildContext context,
    List<FantasyPlayer> offer,
    List<FantasyPlayer> request,
  ) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ConfirmOfferSheet(
        partnerName: widget.partner.display,
        offer: offer,
        request: request,
        messageController: _msgCtrl,
      ),
    );
    if (confirmed == true) await _send();
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
      appBar: AppBar(title: Text('Trade mit ${widget.partner.display}')),
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
          final offerSel = mine.where((p) => _offer.contains(p.id)).toList();
          final requestSel =
              theirs.where((p) => _request.contains(p.id)).toList();
          final canSend =
              (_offer.isNotEmpty || _request.isNotEmpty) && !_sending;

          return Column(
            children: [
              const SizedBox(height: 4),
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
                        title: '${widget.partner.display} gibt',
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
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: canSend
                          ? () => _confirmAndSend(context, offerSel, requestSel)
                          : null,
                      icon: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.arrow_forward),
                      label: Text(_sending
                          ? 'Sende …'
                          : 'Angebot senden (${_offer.length} ↔ ${_request.length})'),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Bestätigungs-Sheet vor dem Absenden: zeigt das finale Angebot beidseitig
/// und enthält das optionale Nachrichtenfeld.
class _ConfirmOfferSheet extends StatelessWidget {
  const _ConfirmOfferSheet({
    required this.partnerName,
    required this.offer,
    required this.request,
    required this.messageController,
  });

  final String partnerName;
  final List<FantasyPlayer> offer;
  final List<FantasyPlayer> request;
  final TextEditingController messageController;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Angebot bestätigen',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
            _side(context, 'Du gibst', offer, scheme.primary),
            const SizedBox(height: 8),
            Icon(Icons.swap_vert, color: scheme.onSurfaceVariant),
            const SizedBox(height: 8),
            _side(context, '$partnerName gibt', request, scheme.tertiary),
            const SizedBox(height: 16),
            TextField(
              controller: messageController,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Nachricht (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Abbrechen'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(true),
                    icon: const Icon(Icons.send),
                    label: const Text('Senden'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _side(BuildContext context, String title,
      List<FantasyPlayer> players, Color color) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 8),
          if (players.isEmpty)
            Text('—', style: TextStyle(color: scheme.onSurfaceVariant))
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in players)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PositionPill(pos: p.position),
                        const SizedBox(width: 6),
                        Text(p.name, style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
              ],
            ),
        ],
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
    final selCount = players.where((p) => selected.contains(p.id)).length;
    final onAccent =
        accent.computeLuminance() > 0.5 ? Colors.black : Colors.white;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent.withValues(alpha: 0.24),
                  accent.withValues(alpha: 0.10),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: accent.withValues(alpha: 0.55)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: accent),
                ),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                    color: selCount > 0
                        ? accent
                        : accent.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$selCount ausgewählt',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: selCount > 0 ? onAccent : accent,
                    ),
                  ),
                ),
              ],
            ),
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
    final base = positionColor(p.position);
    // Lesbare Textfarbe: auf Gelb (ABW) schwarz, sonst weiß.
    final fg = p.position == PlayerPosition.def ? Colors.black : Colors.white;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Material(
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onToggle(p.id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 110,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              // Diagonaler Verlauf der Positionsfarbe für „Sticker"-Optik.
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(base, Colors.white, 0.14)!,
                  base,
                  Color.lerp(base, Colors.black, 0.36)!,
                ],
              ),
              border: Border.all(
                color: sel ? Colors.white : Colors.white.withValues(alpha: 0.10),
                width: sel ? 3 : 1,
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Wappen groß, ragt zur Hälfte über den rechten Kartenrand.
                Positioned(
                  right: -52,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: ClubBadge(
                        club: p.club, iconUrl: clubIcons[p.club], size: 108),
                  ),
                ),
                // Name (groß) + Position links, linksbündig.
                Positioned(
                  left: 10,
                  right: 60,
                  top: 0,
                  bottom: 0,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Lange Namen schrumpfen, statt abgeschnitten zu werden.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _shortName(p.name),
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            height: 1.05,
                            color: fg,
                            shadows: p.position == PlayerPosition.def
                                ? null
                                : const [
                                    Shadow(color: Colors.black38, blurRadius: 3)
                                  ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        p.position.label,
                        textAlign: TextAlign.start,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: fg.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
                // Nicht gewählte Karten deutlich abdunkeln (inaktiv-Look).
                if (!sel)
                  Positioned.fill(
                    child: const ColoredBox(color: Colors.black54),
                  ),
                // Gewählt: klares Häkchen-Badge oben links.
                if (sel)
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 4),
                        ],
                      ),
                      padding: const EdgeInsets.all(3),
                      child: Icon(Icons.check_rounded,
                          size: 18, color: base, weight: 900),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Vorname auf einen Buchstaben kürzen: „Jonas Urbig" → „J. Urbig".
  static String _shortName(String full) {
    final parts = full.trim().split(RegExp(r'\s+'));
    if (parts.length < 2 || parts.first.isEmpty) return full;
    return '${parts.first[0]}. ${parts.sublist(1).join(' ')}';
  }
}

class _OffersTab extends ConsumerWidget {
  const _OffersTab({required this.league});

  final FantasyLeague league;

  /// Offene zuerst, dann nach Datum absteigend.
  static List<TradeOffer> _sorted(Iterable<TradeOffer> trades) =>
      [...trades]..sort((a, b) {
          if (a.status.isPending != b.status.isPending) {
            return a.status.isPending ? -1 : 1;
          }
          return b.createdAt.compareTo(a.createdAt);
        });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myId = ref.watch(currentUserProvider)?.id;
    final trades = ref.watch(leagueTradesProvider(league.id)).valueOrNull ??
        const <TradeOffer>[];

    if (trades.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Noch keine Trade-Angebote.', textAlign: TextAlign.center),
        ),
      );
    }

    final received =
        _sorted(trades.where((t) => t.toManager == myId));
    final sent = _sorted(trades.where((t) => t.fromManager == myId));

    int openOf(List<TradeOffer> l) =>
        l.where((t) => t.status.isPending).length;

    // Dieselbe Karte wie im Chat (holt Angebot + Positionen selbst).
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      children: [
        _OffersSection(
          title: 'Empfangen',
          icon: Icons.call_received,
          openCount: openOf(received),
          trades: received,
          emptyHint: 'Keine empfangenen Angebote.',
        ),
        _OffersSection(
          title: 'Gesendet',
          icon: Icons.call_made,
          openCount: openOf(sent),
          trades: sent,
          emptyHint: 'Keine gesendeten Angebote.',
        ),
      ],
    );
  }
}

/// Ein Abschnitt der Angebote-Liste („Empfangen" bzw. „Gesendet") mit
/// Überschrift, Zähler offener Angebote und den Trade-Karten.
class _OffersSection extends StatelessWidget {
  const _OffersSection({
    required this.title,
    required this.icon,
    required this.openCount,
    required this.trades,
    required this.emptyHint,
  });

  final String title;
  final IconData icon;
  final int openCount;
  final List<TradeOffer> trades;
  final String emptyHint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(
            children: [
              Icon(icon, size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: scheme.onSurfaceVariant)),
              if (openCount > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF23030),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('$openCount offen',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          ),
        ),
        if (trades.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
            child: Text(emptyHint,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          )
        else
          for (final t in trades) TradeCard(tradeId: t.id, inList: true),
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
      // Trade-Positionen vor dem Invalidate lesen (für die Chat-Nachricht).
      final detail = ref.read(tradeDetailProvider(tradeId)).valueOrNull;
      await ref
          .read(fantasyLeagueRepositoryProvider)
          .respondTrade(tradeId, accept);
      // Angenommene Trades im Liga-Chat bekanntgeben, damit alle Bescheid wissen.
      if (accept && detail != null) {
        await _postTradeToChat(ref, trade, detail.items);
      }
      ref.invalidate(tradeDetailProvider(tradeId));
      ref.invalidate(leagueTradesProvider(trade.leagueId));
      messenger.showSnackBar(SnackBar(
          content: Text(accept ? 'Trade angenommen.' : 'Angebot abgelehnt.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Fehlgeschlagen: $e')));
    }
  }

  /// Postet einen angenommenen Trade in den Liga-Chat (Fehler dabei ignorieren).
  Future<void> _postTradeToChat(
      WidgetRef ref, TradeOffer trade, List<TradeItem> items) async {
    final managers =
        ref.read(fantasyManagersProvider(trade.leagueId)).valueOrNull ??
            const <FantasyManager>[];
    final nameOf = {for (final m in managers) m.userId: m.display};
    final pool =
        ref.read(playerPoolProvider).valueOrNull ?? const <FantasyPlayer>[];
    final playerName = {for (final p in pool) p.id: p.name};
    final fromName = nameOf[trade.fromManager] ?? 'Team A';
    final toName = nameOf[trade.toManager] ?? 'Team B';
    List<String> givenBy(String uid) => [
          for (final it in items)
            if (it.giver == uid) playerName[it.playerId] ?? it.playerId
        ];
    final fromGives = givenBy(trade.fromManager);
    final toGives = givenBy(trade.toManager);
    final msg = '🔄 Trade angenommen: $fromName ⇄ $toName\n'
        '$fromName gibt ab: ${fromGives.isEmpty ? '–' : fromGives.join(', ')}\n'
        '$toName gibt ab: ${toGives.isEmpty ? '–' : toGives.join(', ')}';
    try {
      await ref
          .read(fantasyLeagueRepositoryProvider)
          .sendMessage(trade.leagueId, msg);
    } catch (_) {}
  }

  Future<void> _cancel(
      BuildContext context, WidgetRef ref, TradeOffer trade) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Angebot zurückziehen?'),
        content: const Text(
            'Möchtest du dieses Trade-Angebot wirklich zurückziehen?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Zurückziehen')),
        ],
      ),
    );
    if (confirm != true) return;
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
