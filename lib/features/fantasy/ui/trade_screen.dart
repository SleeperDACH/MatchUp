import 'package:flutter/material.dart';
import '../../../core/ui/rueckfrage.dart';
import '../../../app/widgets/skelett.dart';
import '../../../app/widgets/info_knopf.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/typografie.dart';
import '../../../core/ui/app_avatar.dart';
import '../../auth/providers.dart';
import '../../messaging/providers.dart';
import '../../messaging/ui/conversation_screen.dart';
import '../logic/fantasy_scoring_engine.dart';
import '../logic/playoff.dart';
import '../logic/spieler_schnitt.dart';
import '../models/fantasy_models.dart';
import '../models/trade.dart';
import '../providers.dart';
import 'club_badge.dart';
import 'player_profile_sheet.dart';
import 'spieler_kachel.dart';
import 'meine_picks.dart';
import '../../../app/widgets/karte.dart';
import '../logic/draft_rechte.dart';
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
    final trades =
        ref.watch(leagueTradesProvider(league.id)).valueOrNull ??
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
                    : 'Empfangen',
              ),
              Tab(text: openSent > 0 ? 'Gesendet ($openSent)' : 'Gesendet'),
              const Tab(text: 'Historie'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            TradePartnerList(league: league),
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

/// **Die Partnerwahl: alle Kader nebeneinander.**
///
/// Öffentlich, weil sie an zwei Stellen gebraucht wird — als erster Reiter des
/// Trade-Schirms und über [TradePartnerScreen] aus einem Spielerprofil.
/// Vorher stand dort ein `SimpleDialog` mit einer Namensliste: dieselbe Frage,
/// zwei Antworten, und die schlechtere gewann. **Mit wem man tauscht,
/// entscheidet man an den Kadern, nicht an den Namen.**
class TradePartnerList extends ConsumerWidget {
  const TradePartnerList({super.key, required this.league, this.initialOffer});

  final FantasyLeague league;

  /// Spieler, die im Angebot schon stehen sollen — der, aus dessen Profil man
  /// hergekommen ist. Ohne ihn müsste man ihn auf dem nächsten Schirm noch
  /// einmal suchen.
  final Set<String>? initialOffer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final myId = ref.watch(currentUserProvider)?.id;
    final managersAsync = ref.watch(fantasyManagersProvider(league.id));
    final currentRound = ref.watch(fantasyCurrentRoundProvider).valueOrNull;
    final closed = _tradesClosed(league, currentRound);
    final pool =
        ref.watch(playerPoolProvider).valueOrNull ?? const <FantasyPlayer>[];
    final roster =
        ref.watch(leagueRosterProvider(league.id)).valueOrNull ??
        const <RosterEntry>[];
    final clubIcons =
        ref.watch(clubIconsProvider).valueOrNull ?? const <String, String?>{};

    return managersAsync.when(
      loading: () => const Skelett(),
      error: (e, _) => Center(child: Text('Fehler: $e')),
      data: (managers) {
        final others = managers.where((m) => m.userId != myId).toList();
        if (others.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Noch keine anderen Manager in der Liga.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final byId = {for (final p in pool) p.id: p};
        List<FantasyPlayer> playersOf(String uid) =>
            [
              for (final r in roster)
                if (r.managerId == uid && byId[r.playerId] != null)
                  byId[r.playerId]!,
            ]..sort(
              (a, b) => a.position.index != b.position.index
                  ? a.position.index.compareTo(b.position.index)
                  : a.name.compareTo(b.name),
            );

        // Ø je Spieltag nach der Wertung dieser Liga — dieselbe Zahl wie im
        // Angebot, damit man schon bei der Partnerwahl vergleichen kann.
        final stats =
            ref.watch(seasonStatsProvider).valueOrNull ??
            const <int, Map<String, PlayerMatchStats>>{};
        final schnitt = <String, double>{};
        for (final r in roster) {
          final p = byId[r.playerId];
          if (p == null) continue;
          final sp = spielerSchnitt(
            saison: stats,
            spielerId: p.id,
            position: p.position,
            regeln: league.scoring,
          );
          if (sp.hatDaten) schnitt[p.id] = sp.schnitt;
        }
        // Picks für den Reset-Draft je Team, solange die Liga einen hat.
        final slots =
            league.resetAktiv &&
                !(league.draftPhase == 'reset' &&
                    league.draftStatus == DraftStatus.done)
            ? ref.watch(resetPicksProvider(league.id))
            : null;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (closed)
              Card(
                color: scheme.errorContainer,
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text(
                    'Die Trade-Deadline ist überschritten — '
                    'neue Angebote sind nicht mehr möglich.',
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Text(
                'Mit wem möchtest du traden? Tippe auf einen Kader.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
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
                    schnitt: schnitt,
                    picks: slots == null ? null : picksVon(slots, m.userId),
                    nameVon: {for (final x in managers) x.userId: x.display},
                    onOpen: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => TradeComposeScreen(
                          league: league,
                          partner: m,
                          initialOffer: initialOffer ?? const {},
                        ),
                      ),
                    ),
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

/// Eine Kader-Spalte eines Teilnehmers auf dem Auswahl-Screen. Kopf und
/// „Traden"-Knopf öffnen den Trade mit dieser Person.
///
/// **Ruhiger seit dem 20.10.2026** (auf Ansage: „weniger Farbe, die Spieler
/// mehr im Fokus"). Vorher trug jede Zeile einen Strich und das
/// Positionswort in der Positionsfarbe — bei achtzehn Spalten ein Streifen
/// aus Blau, Gelb, Grün und Rot, und der Name war die kleinste Schrift der
/// Zeile. Jetzt gliedern graue Zwischenzeilen nach Position, der Name steht
/// in Textgröße, rechts grau der Schnitt je Spieltag. Darunter die Picks
/// für den Reset-Draft (0145), wenn die Liga einen hat.
class _ParticipantColumn extends StatelessWidget {
  const _ParticipantColumn({
    required this.manager,
    required this.players,
    required this.clubIcons,
    required this.enabled,
    required this.onOpen,
    this.schnitt = const {},
    this.picks,
    this.nameVon = const {},
  });

  /// Anzeigenamen der Manager — für erhandelte Picks („R1 · Big Bang").
  final Map<String, String> nameVon;

  final FantasyManager manager;
  final List<FantasyPlayer> players;
  final Map<String, String?> clubIcons;
  final bool enabled;
  final VoidCallback onOpen;

  /// Ø je Spieltag nach der Wertung dieser Liga.
  final Map<String, double> schnitt;

  /// Picks des Teams für den Reset-Draft; `null` = Liga ohne Reset.
  final List<PickSlot>? picks;

  static const _positionen = {
    PlayerPosition.gk: 'Tor',
    PlayerPosition.def: 'Abwehr',
    PlayerPosition.mid: 'Mittelfeld',
    PlayerPosition.fwd: 'Sturm',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final zeilen = <Widget>[];
    PlayerPosition? letzte;
    for (final p in players) {
      if (p.position != letzte) {
        letzte = p.position;
        zeilen.add(_marke(context, _positionen[p.position] ?? ''));
      }
      zeilen.add(_zeile(context, p));
    }
    if (picks != null && picks!.isNotEmpty) {
      zeilen
        ..add(_marke(context, 'Picks · Reset-Draft'))
        ..add(
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final pk in picks!)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.onSurface.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      pk.fest
                          ? pk.code
                          : pk.ursprung == manager.userId
                          ? 'R${pk.runde}'
                          : 'R${pk.runde} · ${nameVon[pk.ursprung] ?? '?'}',
                      style: const TextStyle(
                        fontSize: Schrift.label,
                        fontWeight: FontWeight.w700,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
    }

    return Container(
      width: 196,
      margin: const EdgeInsets.symmetric(horizontal: 5),
      decoration: kartenDeko(context),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Kopf: Avatar + Name (tippbar → Trade).
          InkWell(
            onTap: enabled ? onOpen : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
              child: Row(
                children: [
                  AppAvatar(
                    imageUrl: manager.avatarUrl,
                    emoji: manager.avatarEmoji,
                    colorHex: manager.avatarColor,
                    fallbackText: manager.display,
                    seed: manager.userId,
                    size: 36,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          manager.display,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: Schrift.text,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          [
                            '${players.length} Spieler',
                            if (picks != null) '${picks!.length} Picks',
                          ].join(' · '),
                          style: TextStyle(
                            fontSize: Schrift.label,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: Theme.of(context).dividerColor),
          Expanded(
            child: players.isEmpty && zeilen.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('Kein Kader', textAlign: TextAlign.center),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.only(bottom: 4),
                    children: zeilen,
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
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

  Widget _marke(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: Schrift.label,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );

  Widget _zeile(BuildContext context, FantasyPlayer p) {
    final scheme = Theme.of(context).colorScheme;
    final s = schnitt[p.id];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 5, 12, 5),
      child: Row(
        children: [
          ClubBadge(club: p.club, iconUrl: clubIcons[p.club], size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                _shortName(p.name).toUpperCase(),
                maxLines: 1,
                softWrap: false,
                style: const TextStyle(
                  fontSize: Schrift.text,
                  fontWeight: Schrift.ueberschriftGewicht,
                  fontStyle: Schrift.ueberschriftStil,
                ),
              ),
            ),
          ),
          if (s != null) ...[
            const SizedBox(width: 6),
            Text(
              formatPoints(s),
              style: TextStyle(
                fontSize: Schrift.label,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
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
    this.initialOfferPicks = const {},
    this.initialRequestPicks = const {},
    this.counterOf,
  });

  final FantasyLeague league;
  final FantasyManager partner;

  /// Vorauswahl (z. B. beim Kontern eines Angebots).
  final Set<String> initialOffer;
  final Set<String> initialRequest;

  /// Vorauswahl an Picks für den Reset-Draft (0145).
  final Set<PickKey> initialOfferPicks;
  final Set<PickKey> initialRequestPicks;

  /// ID des ursprünglichen Angebots, das hiermit gekontert (geschlossen) wird.
  final String? counterOf;

  @override
  ConsumerState<TradeComposeScreen> createState() => _TradeComposeScreenState();
}

class _TradeComposeScreenState extends ConsumerState<TradeComposeScreen> {
  late final Set<String> _offer = {...widget.initialOffer}; // ich gebe ab
  late final Set<String> _request = {...widget.initialRequest}; // ich will
  late final Set<PickKey> _offerPicks = {...widget.initialOfferPicks};
  late final Set<PickKey> _requestPicks = {...widget.initialRequestPicks};
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
      tradeId = await ref
          .read(fantasyLeagueRepositoryProvider)
          .proposeTrade(
            widget.league.id,
            widget.partner.userId,
            offerPlayers: _offer.toList(),
            requestPlayers: _request.toList(),
            offerPicks: _offerPicks.toList(),
            requestPicks: _requestPicks.toList(),
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
          .sendMessage(
            widget.partner.userId,
            'Trade-Angebot',
            tradeId: tradeId,
          );
    } catch (_) {
      // Chat-Nachricht ist optional — Trade wurde bereits gesendet.
    }

    if (!mounted) return;
    // Compose-Screen durch den Direktnachrichten-Chat ersetzen.
    navigator.pushReplacement(
      MaterialPageRoute(
        builder: (_) => ConversationScreen(
          partnerId: widget.partner.userId,
          partnerName: widget.partner.display,
        ),
      ),
    );
  }

  /// Zeigt das finale Angebot zur Bestätigung (inkl. optionaler Nachricht) und
  /// sendet erst nach Bestätigung.
  Future<void> _confirmAndSend(
    BuildContext context,
    List<FantasyPlayer> offer,
    List<FantasyPlayer> request,
    Map<String, String?> clubIcons,
    List<PickSlot> offerPicks,
    List<PickSlot> requestPicks,
    Map<String, String> nameVon,
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
        offerPicks: offerPicks,
        requestPicks: requestPicks,
        nameVon: nameVon,
      ),
    );
    if (confirmed == true) await _send();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final myId = ref.watch(currentUserProvider)?.id;
    final poolAsync = ref.watch(playerPoolProvider);
    final roster =
        ref.watch(leagueRosterProvider(widget.league.id)).valueOrNull ??
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
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      body: poolAsync.when(
        loading: () => const Skelett(),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (pool) {
          final byId = {for (final p in pool) p.id: p};
          List<FantasyPlayer> playersOf(String uid) =>
              [
                for (final r in roster)
                  if (r.managerId == uid && byId[r.playerId] != null)
                    byId[r.playerId]!,
              ]..sort(
                (a, b) => a.position.index != b.position.index
                    ? a.position.index.compareTo(b.position.index)
                    : a.name.compareTo(b.name),
              );

          final mine = myId == null ? <FantasyPlayer>[] : playersOf(myId);
          final theirs = playersOf(widget.partner.userId);
          // **Die Zahl, an der ein Angebot hängt.** Ohne sie ist der Schirm
          // eine Namensliste: Was man hergibt und was man bekommt, stand
          // nirgends — man musste jeden Spieler einzeln öffnen.
          //
          // **Der Schnitt je Spieltag, nicht die Saisonsumme.** Zwei Spieler
          // sind nur so vergleichbar: Wer erst im Winter kam oder verletzt
          // war, hat eine kleine Summe und kann trotzdem der bessere sein.
          // Das Ø vor der Zahl sagt es auch hin — sonst läse man sie als
          // Gesamtpunktzahl.
          final stats =
              ref.watch(seasonStatsProvider).valueOrNull ??
              const <int, Map<String, PlayerMatchStats>>{};
          final punkte = <String, double>{
            for (final p in [...mine, ...theirs])
              if (spielerSchnitt(
                saison: stats,
                spielerId: p.id,
                position: p.position,
                regeln: widget.league.scoring,
              ).hatDaten)
                p.id: spielerSchnitt(
                  saison: stats,
                  spielerId: p.id,
                  position: p.position,
                  regeln: widget.league.scoring,
                ).schnitt,
          };
          // **Picks für den Reset-Draft** (0145) — nur, solange sie sich
          // handeln lassen (Hinrunde einer Liga mit Reset).
          final slots = picksHandelbar(widget.league)
              ? ref.watch(resetPicksProvider(widget.league.id))
              : null;
          final nameVon = {
            for (final m
                in ref
                        .watch(fantasyManagersProvider(widget.league.id))
                        .valueOrNull ??
                    const <FantasyManager>[])
              m.userId: m.display,
          };
          final myPicks = slots == null || myId == null
              ? const <PickSlot>[]
              : picksVon(slots, myId);
          final theirPicks = slots == null
              ? const <PickSlot>[]
              : picksVon(slots, widget.partner.userId);
          final offerPickSel = myPicks
              .where((p) => _offerPicks.contains(p.key))
              .toList();
          final requestPickSel = theirPicks
              .where((p) => _requestPicks.contains(p.key))
              .toList();
          final offerSel = mine.where((p) => _offer.contains(p.id)).toList();
          final requestSel = theirs
              .where((p) => _request.contains(p.id))
              .toList();
          final canSend =
              (_offer.isNotEmpty ||
                  _request.isNotEmpty ||
                  offerPickSel.isNotEmpty ||
                  requestPickSel.isNotEmpty) &&
              !_sending;

          return Column(
            children: [
              // Was ist der Tausch? Steht jetzt oben und bleibt stehen.
              _Geschaeft(
                gebe: offerSel,
                bekomme: requestSel,
                gebePicks: offerPickSel,
                bekommePicks: requestPickSel,
                nameVon: nameVon,
                clubIcons: clubIcons,
                punkte: punkte,
              ),
              // Kapitelmarken statt farbiger Kopfkästen — dieselbe Gliederung
              // wie auf dem Startbildschirm.
              Row(
                children: [
                  Expanded(
                    child: _Spaltenmarke(
                      wort: 'Du gibst',
                      anzahl: _offer.length + offerPickSel.length,
                    ),
                  ),
                  Expanded(
                    child: _Spaltenmarke(
                      wort: widget.partner.display,
                      anzahl: _request.length + requestPickSel.length,
                    ),
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
                        picks: myPicks,
                        selectedPicks: _offerPicks,
                        nameVon: nameVon,
                        onTogglePick: (k) => setState(
                          () => _offerPicks.contains(k)
                              ? _offerPicks.remove(k)
                              : _offerPicks.add(k),
                        ),
                        clubIcons: clubIcons,
                        punkte: punkte,
                        onToggle: (id) => setState(
                          () => _offer.contains(id)
                              ? _offer.remove(id)
                              : _offer.add(id),
                        ),
                        onProfil: (p) => showPlayerProfile(
                          context,
                          league: widget.league,
                          player: p,
                          clubIcon: clubIcons[p.club],
                          isMine: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: _RosterColumn(
                        players: theirs,
                        selected: _request,
                        picks: theirPicks,
                        selectedPicks: _requestPicks,
                        nameVon: nameVon,
                        onTogglePick: (k) => setState(
                          () => _requestPicks.contains(k)
                              ? _requestPicks.remove(k)
                              : _requestPicks.add(k),
                        ),
                        clubIcons: clubIcons,
                        punkte: punkte,
                        onToggle: (id) => setState(
                          () => _request.contains(id)
                              ? _request.remove(id)
                              : _request.add(id),
                        ),
                        // Sein Spieler: kein „Droppen" im Profil, aber der
                        // Trade-Knopf — dieselbe Regel wie in jeder Liste.
                        onProfil: (p) => showPlayerProfile(
                          context,
                          league: widget.league,
                          player: p,
                          clubIcon: clubIcons[p.club],
                          isMine: false,
                        ),
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
                  child: _SendeKnopf(
                    laeuft: _sending,
                    onPressed: canSend
                        ? () => _confirmAndSend(
                            context,
                            offerSel,
                            requestSel,
                            clubIcons,
                            offerPickSel,
                            requestPickSel,
                            nameVon,
                          )
                        : null,
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
    this.offerPicks = const [],
    this.requestPicks = const [],
    this.nameVon = const {},
  });

  final String partnerName;
  final List<FantasyPlayer> offer;
  final List<FantasyPlayer> request;
  final List<PickSlot> offerPicks;
  final List<PickSlot> requestPicks;
  final Map<String, String> nameVon;
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
            Text(
              'Angebot bestätigen',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 14),
            _side(context, 'Du gibst', offer, offerPicks, scheme.primary),
            const SizedBox(height: 8),
            Icon(Icons.swap_vert, color: scheme.onSurfaceVariant),
            const SizedBox(height: 8),
            _side(
              context,
              '$partnerName gibt',
              request,
              requestPicks,
              scheme.tertiary,
            ),
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
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Senden'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _side(
    BuildContext context,
    String title,
    List<FantasyPlayer> players,
    List<PickSlot> picks,
    Color color,
  ) {
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
          Text(
            title,
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(height: 8),
          if (players.isEmpty && picks.isEmpty)
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
                for (final p in picks)
                  PickKachel(
                    runde: p.runde,
                    team: nameVon[p.ursprung] ?? '?',
                    code: p.code,
                    fest: p.fest,
                    hervor: true,
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

/// Die eigenen **vorgemerkten** Trades: angenommen, aber noch nicht vollzogen.
///
/// Erreichbar über den Kader-Tab. Der Schirm existiert, weil es zwischen
/// „abgemacht" und „vollzogen" seit Migration 0088 eine Lücke von bis zu
/// eineinhalb Tagen gibt — und wer in dieser Zeit auf seinen Kader schaut,
/// muss wissen, warum der Spieler noch da ist.
class VorgemerkteTradesScreen extends ConsumerWidget {
  const VorgemerkteTradesScreen({super.key, required this.league});

  final FantasyLeague league;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final trades = ref.watch(vorgemerkteTradesProvider(league.id));
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Offene Trades'),
            Text(
              league.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: const [
          // Warum die Kader erst später wechseln, stand als Absatz über der
          // Liste (Design-Ideen Punkt 4).
          InfoKnopf(
            titel: 'Warum erst nach dem Spieltag?',
            text:
                'Diese Trades sind beschlossen. Damit ein Tausch niemandem '
                'mitten in der Wertung einen Spieler aus der Elf nimmt, '
                'wechseln die Kader erst 12 Stunden nach dem letzten Spiel '
                'des Spieltags.',
          ),
        ],
      ),
      body: trades.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Kein Trade wartet auf Ausführung.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(top: 8, bottom: 24),
              children: [
                for (final t in trades) TradeCard(tradeId: t.id, inList: true),
              ],
            ),
    );
  }
}

/// „Der Tausch ist beschlossen, greift aber erst nach dem Spieltag."
///
/// Ein Trade mitten in der Wertung nimmt einem Manager rückwirkend einen
/// Spieler aus der laufenden Elf — genau so stand einmal jemand mit zehn
/// Spielern da. Seit Migration 0088 wird ein angenommener Trade deshalb
/// vorgemerkt. Dieser Zustand muss stehen, sonst sieht der Kader schlicht
/// falsch aus: Der Spieler ist noch da, obwohl er weg sein sollte.
class _VorgemerktHinweis extends StatelessWidget {
  const _VorgemerktHinweis({required this.freiAb});

  final DateTime? freiAb;

  static const _tage = ['Mo.', 'Di.', 'Mi.', 'Do.', 'Fr.', 'Sa.', 'So.'];

  String _zeitpunkt() {
    final t = freiAb;
    if (t == null) return 'nach dem Spieltag';
    final zz = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return 'ab ${_tage[t.weekday - 1]} $zz:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.schedule_outlined, size: 16, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Angenommen — die Spieler wechseln erst nach dem Spieltag '
              '(${_zeitpunkt()}). Bis dahin zählen sie für ihre bisherigen '
              'Teams.',
              style: TextStyle(
                fontSize: 11,
                color: scheme.onSurfaceVariant,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kapitelmarke über einer Kaderspalte: Wort, Haarlinie bis an den Rand —
/// **ohne farbigen Strich** (Design-Ideen Punkt 3, 15.10.2026: Grün und Blau
/// sagten hier nur „links" und „rechts") — dieselbe Gliederung wie auf dem Startbildschirm und im
/// Live-Tab. Rechts steht die Anzahl, aber **nur wenn etwas gewählt ist**:
/// „0 gewählt" ist eine Meldung über nichts.
class _Spaltenmarke extends StatelessWidget {
  const _Spaltenmarke({required this.wort, required this.anzahl});

  final String wort;
  final int anzahl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
      child: Row(
        children: [
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
            Text(
              '$anzahl',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: scheme.onSurfaceVariant,
              ),
            ),
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
    required this.punkte,
    this.gebePicks = const [],
    this.bekommePicks = const [],
    this.nameVon = const {},
  });

  /// Anzeigenamen — ein Pick heißt „R1 · Big Bang", nicht „Pick 1.01".
  final Map<String, String> nameVon;

  final List<FantasyPlayer> gebe;
  final List<FantasyPlayer> bekomme;
  final List<PickSlot> gebePicks;
  final List<PickSlot> bekommePicks;
  final Map<String, String?> clubIcons;

  /// Saisonpunkte je Spieler — im Kopf steht die **Summe je Seite**. Sie ist
  /// die kürzeste Antwort auf „lohnt sich das?", und sie stand hier nicht.
  final Map<String, double> punkte;

  double _summe(List<FantasyPlayer> xs) =>
      xs.fold<double>(0, (a, p) => a + (punkte[p.id] ?? 0));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // **Die Karte steht immer, auch leer.** Vorher stand an ihrer Stelle die
    // Zeile „Spieler antippen — aus deinem Kader und aus seinem". Eine
    // Anleitung, die dasteht, bis man sie befolgt hat, ist eine Zeile, die
    // niemand ein zweites Mal liest; die beiden Seiten mit „nichts" sagen
    // dasselbe, und sie sagen es auch noch, wenn erst eine Seite steht.
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
          Expanded(
            child: _seite(
              context,
              gebe,
              gebePicks,
              scheme.primary,
              links: true,
              summe: _summe(gebe),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Icon(
              Icons.swap_horiz,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
          ),
          Expanded(
            child: _seite(
              context,
              bekomme,
              bekommePicks,
              scheme.tertiary,
              links: false,
              summe: _summe(bekomme),
            ),
          ),
        ],
      ),
    );
  }

  Widget _seite(
    BuildContext context,
    List<FantasyPlayer> spieler,
    List<PickSlot> picks,
    Color farbe, {
    required bool links,
    required double summe,
  }) {
    final scheme = Theme.of(context).colorScheme;
    if (spieler.isEmpty && picks.isEmpty) {
      return Text(
        'nichts',
        textAlign: links ? TextAlign.start : TextAlign.end,
        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
      );
    }
    return Column(
      crossAxisAlignment: links
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        _kacheln(context, spieler, picks, links),
        if (spieler.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Ø ${formatPoints(summe)} Punkte',
            style: TextStyle(
              fontSize: Schrift.label,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _kacheln(
    BuildContext context,
    List<FantasyPlayer> spieler,
    List<PickSlot> picks,
    bool links,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      alignment: links ? WrapAlignment.start : WrapAlignment.end,
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final p in spieler)
          Container(
            padding: const EdgeInsets.fromLTRB(3, 2, 7, 2),
            decoration: BoxDecoration(
              // Neutral — die Position sagt das Wappen-Umfeld nicht, aber
              // eine Farbfläche je Pille sagte sie zu laut (Design-Ideen
              // Punkt 3).
              color: scheme.onSurface.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClubBadge(club: p.club, iconUrl: clubIcons[p.club], size: 16),
                const SizedBox(width: 5),
                Text(
                  SpielerKachel.kurzerName(p.name).toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: Schrift.ueberschriftGewicht,
                    fontStyle: Schrift.ueberschriftStil,
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        for (final p in picks)
          Container(
            padding: const EdgeInsets.fromLTRB(6, 3, 8, 3),
            decoration: BoxDecoration(
              color: scheme.onSurface.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.confirmation_number_outlined,
                  size: 13,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  p.fest
                      ? 'Pick ${p.code}'
                      : 'R${p.runde} · ${nameVon[p.ursprung] ?? '?'}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// **Der Knopf, der das Angebot abschickt.**
///
/// Er trug das Markengrün, das in dieser App auf sehr vielen Knöpfen steht —
/// und damit sah die einzige Entscheidung dieses Schirms aus wie jede andere
/// Schaltfläche. Jetzt ist er hell auf dunklem Grund: der stärkste Kontrast,
/// den diese Oberfläche hat, ohne eine weitere Signalfarbe einzuführen. Grün
/// heißt hier ohnehin „hier läuft etwas", und ein Angebot läuft erst, wenn es
/// abgeschickt ist.
class _SendeKnopf extends StatelessWidget {
  const _SendeKnopf({required this.laeuft, required this.onPressed});

  final bool laeuft;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final an = onPressed != null;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(
        onPressed: onPressed,

        // Farbe, Form und Schrift kommen aus dem Theme — seit der helle Knopf
        // dort steht, hat dieser Schirm keine eigene Fassung mehr.
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (laeuft)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.surface,
                ),
              )
            else
              Icon(
                Icons.send,
                size: 18,
                color: an ? scheme.surface : scheme.onSurfaceVariant,
              ),
            const SizedBox(width: 8),
            // Die Zahlen standen hier, weil der Tausch sonst nirgends
            // zusammengefasst war. Das tut jetzt der Kopf.
            Text(laeuft ? 'Sende …' : 'Angebot senden'),
          ],
        ),
      ),
    );
  }
}

class _RosterColumn extends StatelessWidget {
  const _RosterColumn({
    required this.players,
    required this.selected,
    required this.clubIcons,
    required this.onToggle,
    required this.onProfil,
    required this.punkte,
    this.picks = const [],
    this.selectedPicks = const {},
    this.onTogglePick,
    this.nameVon = const {},
  });

  final List<FantasyPlayer> players;
  final Set<String> selected;

  /// Picks für den Reset-Draft unter den Spielern (0145).
  final List<PickSlot> picks;
  final Set<PickKey> selectedPicks;
  final ValueChanged<PickKey>? onTogglePick;
  final Map<String, String> nameVon;
  final Map<String, String?> clubIcons;

  /// Saisonpunkte je Spieler, nach der Wertung dieser Liga.
  final Map<String, double> punkte;
  final ValueChanged<String> onToggle;

  /// **Der Tipp auf die Karte wählt aus** — deshalb braucht das Profil einen
  /// eigenen Knopf. Vor einem Angebot will man Leistung, Ausfallgrund und
  /// Spielplan sehen, und dieser Schirm war der einzige im Fantasy-Bereich,
  /// von dem aus es keinen Weg dorthin gab.
  final ValueChanged<FantasyPlayer> onProfil;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (players.isEmpty && picks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Kein Kader',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }
    // Der farbige Kopfkasten ist raus — er steht jetzt als Kapitelmarke über
    // beiden Spalten (siehe `_Spaltenmarke`). Zwei getönte Kästen mit Rahmen
    // und Zähler darin waren das Lauteste auf einem Schirm, dessen Inhalt die
    // Spielerkarten sind.
    return ListView.builder(
      padding: const EdgeInsets.only(top: 2, bottom: 8),
      itemCount: players.length + (picks.isEmpty ? 0 : picks.length + 1),
      itemBuilder: (context, i) {
        if (i < players.length) {
          final p = players[i];
          return _tile(context, p, selected.contains(p.id));
        }
        if (i == players.length) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(10, 14, 8, 4),
            child: Text(
              'PICKS · RESET-DRAFT',
              style: TextStyle(
                fontSize: Schrift.label,
                fontWeight: Schrift.ueberschriftGewicht,
                fontStyle: Schrift.ueberschriftStil,
                letterSpacing: 0.6,
                color: scheme.onSurfaceVariant,
              ),
            ),
          );
        }
        final pick = picks[i - players.length - 1];
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
          child: PickKachel(
            runde: pick.runde,
            team: nameVon[pick.ursprung] ?? '?',
            code: pick.code,
            fest: pick.fest,
            hervor: selectedPicks.contains(pick.key),
            onTap: onTogglePick == null ? null : () => onTogglePick!(pick.key),
          ),
        );
      },
    );
  }

  Widget _tile(BuildContext context, FantasyPlayer p, bool sel) {
    // Dieselbe Karte wie in der Angebotsansicht — herausgeloest nach
    // spieler_kachel.dart, damit beide Stellen nicht auseinanderlaufen.
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
      child: SpielerKachel(
        spieler: p,
        iconUrl: clubIcons[p.club],
        hervor: sel,
        punkte: punkte[p.id],
        onTap: () => onToggle(p.id),
        onProfil: () => onProfil(p),
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
    final trades =
        ref.watch(leagueTradesProvider(league.id)).valueOrNull ??
        const <TradeOffer>[];
    final list =
        trades
            .where(
              (t) =>
                  t.status.isPending &&
                  (incoming ? t.toManager == myId : t.fromManager == myId),
            )
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
    final trades =
        ref.watch(leagueTradesProvider(league.id)).valueOrNull ??
        const <TradeOffer>[];
    final list = trades.where((t) => !t.status.isPending).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (list.isEmpty) {
      return const _EmptyState(
        icon: Icons.history_outlined,
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
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sucht einen Manager in der Ligaliste. `null` = Liste noch nicht geladen
/// **oder** der Mann ist nicht mehr in der Liga — die Karte behandelt beides
/// gleich: Sie behauptet dann keinen Namen, statt einen falschen zu raten.
FantasyManager? managerMit(List<FantasyManager>? liste, String id) {
  if (liste == null) return null;
  for (final m in liste) {
    if (m.userId == id) return m;
  }
  return null;
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
    BuildContext context,
    WidgetRef ref,
    TradeOffer trade,
    bool accept,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(fantasyLeagueRepositoryProvider)
          .respondTrade(tradeId, accept);
      // Kein Eintrag mehr im Liga-Chat: Der Transfers-Bereich zeigt den Trade
      // mit beiden Seiten nebeneinander, und zwar auch dann noch, wenn er im
      // Chat laengst weggescrollt waere.
      ref.invalidate(tradeDetailProvider(tradeId));
      ref.invalidate(leagueTradesProvider(trade.leagueId));
      messenger.showSnackBar(
        SnackBar(
          content: Text(accept ? 'Trade angenommen.' : 'Angebot abgelehnt.'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Fehlgeschlagen: $e')));
    }
  }

  Future<void> _cancel(
    BuildContext context,
    WidgetRef ref,
    TradeOffer trade,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirm = await rueckfrage(
      context,
      titel: 'Angebot zurückziehen?',
      text: 'Möchtest du dieses Trade-Angebot wirklich zurückziehen?',
      ja: 'Zurückziehen',
      nein: 'Abbrechen',
    );
    if (confirm != true) return;
    try {
      await ref.read(fantasyLeagueRepositoryProvider).cancelTrade(tradeId);
      ref.invalidate(tradeDetailProvider(tradeId));
      ref.invalidate(leagueTradesProvider(trade.leagueId));
      messenger.showSnackBar(
        const SnackBar(content: Text('Angebot zurückgezogen.')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Fehlgeschlagen: $e')));
    }
  }

  /// Gegenangebot: den Trade-Compose mit vertauschter Vorauswahl öffnen.
  void _counter(
    BuildContext context,
    WidgetRef ref,
    TradeOffer trade,
    List<TradeItem> items,
    List<TradePick> picks,
  ) {
    final league = ref.read(draftLeagueProvider(trade.leagueId)).valueOrNull;
    final managers = ref
        .read(fantasyManagersProvider(trade.leagueId))
        .valueOrNull;
    final sender = managerMit(managers, trade.fromManager);
    if (league == null || sender == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kontern gerade nicht möglich.')),
      );
      return;
    }
    final myGive = {
      for (final it in items)
        if (it.giver == trade.toManager) it.playerId,
    };
    final theirGive = {
      for (final it in items)
        if (it.giver == trade.fromManager) it.playerId,
    };
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TradeComposeScreen(
          league: league,
          partner: sender,
          initialOffer: myGive,
          initialRequest: theirGive,
          initialOfferPicks: {
            for (final p in picks)
              if (p.giver == trade.toManager) p.key,
          },
          initialRequestPicks: {
            for (final p in picks)
              if (p.giver == trade.fromManager) p.key,
          },
          counterOf: trade.id,
        ),
      ),
    );
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
          return _shell(
            context,
            child: Text(
              'Angebot nicht mehr verfügbar.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          );
        }
        final trade = d.trade;
        // Die Positionen als Paar (ID, Spieler) — der Spieler kann fehlen,
        // wenn der lokale Pool ihn nicht kennt. Dann zeigt die Karte die ID
        // statt ihn wegzulassen: „nicht gefunden" ist ein eigener Zustand,
        // nicht dasselbe wie „nichts dabei".
        final offered = [
          for (final it in d.items)
            if (it.giver == trade.fromManager)
              (it.playerId, playerById[it.playerId]),
        ];
        final requested = [
          for (final it in d.items)
            if (it.giver == trade.toManager)
              (it.playerId, playerById[it.playerId]),
        ];
        final incoming = trade.toManager == myId;
        // Picks für den Reset-Draft (0145) mit ihrer Nummer nach der
        // aktuellen Tabelle, soweit sie schon berechnet ist.
        final slots = ref.watch(resetPicksProvider(trade.leagueId));
        final codeVon = {
          for (final s in slots ?? const <PickSlot>[]) s.key: s.code,
        };
        final offeredPicks = [
          for (final p in d.picks)
            if (p.giver == trade.fromManager) p,
        ];
        final requestedPicks = [
          for (final p in d.picks)
            if (p.giver == trade.toManager) p,
        ];
        // Liga (Name + fürs Kontern) & Manager laden.
        final leagueName = ref
            .watch(draftLeagueProvider(trade.leagueId))
            .valueOrNull
            ?.name;
        final managers = ref
            .watch(fantasyManagersProvider(trade.leagueId))
            .valueOrNull;
        // **Die Gegenseite.** Bei einem eingehenden Angebot ist das der
        // Absender, bei einem eigenen der Empfänger. Genau das fehlte: Die
        // Karte sagte „Trade-Angebot" und den Liganamen — aber nicht, mit wem
        // man da eigentlich handelt.
        final gegen = managerMit(
          managers,
          incoming ? trade.fromManager : trade.toManager,
        );
        // Ohne Namen bleibt es beim alten Kopf: lieber die neutrale Marke als
        // eine leere Zeile, wo ein Mensch stehen sollte.
        final kopf = gegen == null
            ? 'Trade-Angebot'
            : (incoming ? 'Von ${gegen.display}' : 'An ${gegen.display}');
        final nameVon = {
          for (final m in managers ?? const <FantasyManager>[])
            m.userId: m.display,
        };
        Widget pickKachel(TradePick p) => PickKachel(
          runde: p.runde,
          team: nameVon[p.ursprung] ?? '?',
          code: codeVon[p.key],
          fest: slots?.firstOrNull?.fest ?? false,
          hervor: true,
          hoehe: 46,
          breite: 152,
        );
        final untertitel = gegen == null
            ? leagueName
            : ['Trade-Angebot', ?leagueName].join(' · ');

        return _shell(
          context,
          // Nur ein eingehendes, offenes Angebot will etwas von mir.
          betont: incoming && trade.status.isPending,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Das Gesicht der Gegenseite statt eines Piktogramms — in
                  // dieser App steht überall ein Avatar für einen Menschen.
                  if (gegen != null)
                    AppAvatar(
                      imageUrl: gegen.avatarUrl,
                      emoji: gegen.avatarEmoji,
                      colorHex: gegen.avatarColor,
                      fallbackText: gegen.display,
                      seed: gegen.userId,
                      size: 28,
                    )
                  else
                    Icon(Icons.swap_horiz, size: 18, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          kopf,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        if (untertitel != null)
                          Text(
                            untertitel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  _statusChip(context, trade.status),
                ],
              ),
              const SizedBox(height: 8),
              _seite(
                context,
                'Du bekommst',
                incoming ? offered : requested,
                clubIcons,
                scheme.primary,
                picks: [
                  for (final p in incoming ? offeredPicks : requestedPicks)
                    pickKachel(p),
                ],
              ),
              const SizedBox(height: 8),
              _seite(
                context,
                'Du gibst',
                incoming ? requested : offered,
                clubIcons,
                scheme.tertiary,
                picks: [
                  for (final p in incoming ? requestedPicks : offeredPicks)
                    pickKachel(p),
                ],
              ),
              if (trade.message != null && trade.message!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  '„${trade.message}"',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
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
                            color: scheme.error.withValues(alpha: 0.5),
                          ),
                        ),
                        onPressed: () => _respond(context, ref, trade, false),
                        child: const Text('Ablehnen'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      // **Hier bleibt Grün.** Der gefüllte Knopf der App ist
                      // sonst hell; „Annehmen" steht aber gegen „Ablehnen" in
                      // Rot, und ohne Grün verliert Rot sein Gegenüber.
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.onPrimary,
                        ),
                        onPressed: () => _respond(context, ref, trade, true),
                        child: const Text('Annehmen'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () =>
                        _counter(context, ref, trade, d.items, d.picks),
                    child: const Text('Kontern'),
                  ),
                ),
              ] else if (trade.wartetAufAusfuehrung) ...[
                const SizedBox(height: 10),
                // Abgemacht, aber noch nicht vollzogen. Ohne diesen Hinweis
                // wirkt der Kader falsch: Der Spieler steht noch da, obwohl
                // der Tausch beschlossen ist.
                _VorgemerktHinweis(freiAb: trade.executeAfter),
              ] else if (trade.status.isPending) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      'Warten auf Antwort …',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: scheme.error,
                      ),
                      onPressed: () => _cancel(context, ref, trade),
                      child: const Text('Zurückziehen'),
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
  Widget _shell(
    BuildContext context, {
    required Widget child,
    bool betont = false,
  }) {
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
                    scheme.primary.withValues(alpha: 0.12),
                    grund,
                  ),
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
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.82,
      ),
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
    Color farbe, {
    List<Widget> picks = const [],
  }) {
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
        if (spieler.isEmpty && picks.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 9),
            child: Text('—', style: TextStyle(color: scheme.onSurfaceVariant)),
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
                  Text(
                    id,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  )
                else
                  SpielerKachel(
                    spieler: p,
                    iconUrl: clubIcons[p.club],
                    hervor: true,
                    mitHaken: false,
                    hoehe: 46,
                    breite: 152,
                  ),
              ...picks,
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
      child: Text(
        status.label,
        style: TextStyle(
          color: ton ?? scheme.onSurfaceVariant,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Die Partnerwahl als eigener Schirm — der Weg aus einem Spielerprofil.
///
/// Gemeldet: *„Wenn ich über ein Spielerprofil von meinen Spielern traden
/// möchte, habe ich nur den Screen mit allen Teilnehmern und nicht den
/// normalen Auswahlscreen von den Trades."* Dort stand ein Dialog mit
/// Avataren und Namen; die Frage „mit wem tausche ich?" beantwortet man aber
/// an den **Kadern** — und die zeigt der Trade-Schirm längst.
class TradePartnerScreen extends StatelessWidget {
  const TradePartnerScreen({
    super.key,
    required this.league,
    this.initialOffer,
  });

  final FantasyLeague league;
  final Set<String>? initialOffer;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Neuer Trade')),
    body: TradePartnerList(league: league, initialOffer: initialOffer),
  );
}
