import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/app_avatar.dart';
import '../../auth/providers.dart';
import '../../messaging/providers.dart';
import '../../messaging/ui/conversation_screen.dart';
import '../logic/playoff.dart';
import '../models/fantasy_models.dart';
import '../models/trade.dart';
import '../providers.dart';
import 'club_badge.dart';
import 'spieler_kachel.dart';
import '../../../app/widgets/segmented_tab_bar.dart';

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
    final openReceived = trades
        .where((t) => t.status.isPending && t.toManager == myId)
        .length;
    final openSent = trades
        .where((t) => t.status.isPending && t.fromManager == myId)
        .length;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Trade'),
          bottom: SegmentedTabBar(
            scrollable: true,
            tabs: [
              const Tab(text: 'Neuer Trade'),
              Tab(
                  text: openReceived > 0
                      ? 'Empfangen ($openReceived)'
                      : 'Empfangen'),
              Tab(text: openSent > 0 ? 'Gesendet ($openSent)' : 'Gesendet'),
              const Tab(text: 'Historie'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _PartnerList(league: league),
            _ActiveOffers(league: league, incoming: true),
            _ActiveOffers(league: league, incoming: false),
            _TradeHistory(league: league),
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
    final scheme = Theme.of(context).colorScheme;
    final myId = ref.watch(currentUserProvider)?.id;
    final managersAsync = ref.watch(fantasyManagersProvider(league.id));
    final currentRound = ref.watch(fantasyCurrentRoundProvider).valueOrNull;
    final closed = _tradesClosed(league, currentRound);
    final pool = ref.watch(playerPoolProvider).valueOrNull ??
        const <FantasyPlayer>[];
    final roster = ref.watch(leagueRosterProvider(league.id)).valueOrNull ??
        const <RosterEntry>[];
    final clubIcons =
        ref.watch(clubIconsProvider).valueOrNull ?? const <String, String?>{};

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
        final byId = {for (final p in pool) p.id: p};
        List<FantasyPlayer> playersOf(String uid) => [
              for (final r in roster)
                if (r.managerId == uid && byId[r.playerId] != null)
                  byId[r.playerId]!
            ]..sort((a, b) => a.position.index != b.position.index
                ? a.position.index.compareTo(b.position.index)
                : a.name.compareTo(b.name));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (closed)
              Card(
                color: scheme.errorContainer,
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('Die Trade-Deadline ist überschritten — '
                      'neue Angebote sind nicht mehr möglich.'),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Text(
                'Mit wem möchtest du traden? Tippe auf einen Kader.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            // Alle Teilnehmer-Kader nebeneinander (horizontal scrollbar).
            Expanded(
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(6, 2, 6, 10),
                itemCount: others.length,
                itemBuilder: (context, i) {
                  final m = others[i];
                  return _ParticipantColumn(
                    manager: m,
                    players: playersOf(m.userId),
                    clubIcons: clubIcons,
                    enabled: !closed,
                    onOpen: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) =>
                            TradeComposeScreen(league: league, partner: m))),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Eine kompakte Kader-Spalte eines Teilnehmers auf dem Auswahl-Screen.
/// Kopf und „Traden"-Button öffnen den Trade mit dieser Person.
class _ParticipantColumn extends StatelessWidget {
  const _ParticipantColumn({
    required this.manager,
    required this.players,
    required this.clubIcons,
    required this.enabled,
    required this.onOpen,
  });

  final FantasyManager manager;
  final List<FantasyPlayer> players;
  final Map<String, String?> clubIcons;
  final bool enabled;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 188,
      margin: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Kopf: Avatar + Name (tippbar → Trade).
          InkWell(
            onTap: enabled ? onOpen : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
              child: Column(
                children: [
                  AppAvatar(
                    imageUrl: manager.avatarUrl,
                    emoji: manager.avatarEmoji,
                    colorHex: manager.avatarColor,
                    fallbackText: manager.display,
                    size: 44,
                  ),
                  const SizedBox(height: 6),
                  Text(manager.display,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('${players.length} Spieler',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: players.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('Kein Kader', textAlign: TextAlign.center),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: players.length,
                    itemBuilder: (context, i) => _miniTile(context, players[i]),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: enabled ? onOpen : null,
                child: const Text('Traden'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniTile(BuildContext context, FantasyPlayer p) {
    final base = positionColor(p.position);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 26,
            decoration: BoxDecoration(
                color: base, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 6),
          ClubBadge(club: p.club, iconUrl: clubIcons[p.club], size: 20),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(_shortName(p.name),
                      maxLines: 1,
                      softWrap: false,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700)),
                ),
                Text(p.position.label,
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                        color: base)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _shortName(String full) {
    final parts = full.trim().split(RegExp(r'\s+'));
    if (parts.length < 2 || parts.first.isEmpty) return full;
    return '${parts.first[0]}. ${parts.sublist(1).join(' ')}';
  }
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
    Map<String, String?> clubIcons,
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
        clubIcons: clubIcons,
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
      appBar: AppBar(
        centerTitle: true,
        // Zweizeilig wie in den Fantasy-Einstellungen: oben, was der Schirm
        // ist, darunter, worauf er sich bezieht.
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Neuer Trade'),
            Text(
              'mit ${widget.partner.display}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
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
              // Was ist der Tausch? Steht jetzt oben und bleibt stehen.
              _Geschaeft(
                  gebe: offerSel, bekomme: requestSel, clubIcons: clubIcons),
              // Kapitelmarken statt farbiger Kopfkästen — dieselbe Gliederung
              // wie auf dem Startbildschirm.
              Row(
                children: [
                  Expanded(
                    child: _Spaltenmarke(
                        wort: 'Du gibst',
                        anzahl: _offer.length,
                        farbe: scheme.primary),
                  ),
                  Expanded(
                    child: _Spaltenmarke(
                        wort: widget.partner.display,
                        anzahl: _request.length,
                        farbe: scheme.tertiary),
                  ),
                ],
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _RosterColumn(
                        players: mine,
                        selected: _offer,
                        clubIcons: clubIcons,
                        onToggle: (id) => setState(() =>
                            _offer.contains(id) ? _offer.remove(id) : _offer.add(id)),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: _RosterColumn(
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
                          ? () => _confirmAndSend(
                              context, offerSel, requestSel, clubIcons)
                          : null,
                      icon: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.arrow_forward),
                      // Die Zahlen standen hier, weil der Tausch sonst
                      // nirgends zusammengefasst war. Das tut jetzt der Kopf.
                      label: Text(_sending ? 'Sende …' : 'Angebot senden'),
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
    required this.clubIcons,
  });

  final String partnerName;
  final List<FantasyPlayer> offer;
  final List<FantasyPlayer> request;
  final TextEditingController messageController;
  final Map<String, String?> clubIcons;

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
            // Dieselbe Karte wie in der Auswahl und in der Angebotskarte.
            // Vorher standen hier Pillen mit Namen — damit sah derselbe Trade
            // auf drei Schirmen dreimal anders aus.
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in players)
                  SpielerKachel(
                    spieler: p,
                    iconUrl: clubIcons[p.club],
                    hervor: true,
                    mitHaken: false,
                    hoehe: 46,
                    breite: 152,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Kapitelmarke über einer Kaderspalte: farbiger Strich, Wort, Haarlinie bis
/// an den Rand — dieselbe Gliederung wie auf dem Startbildschirm und im
/// Live-Tab. Rechts steht die Anzahl, aber **nur wenn etwas gewählt ist**:
/// „0 gewählt" ist eine Meldung über nichts.
class _Spaltenmarke extends StatelessWidget {
  const _Spaltenmarke(
      {required this.wort, required this.anzahl, required this.farbe});

  final String wort;
  final int anzahl;
  final Color farbe;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
      child: Row(
        children: [
          Container(width: 3, height: 12, color: farbe),
          const SizedBox(width: 6),
          Flexible(
            flex: 0,
            child: Text(
              wort.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
                color: scheme.onSurface,
              ),
            ),
          ),
          if (anzahl > 0) ...[
            const SizedBox(width: 6),
            Text('$anzahl',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: farbe)),
          ],
          const SizedBox(width: 8),
          Expanded(child: Container(height: 1, color: scheme.outlineVariant)),
        ],
      ),
    );
  }
}

/// Der Kopf, der sagt, **was der Tausch ist**.
///
/// Vorher stand das nirgends: Die Auswahl lag verstreut in zwei scrollenden
/// Spalten, und zusammengefasst wurde sie einzig als Zahlenpaar im
/// Absende-Knopf („1 ↔ 2"). Wer zwei Bildschirmhöhen weit gescrollt hatte,
/// wusste nicht mehr, was er eigentlich anbietet.
///
/// Bleibt oben stehen, zeigt beide Seiten mit denselben Wappen wie die
/// Kacheln, und sagt bei leerer Auswahl, was zu tun ist — statt leer zu sein.
class _Geschaeft extends StatelessWidget {
  const _Geschaeft({
    required this.gebe,
    required this.bekomme,
    required this.clubIcons,
  });

  final List<FantasyPlayer> gebe;
  final List<FantasyPlayer> bekomme;
  final Map<String, String?> clubIcons;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (gebe.isEmpty && bekomme.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
        child: Row(
          children: [
            Icon(Icons.touch_app_outlined,
                size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Spieler antippen — aus deinem Kader und aus seinem.',
                style: TextStyle(
                    fontSize: 12.5, color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: _seite(context, gebe, scheme.primary, links: true)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Icon(Icons.swap_horiz,
                size: 18, color: scheme.onSurfaceVariant),
          ),
          Expanded(
              child: _seite(context, bekomme, scheme.tertiary, links: false)),
        ],
      ),
    );
  }

  Widget _seite(BuildContext context, List<FantasyPlayer> spieler, Color farbe,
      {required bool links}) {
    final scheme = Theme.of(context).colorScheme;
    if (spieler.isEmpty) {
      return Text('nichts',
          textAlign: links ? TextAlign.start : TextAlign.end,
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant));
    }
    return Wrap(
      alignment: links ? WrapAlignment.start : WrapAlignment.end,
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final p in spieler)
          Container(
            padding: const EdgeInsets.fromLTRB(3, 2, 7, 2),
            decoration: BoxDecoration(
              color: positionColor(p.position).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClubBadge(
                    club: p.club, iconUrl: clubIcons[p.club], size: 16),
                const SizedBox(width: 5),
                Text(SpielerKachel.kurzerName(p.name),
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface)),
              ],
            ),
          ),
      ],
    );
  }
}

class _RosterColumn extends StatelessWidget {
  const _RosterColumn({
    required this.players,
    required this.selected,
    required this.clubIcons,
    required this.onToggle,
  });

  final List<FantasyPlayer> players;
  final Set<String> selected;
  final Map<String, String?> clubIcons;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (players.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Kein Kader',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant)),
        ),
      );
    }
    // Der farbige Kopfkasten ist raus — er steht jetzt als Kapitelmarke über
    // beiden Spalten (siehe `_Spaltenmarke`). Zwei getönte Kästen mit Rahmen
    // und Zähler darin waren das Lauteste auf einem Schirm, dessen Inhalt die
    // Spielerkarten sind.
    return ListView.builder(
      padding: const EdgeInsets.only(top: 2, bottom: 8),
      itemCount: players.length,
      itemBuilder: (context, i) {
        final p = players[i];
        return _tile(context, p, selected.contains(p.id));
      },
    );
  }

  Widget _tile(BuildContext context, FantasyPlayer p, bool sel) {
    // Dieselbe Karte wie in der Angebotsansicht — herausgeloest nach
    // spieler_kachel.dart, damit beide Stellen nicht auseinanderlaufen.
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: SpielerKachel(
        spieler: p,
        iconUrl: clubIcons[p.club],
        hervor: sel,
        onTap: () => onToggle(p.id),
      ),
    );
  }

}

