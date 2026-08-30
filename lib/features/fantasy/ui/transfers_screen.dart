import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/widgets/leise_reiter.dart';
import '../../auth/providers.dart';
import '../logic/transfer_vorgaenge.dart';
import '../models/fantasy_models.dart';
import '../models/roster_move.dart';
import '../providers.dart';
import 'player_profile_sheet.dart';
import 'spieler_kachel.dart';
import 'trade_screen.dart';

/// **Transfers**: was bei mir ansteht, und was in der Liga passiert.
///
/// Beides lag vorher verstreut: Eingehende Trade-Angebote im Trade-Schirm,
/// eigene Waiver-Anträge hinter einem Symbol in der Free-Agency-Kopfzeile, und
/// die Bewegungen der anderen **nirgends** — man erfuhr sie höchstens
/// nebenbei im Liga-Chat, wenn man gerade hinsah.
///
/// Die zwei Reiter beantworten zwei verschiedene Fragen: „muss ich etwas tun?"
/// und „was ist los?". Deshalb zwei Seiten und nicht eine lange Liste.
class TransfersScreen extends ConsumerWidget {
  const TransfersScreen({super.key, required this.league});

  final FantasyLeague league;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text('Transfers'),
              Text(league.name,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
          bottom: const LeiseReiter(
              titel: ['Meine Transfers', 'Liga'], horizontal: 12),
        ),
        body: TabBarView(
          children: [
            _MeineSeite(league: league),
            _LigaSeite(league: league),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Meine Seite
// ---------------------------------------------------------------------------

class _MeineSeite extends ConsumerWidget {
  const _MeineSeite({required this.league});

  final FantasyLeague league;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myId = ref.watch(currentUserProvider)?.id;
    final trades =
        ref.watch(leagueTradesProvider(league.id)).valueOrNull ?? const [];
    final claims =
        ref.watch(myWaiverClaimsProvider(league.id)).valueOrNull ?? const [];
    final moves =
        ref.watch(rosterMovesProvider(league.id)).valueOrNull ?? const [];

    final eingehend = [
      for (final t in trades)
        if (t.toManager == myId && t.status.isPending) t
    ];
    final gestellt = [
      for (final t in trades)
        if (t.fromManager == myId && t.status.isPending) t
    ];
    final vorgemerkt = ref.watch(vorgemerkteTradesProvider(league.id));
    final offeneAntraege = [
      for (final c in claims)
        if (c.status.isPending) c
    ]..sort((a, b) => a.rank.compareTo(b.rank));
    final meineBewegungen = [
      for (final m in moves)
        if (m.managerId == myId) m
    ];

    if (eingehend.isEmpty &&
        gestellt.isEmpty &&
        vorgemerkt.isEmpty &&
        offeneAntraege.isEmpty &&
        meineBewegungen.isEmpty) {
      return const _Leer(
          'Noch keine Transfers.\nAngebote, Anträge und Wechsel stehen hier.');
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 20),
      children: [
        if (eingehend.isNotEmpty) ...[
          // Nur hier ist wirklich etwas von mir gewollt — deshalb trägt allein
          // diese Marke eine Zahl.
          _Marke('Wartet auf dich', zahl: eingehend.length, farbe: _kRot),
          for (final t in eingehend) TradeCard(tradeId: t.id, inList: true),
        ],
        if (offeneAntraege.isNotEmpty) ...[
          const _Marke('Offene Waiver-Anträge', farbe: _kGold),
          for (final c in offeneAntraege)
            _AntragKarte(league: league, claim: c),
        ],
        if (gestellt.isNotEmpty) ...[
          const _Marke('Selbst gestellt'),
          for (final t in gestellt) TradeCard(tradeId: t.id, inList: true),
        ],
        if (vorgemerkt.isNotEmpty) ...[
          const _Marke('Angenommen, wartet auf den Spieltag'),
          for (final t in vorgemerkt) TradeCard(tradeId: t.id, inList: true),
        ],
        if (meineBewegungen.isNotEmpty) ...[
          const _Marke('Meine Wechsel'),
          for (final v in ereignisseAus(meineBewegungen))
            _VorgangsKarte(league: league, ereignis: v, mitManager: false),
        ],
      ],
    );
  }
}

/// Ein offener Waiver-Antrag — in derselben Kartenform wie ein Trade-Angebot.
class _AntragKarte extends ConsumerWidget {
  const _AntragKarte({required this.league, required this.claim});

  final FantasyLeague league;
  final WaiverClaim claim;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final pool =
        ref.watch(playerPoolProvider).valueOrNull ?? const <FantasyPlayer>[];
    final nachId = {for (final p in pool) p.id: p};
    final icons =
        ref.watch(clubIconsProvider).valueOrNull ?? const <String, String?>{};
    final fenster = ref.watch(waiverWindowProvider).valueOrNull;