/// Offene Angebote einer Richtung: [incoming] true = an mich gerichtet
/// („Empfangen"), false = von mir gestellt („Gesendet"). Zeigt nur noch
/// laufende (pending) Angebote — abgeschlossene stehen in der Historie.
class _ActiveOffers extends ConsumerWidget {
  const _ActiveOffers({required this.league, required this.incoming});

  final FantasyLeague league;
  final bool incoming;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myId = ref.watch(currentUserProvider)?.id;
    final trades = ref.watch(leagueTradesProvider(league.id)).valueOrNull ??
        const <TradeOffer>[];
    final list = trades
        .where((t) =>
            t.status.isPending &&
            (incoming ? t.toManager == myId : t.fromManager == myId))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (list.isEmpty) {
      return _EmptyState(
        icon: incoming ? Icons.call_received : Icons.call_made,
        text: incoming
            ? 'Keine offenen empfangenen Angebote.'
            : 'Keine offenen gesendeten Angebote.',
      );
    }

    // Dieselbe Karte wie im Chat (holt Angebot + Positionen selbst).
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [for (final t in list) TradeCard(tradeId: t.id, inList: true)],
    );
  }
}

/// Trade-Historie: alle abgeschlossenen Angebote (angenommen, abgelehnt,
/// zurückgezogen, gekontert) beider Richtungen, neueste zuerst.
class _TradeHistory extends ConsumerWidget {
  const _TradeHistory({required this.league});