    final rein = nachId[claim.addPlayerId];
    final raus = claim.dropPlayerId == null ? null : nachId[claim.dropPlayerId!];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.schedule, size: 16, color: _kGold),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Antrag ${claim.rank}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
                if (fenster?.deadline != null)
                  Text(
                    'ab ${DateFormat('E, d. MMM, HH:mm', 'de_DE').format(fenster!.deadline!)}',
                    style: TextStyle(
                        fontSize: 11, color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (rein != null)
                  SpielerKachel(
                    spieler: rein,
                    iconUrl: icons[rein.club],
                    hoehe: 46,
                    breite: 152,
                    mitHaken: false,
                    onTap: () => showPlayerProfile(context,
                        league: league,
                        player: rein,
                        clubIcon: icons[rein.club],
                        isMine: false),
                  )
                else
                  _Unbekannt(claim.addPlayerId),
                if (raus != null) ...[
                  Icon(Icons.swap_horiz,
                      size: 18, color: scheme.onSurfaceVariant),
                  SpielerKachel(
                    spieler: raus,
                    iconUrl: icons[raus.club],
                    hoehe: 46,
                    breite: 152,
                    mitHaken: false,
                    onTap: () => showPlayerProfile(context,
                        league: league,
                        player: raus,
                        clubIcon: icons[raus.club],
                        isMine: true),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    raus == null
                        ? 'Ohne Abgang — bei vollem Kader wird er ungültig.'
                        : 'Wird beim nächsten Waiver-Fenster entschieden.',
                    style: TextStyle(
                        fontSize: 11, color: scheme.onSurfaceVariant),
                  ),
                ),
                TextButton(
                  onPressed: () => _stornieren(context, ref),
                  child: const Text('Zurückziehen'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _stornieren(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(fantasyLeagueRepositoryProvider)
          .cancelWaiverClaim(claim.id);
      ref.invalidate(myWaiverClaimsProvider(league.id));
      messenger
          .showSnackBar(const SnackBar(content: Text('Antrag zurückgezogen.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Fehlgeschlagen: $e')));
    }
  }
}

// ---------------------------------------------------------------------------
// Liga-Seite
// ---------------------------------------------------------------------------

class _LigaSeite extends ConsumerWidget {
  const _LigaSeite({required this.league});

  final FantasyLeague league;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movesAsync = ref.watch(rosterMovesProvider(league.id));
    return movesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _Leer('Bewegungen nicht geladen.\n$e'),
      data: (moves) {
        // **Der Draft ist keine Bewegung, die man nachliest.** Er erzeugt bei
        // sechzehn Teams Hunderte Zeilen und würde jede Free-Agency-Meldung
        // darunter begraben; wer den Draft sehen will, hat dafür das Board.
        final vorgaenge = [
          for (final v in ereignisseAus(moves))
            if (v.weg != 'draft') v
        ];
        if (vorgaenge.isEmpty) {
          return const _Leer(
              'Noch keine Wechsel.\nHier stehen alle Zu- und Abgänge der Liga.');
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 20),
          itemCount: vorgaenge.length,
          itemBuilder: (context, i) {
            final v = vorgaenge[i];
            final davor = i == 0 ? null : vorgaenge[i - 1];
            final neuerTag =
                davor == null || !_gleicherTag(davor.passiertAm, v.passiertAm);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (neuerTag) _Marke(_tag(v.passiertAm)),
                _VorgangsKarte(
                    league: league, ereignis: v, mitManager: true),
              ],
            );
          },
        );
      },
    );
  }

  static bool _gleicherTag(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _tag(DateTime d) {
    final heute = DateTime.now();
    if (_gleicherTag(d, heute)) return 'Heute';
    if (_gleicherTag(d, heute.subtract(const Duration(days: 1)))) {
      return 'Gestern';
    }
    return DateFormat('EEEE, d. MMMM', 'de_DE').format(d);
  }
}

/// **Ein Vorgang: was kam, was ging, und wo der Abgegebene jetzt steckt.**
///
/// Vorher standen Zugang und Abgang als zwei unabhängige Zeilen untereinander
/// — „X verpflichtet" über „Y abgegeben", ohne dass etwas sagte, dass Y *für*
/// X gehen musste. Und über Y stand danach nichts mehr, obwohl sich sofort die
/// nächste Frage stellt: Kann ich ihn holen?
class _VorgangsKarte extends ConsumerWidget {
  const _VorgangsKarte({
    required this.league,
    required this.ereignis,
    required this.mitManager,
  });

  final FantasyLeague league;
  final TransferEreignis ereignis;