  final FantasyLeague league;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trades = ref.watch(leagueTradesProvider(league.id)).valueOrNull ??
        const <TradeOffer>[];
    final list = trades.where((t) => !t.status.isPending).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (list.isEmpty) {
      return const _EmptyState(
        icon: Icons.history,
        text: 'Noch keine abgeschlossenen Trades.',
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [for (final t in list) TradeCard(tradeId: t.id, inList: true)],
    );
  }
}

/// Leerer Zustand eines Angebote-Tabs (Icon + Hinweis, mittig).
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
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
    final playerById = {for (final p in pool) p.id: p};
    final clubIcons =
        ref.watch(clubIconsProvider).valueOrNull ?? const <String, String?>{};

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
        // Die Positionen als Paar (ID, Spieler) — der Spieler kann fehlen,
        // wenn der lokale Pool ihn nicht kennt. Dann zeigt die Karte die ID
        // statt ihn wegzulassen: „nicht gefunden" ist ein eigener Zustand,
        // nicht dasselbe wie „nichts dabei".
        final offered = [
          for (final it in d.items)
            if (it.giver == trade.fromManager)
              (it.playerId, playerById[it.playerId])
        ];
        final requested = [
          for (final it in d.items)
            if (it.giver == trade.toManager)
              (it.playerId, playerById[it.playerId])
        ];
        final incoming = trade.toManager == myId;
        // Liga (Name + fürs Kontern) & Manager laden.
        final leagueName =
            ref.watch(draftLeagueProvider(trade.leagueId)).valueOrNull?.name;
        ref.watch(fantasyManagersProvider(trade.leagueId));

        return _shell(
          context,
          // Nur ein eingehendes, offenes Angebot will etwas von mir.
          betont: incoming && trade.status.isPending,
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
              _seite(context, 'Du bekommst',
                  incoming ? offered : requested, clubIcons, scheme.primary),
              const SizedBox(height: 8),
              _seite(context, 'Du gibst',
                  incoming ? requested : offered, clubIcons, scheme.tertiary),
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

  /// Die Fläche um das Angebot.
  ///
  /// Vorher: `surfaceContainerHighest` auf 60 % Deckung — eine milchige
  /// Schicht, die weder Fläche noch nichts war — und ein **grüner Rahmen auf
  /// jeder Karte**, auch bei einem Angebot, das nur auf Antwort wartet. Grün
  /// heißt in dieser App „hier läuft etwas"; auf jeder Karte gesetzt sagt es
  /// gar nichts mehr.
  ///
  /// Jetzt der volle Kartengrund und eine Haarlinie. Farbe bekommt nur, was
  /// **von mir etwas will**: Ein eingehendes, offenes Angebot trägt einen
  /// Hauch aus der Ecke und eine getönte Kante ([betont]) — dasselbe Muster
  /// wie bei den Ligakarten und im MatchUp-Kasten.
  Widget _shell(BuildContext context,
      {required Widget child, bool betont = false}) {
    final scheme = Theme.of(context).colorScheme;
    final grund = Theme.of(context).cardColor;
    final card = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: grund,
        gradient: betont
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                stops: const [0.0, 0.75],
                colors: [
                  Color.alphaBlend(
                      scheme.primary.withValues(alpha: 0.12), grund),
                  grund,
                ],
              )
            : null,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: betont
              ? scheme.primary.withValues(alpha: 0.45)
              : Theme.of(context).dividerColor,
        ),
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

  /// Eine Seite des Angebots: Marke plus die Spielerkarten darunter.
  ///
  /// Vorher stand hier eine Komma-Liste von Namen („J. Urbig, S. Kolo Muani").
  /// Dieselbe Auskunft, aber ohne Verein, ohne Position und ohne
  /// Wiedererkennung — wer ein Angebot beurteilen soll, schaut auf Spieler,
  /// nicht auf einen Satz. Jetzt dieselbe [SpielerKachel] wie in der Auswahl,
  /// nur kompakter und ohne Häkchen: Im Angebot ist die Karte der Inhalt, kein
  /// getroffener Haken.
  Widget _seite(
    BuildContext context,
    String label,
    List<(String, FantasyPlayer?)> spieler,
    Map<String, String?> clubIcons,
    Color farbe,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 3, height: 11, color: farbe),
            const SizedBox(width: 6),
            Text(
              label.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (spieler.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 9),
            child: Text('—',
                style: TextStyle(color: scheme.onSurfaceVariant)),
          )
        else
          // Nebeneinander statt untereinander, mit fester Breite: Über die
          // volle Kartenbreite gezogen wirkten die Kacheln viel zu groß für
          // das bisschen, was sie tragen (Name und Position).
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (id, p) in spieler)
                if (p == null)
                  // Unbekannter Spieler: Der lokale Pool kennt ihn nicht (der
                  // Zugang kam per sync-squads nach dem App-Start). Ihn
                  // wegzulassen hieße, ein Angebot falsch darzustellen.
                  Text(id,
                      style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic))
                else
                  SpielerKachel(
                    spieler: p,
                    iconUrl: clubIcons[p.club],
                    hervor: true,
                    mitHaken: false,
                    hoehe: 46,
                    breite: 152,
                  ),
            ],
          ),
      ],
    );
  }

  /// Der Zustand als Chip.
  ///
  /// **„Offen" ist farblos.** Es ist kein Ergebnis, sondern der Normalfall —
  /// jedes Angebot, das man sieht, ist erst einmal offen. Vorher zog es
  /// `secondaryContainer`, und genau daraus wird beim grünen Seed dieser App
  /// das stumpfe Oliv, wegen dem hier auch keine `ChoiceChip`s stehen
  /// (siehe CLAUDE.md). Farbe tragen nur die **Ausgänge**: angenommen grün,
  /// abgelehnt rot, gekontert gold. Zurückgezogen bleibt ebenfalls neutral —
  /// auch das ist kein Ergebnis, sondern ein Abbruch.
  Widget _statusChip(BuildContext context, TradeStatus status) {
    final scheme = Theme.of(context).colorScheme;
    final Color? ton = switch (status) {
      TradeStatus.pending => null,
      TradeStatus.cancelled => null,
      TradeStatus.accepted => scheme.primary,
      TradeStatus.rejected => scheme.error,
      TradeStatus.countered => scheme.tertiary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: ton?.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: ton == null
            ? Border.all(color: Theme.of(context).dividerColor)
            : null,
      ),
      child: Text(status.label,
          style: TextStyle(
              color: ton ?? scheme.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w700)),
    );
  }
}