  /// Auf der Liga-Seite steht dabei, wer es war; auf der eigenen nicht.
  final bool mitManager;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final pool =
        ref.watch(playerPoolProvider).valueOrNull ?? const <FantasyPlayer>[];
    final nachId = {for (final p in pool) p.id: p};
    final icons =
        ref.watch(clubIconsProvider).valueOrNull ?? const <String, String?>{};
    final manager =
        ref.watch(fantasyManagersProvider(league.id)).valueOrNull ?? const [];
    final namen = {for (final m in manager) m.userId: m.display};

    Widget kachel(RosterMove m) {
      final p = nachId[m.playerId];
      if (p == null) return _Unbekannt(m.playerId);
      return SpielerKachel(
        spieler: p,
        iconUrl: icons[p.club],
        // Schmaler als im Trade-Angebot: Dort steht eine Kachel je Zeile,
        // hier stehen zwei nebeneinander plus Pfeil.
        hoehe: 42,
        breite: 124,
        mitHaken: false,
        onTap: () => showPlayerProfile(context,
            league: league,
            player: p,
            clubIcon: icons[p.club],
            isMine: false),
      );
    }

    final erste = ereignis.seiten.first;

    // **Ein Trade steht als ein Tausch da, nicht als zwei Meldungen.** Er
    // erzeugt je Manager einen Vorgang; nebeneinander gestellt wären das
    // dieselbe Auskunft zweimal, spiegelverkehrt.
    // **Kein „↔" im Text.** Barlow Condensed hat das Zeichen nicht; in der
    // Vorschau stand dort ein leeres Kästchen, und auf dem Gerät hinge es an
    // einer Schrift-Ersatzkette. Der Tauschpfeil ist ein Symbol (links im
    // Kopf), kein Buchstabe — dieselbe Regel wie im Trade-Schirm.
    final kopf = ereignis.istTrade
        ? 'Trade · ${ereignis.seiten.map((v) => namen[v.managerId] ?? '?').join(' und ')}'
        : [
            erste.bezeichnung,
            if (mitManager && namen[erste.managerId] != null)
              namen[erste.managerId]!,
          ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                    ereignis.istTrade
                        ? Icons.swap_horiz
                        : (erste.nurAbgang
                            ? Icons.north_east
                            : Icons.south_west),
                    size: 15,
                    color: ereignis.istTrade
                        ? scheme.onSurfaceVariant
                        : (erste.nurAbgang ? _kRot : _kGruen)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(kopf,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700)),
                ),
                Text(
                  DateFormat('HH:mm', 'de_DE').format(ereignis.passiertAm),
                  style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (ereignis.istTrade)
              // Je Seite eine Zeile: wer bekommt was. Der Abgang der einen ist
              // der Zugang der anderen — ihn zweimal hinzuschreiben wäre
              // dasselbe Doppelte in klein.
              for (final v in ereignis.seiten)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 92,
                        child: Text(namen[v.managerId] ?? '?',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurfaceVariant)),
                      ),
                      Icon(Icons.south_west, size: 13, color: _kGruen),
                      const SizedBox(width: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [for (final m in v.rein) kachel(m)],
                      ),
                    ],
                  ),
                )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final m in erste.rein) kachel(m),
                  if (erste.rein.isNotEmpty && erste.raus.isNotEmpty)
                    Icon(Icons.swap_horiz,
                        size: 18, color: scheme.onSurfaceVariant),
                  for (final m in erste.raus) kachel(m),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

const _kGruen = Color(0xFF4ADE6A);
const _kRot = Color(0xFFF23030);
const _kGold = Color(0xFFFFC83D);

/// Kapitelmarke wie überall sonst: farbiger Strich, Wort, Haarlinie bis an den
/// Rand. Eine Zahl trägt sie nur, wo etwas wartet.
class _Marke extends StatelessWidget {
  const _Marke(this.text, {this.zahl, this.farbe});

  final String text;
  final int? zahl;
  final Color? farbe;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final f = farbe ?? scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Row(
        children: [
          Container(width: 3, height: 13, color: f),
          const SizedBox(width: 8),
          Text(text.toUpperCase(),
              style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                  color: farbe ?? scheme.onSurfaceVariant)),
          if (zahl != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                  color: f, borderRadius: BorderRadius.circular(8)),
              child: Text('$zahl',
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
            ),
          ],
          const SizedBox(width: 10),
          Expanded(
            child: Container(height: 1, color: Theme.of(context).dividerColor),
          ),
        ],
      ),
    );
  }
}

class _Unbekannt extends StatelessWidget {
  const _Unbekannt(this.id);
  final String id;

  @override
  Widget build(BuildContext context) => Text(id,
      style: TextStyle(
          fontStyle: FontStyle.italic,
          color: Theme.of(context).colorScheme.onSurfaceVariant));
}

class _Leer extends StatelessWidget {
  const _Leer(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(
                  height: 1.4,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      );
}
