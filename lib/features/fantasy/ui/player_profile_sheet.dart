import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/typografie.dart';
import '../../../app/widgets/leise_reiter.dart';
import '../../../app/widgets/liga_tabelle.dart';
import '../../../app/widgets/team_fixture_list.dart';
import '../../../app/widgets/jersey_icon.dart';
import '../../../app/widgets/karte.dart';
import '../../../core/util/club_colors.dart';
import '../../../core/logic/vereins_kuerzel.dart';
import '../../../core/models/models.dart';
import '../../../core/models/team_fixture.dart';

import '../../auth/providers.dart';
import '../logic/aufstellungs_prognose.dart';
import '../logic/fantasy_scoring_engine.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';
import 'club_badge.dart';
import 'pitch_painter.dart';
import 'punkte_aufschluesselung.dart';
import 'trade_screen.dart';
import '../logic/waiver_fenster.dart';
import 'player_action_buttons.dart';
import '../../../app/widgets/punktzahl.dart';
import '../logic/spieler_schnitt.dart';
import '../logic/rueckkehr.dart';
import '../logic/naechstes_spiel.dart';

/// Öffnet das Spielerprofil (Kopf + Leistungstabelle je Spieltag; für eigene
/// Spieler zusätzlich „Droppen"). [isMine] steuert den Drop-Button.
Future<void> showPlayerProfile(
  BuildContext context, {
  required FantasyLeague league,
  required FantasyPlayer player,
  String? clubIcon,
  required bool isMine,
  DateTime? jetzt,
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
      jetzt: jetzt,
    ),
  );
}

/// Öffnet ein **weiteres** Profil über dem aktuellen.
///
/// **Ohne `pop`, und das ist der Punkt.** Vorher schloss der Tipp auf einen
/// anderen Spieler das offene Blatt und öffnete ein neues an seiner Stelle —
/// wer danach nach unten wischte, landete nicht beim Profil, aus dem er kam,
/// sondern ganz draußen im Reiter. Gemeldet als „ich bin komplett raus aus
/// dem Tab". Gestapelt führt die gewohnte Geste dahin zurück, wo man war, und
/// das darunterliegende Blatt behält seinen Reiter und seinen Scrollstand.
///
/// `isMine` wird hier **gerechnet**, nicht geraten: Die Kaderliste gab bisher
/// pauschal `false` mit, und damit fehlte am eigenen Spieler der Droppen-Knopf.
void _weiteresProfil(
  BuildContext context,
  WidgetRef ref, {
  required FantasyLeague league,
  required FantasyPlayer ziel,
}) {
  final icons =
      ref.read(clubIconsProvider).valueOrNull ?? const <String, String?>{};
  final myId = ref.read(currentUserProvider)?.id;
  final roster = ref.read(leagueRosterProvider(league.id)).valueOrNull ??
      const <RosterEntry>[];
  showPlayerProfile(
    context,
    league: league,
    player: ziel,
    clubIcon: icons[ziel.club],
    isMine: roster.any((r) => r.playerId == ziel.id && r.managerId == myId),
  );
}

class _PlayerProfileSheet extends ConsumerWidget {
  const _PlayerProfileSheet({
    required this.league,
    required this.player,
    required this.clubIcon,
    required this.isMine,
    this.jetzt,
  });

  final FantasyLeague league;
  final FantasyPlayer player;
  final String? clubIcon;
  final bool isMine;

  /// Stellbare Uhr, nur für die Vorschau. **Sonst hängt das Bild am Kalender:**
  /// Ob ein freier Spieler „Holen" oder „Antrag" anbietet, entscheidet der
  /// Anpfiff seines Vereins — und die Vorschau baut feste Spieltage. Am
  /// 04.09.2026 wurde ihr dritter Spieltag zum heutigen, der Spieler rutschte
  /// auf den Waiver, und der Test fiel ohne jede Änderung am Code. Dieselbe
  /// Lehre und dieselbe Lösung wie beim Free-Agency-Schirm: Eine Uhr, die man
  /// stellen kann, ist die einzige Art, ein zeitabhängiges Bild fest
  /// einzuchecken.
  final DateTime? jetzt;

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
                      _Ausfallzeile(playerId: player.id, jetzt: jetzt),
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
                    // **Tabelle statt Vereinskader** (Ansage vom 19.09.2026).
                    // Der Kader-Reiter listete den Pool-Kader des Vereins —
                    // eine Auskunft, die man im Profil eines einzelnen
                    // Spielers selten sucht. Wo sein Verein steht, dagegen
                    // schon.
                    titel: ['Leistung', 'Aufstellung', 'Spielplan', 'Tabelle'],
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
                          data: (season) => _table(
                            context,
                            season,
                            ref.watch(fantasySeasonFixturesProvider)
                                    .valueOrNull ??
                                const <Fixture>[],
                          ),
                        ),
                        _Prognose(league: league, player: player),
                        _Spielplan(club: player.club),
                        _Tabelle(club: player.club),
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
            aufWire: vereinAufWire(
                player.club, spiele, jetzt ?? DateTime.now()),
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
  /// **Der normale Auswahlschirm, kein eigener Dialog.**
  ///
  /// Hier stand ein `SimpleDialog` mit Avataren und Namen. Gemeldet: *„Wenn
  /// ich über ein Spielerprofil von meinen Spielern traden möchte, habe ich
  /// nur den Screen mit allen Teilnehmern und nicht den normalen
  /// Auswahlscreen von den Trades."*
  ///
  /// Zu Recht: **Mit wem man tauscht, entscheidet man an den Kadern, nicht an
  /// den Namen** — und genau die stellt der Trade-Schirm nebeneinander. Es
  /// waren zwei Antworten auf dieselbe Frage, und die schlechtere stand
  /// ausgerechnet dort, wo man mit einem konkreten Spieler im Kopf herkommt.
  ///
  /// Der Spieler geht als `initialOffer` mit: Ohne ihn müsste man ihn auf dem
  /// nächsten Schirm noch einmal suchen.
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
    final nav = Navigator.of(context);
    nav.pop();
    nav.push(
      MaterialPageRoute(
        builder: (_) => TradePartnerScreen(
          league: league,
          initialOffer: {player.id},
        ),
      ),
    );
  }

  Widget _table(
    BuildContext context,
    Map<int, Map<String, PlayerMatchStats>> season,
    List<Fixture> spiele,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final defensive = player.position == PlayerPosition.gk ||
        player.position == PlayerPosition.def;

    // **Alle Spieltage der Saison, nicht nur die gewerteten.** Vorher endete
    // die Tabelle beim aktuellen Spieltag; damit war nicht zu sehen, gegen wen
    // es als Nächstes geht — die Frage, die man vor einem Trade stellt.
    final letzte = spiele.isEmpty
        ? 34
        : spiele.map((f) => f.round).fold(0, (a, b) => a > b ? a : b);
    final runden = [for (var r = 1; r <= (letzte == 0 ? 34 : letzte); r++) r];

    // Gegner je Spieltag, aus dem Spielplan des Vereins. Verglichen wird die
    // kanonische Form: „1. FSV Mainz 05" und „FSV Mainz 05" sind derselbe
    // Verein (siehe `vereins_kuerzel.dart` und Migration 0108).
    final meiner = vereinKanonisch(player.club);
    final gegner = <int, ({String kuerzel, bool heim})>{};
    for (final f in spiele) {
      final heim = vereinKanonisch(f.home.name) == meiner;
      final aus = vereinKanonisch(f.away.name) == meiner;
      if (!heim && !aus) continue;
      gegner[f.round] = (
        kuerzel: vereinsKuerzel(heim ? f.away.name : f.home.name),
        heim: heim,
      );
    }

    final rows = [
      for (final r in runden)
        (r, season[r]?[player.id] ?? const PlayerMatchStats()),
    ];
    final gewertet = [
      for (final e in rows)
        if (season.containsKey(e.$1)) e,
    ];
    final total = gewertet.fold<double>(
      0,
      (s, e) => s + scorePlayer(e.$2, player.position, league.scoring),
    );
    final schnitt = spielerSchnitt(
      saison: season,
      spielerId: player.id,
      position: player.position,
      regeln: league.scoring,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      children: [
        // **Eine Leiste statt dreier Kästen.** Zwei getönte Kacheln über einem
        // breiten Kasten sahen aus wie drei angefangene Gedanken; die vier
        // Zahlen gehören zusammen und stehen jetzt in einer Reihe, durch
        // Haarlinien getrennt.
        _Bilanzleiste(
          punkte: total,
          schnitt: schnitt,
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
                  gegner: gegner[r],
                  // Ein Spieltag, der noch nicht gewertet ist, hat keine
                  // Punktzahl — auch keine 0.
                  punkte: season.containsKey(r)
                      ? scorePlayer(st, player.position, league.scoring)
                      : null,
                  onTap: season.containsKey(r)
                      ? () => _zeigeAufschluesselung(context, r, st)
                      : null,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _zeigeAufschluesselung(
    BuildContext context,
    int runde,
    PlayerMatchStats stats,
  ) {
    zeigePunkteAufschluesselung(
      context,
      titel: '${player.name} · $runde. Spieltag',
      score: scorePlayerDetailed(stats, player.position, league.scoring),
      gespielt: stats.hasContribution,
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
          Expanded(child: Text('GEGNER', style: stil)),
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

/// **Die Bilanz als eine Leiste.**
///
/// Hier standen zwei getönte Kacheln („Punkte", „Spiele") über einem breiten
/// Kasten mit den Schnitten — drei Formen für vier Zahlen, und keine sagte,
/// dass sie zusammengehören. Jetzt eine Reihe, durch Haarlinien geteilt.
class _Bilanzleiste extends StatelessWidget {
  const _Bilanzleiste({required this.punkte, required this.schnitt});

  final double punkte;
  final SpielerSchnitt schnitt;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // **Minus steht rot da.** Ein Minuszeichen vor einer sonst gleich
    // aussehenden Zahl überliest man; die Farbe sieht man, bevor man liest.
    Widget feld(String wert, String wort,
            {bool leise = false, double? zahl}) =>
        Expanded(
          child: Column(
            children: [
              Text(
                wert,
                maxLines: 1,
                style: TextStyle(
                  fontSize: Schrift.h3,
                  fontWeight: FontWeight.w800,
                  fontFeatures: gleichbreiteZiffern,
                  color: (zahl ?? 0) < 0
                      ? scheme.error
                      : (leise ? scheme.onSurfaceVariant : scheme.onSurface),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                wort.toUpperCase(),
                maxLines: 1,
                style: TextStyle(
                  fontSize: Schrift.mikro,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );

    Widget trenner() => Container(
          width: 1,
          height: 30,
          color: scheme.onSurface.withValues(alpha: 0.08),
        );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          feld(formatPoints(punkte), 'Punkte', zahl: punkte),
          trenner(),
          feld(formatPoints(schnitt.punkteJeSpieltag), 'Ø je Spieltag',
              zahl: schnitt.punkteJeSpieltag),
          trenner(),
          feld('${schnitt.minutenJeSpieltag.round()}', 'Ø Minuten',
              leise: true),
          trenner(),
          feld('${schnitt.einsaetze}', 'Einsätze', leise: true),
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
    required this.gegner,
  });

  final int runde;
  final PlayerMatchStats stats;
  final bool defensive;

  /// `null` = der Spieltag ist noch nicht gewertet. Dann steht in der Zeile
  /// überall ein Strich, und sie reagiert nicht auf Tippen: Es gibt nichts
  /// aufzuschlüsseln.
  final double? punkte;
  final VoidCallback? onTap;

  /// Gegner dieses Spieltags samt Heimrecht — aus dem Spielplan des Vereins.
  final ({String kuerzel, bool heim})? gegner;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final gespielt = stats.hasContribution;
    final offen = punkte == null;
    final stil = TextStyle(
      fontSize: 13,
      fontFeatures: const [FontFeature.tabularFigures()],
      color: gespielt
          ? scheme.onSurface
          : scheme.onSurfaceVariant.withValues(alpha: offen ? 0.6 : 1),
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
            // **Gegen wen.** Ohne den Gegner ist eine Zeile mit lauter
            // Strichen nur ein leerer Spieltag; mit ihm ist sie der Spielplan
            // — die Frage vor einem Trade lautet „wen hat er noch?".
            Expanded(
              child: Text(
                gegner == null
                    ? '–'
                    : '${gegner!.heim ? '' : '@ '}${gegner!.kuerzel}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: stil.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant
                      .withValues(alpha: offen ? 0.7 : 0.95),
                ),
              ),
            ),
            // Nicht gespielt zeigt „–", nicht „0" — dieselbe Regel wie im
            // MatchUp: Eine Null ist sonst doppeldeutig.
            z(gespielt ? '${stats.minutes}' : '–'),
            z(gespielt ? '${stats.goals}' : '–'),
            z(gespielt ? '${stats.assists}' : '–'),
            // **Kein „✓" als Zeichen.** Rajdhani hat es nicht, und in
            // der Vorschau stand dort ein leeres Kästchen; auf dem Gerät hinge
            // die Anzeige an einer Schrift-Ersatzkette. Ein Symbol aus der
            // Icon-Schrift ist beides nicht.
            if (defensive)
              SizedBox(
                width: _LeistungKopf.zahl,
                child: !gespielt || !stats.cleanSheet
                    ? Text('–', style: stil, textAlign: TextAlign.center)
                    : Icon(Icons.check, size: 15, color: stil.color),
              ),
            SizedBox(
              width: _LeistungKopf.punkte,
              child: Text(
                gespielt && punkte != null ? formatPoints(punkte!) : '–',
                textAlign: TextAlign.right,
                // Dieselbe Auszeichnung wie in der Aufschlüsselung darunter:
                // Rot markiert den Abzug, der Normalfall braucht keine Farbe.
                style: stil.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: gespielt && (punkte ?? 0) < 0
                      ? Theme.of(context).colorScheme.error
                      : stil.color,
                ),
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
    // **Kanonisch vergleichen, nicht buchstabengenau.** `players.club` schreibt
    // „1. FC Köln", der Spielplan „FC Köln" — bei sieben von achtzehn Vereinen
    // gehen die Schreibweisen auseinander, und der Reiter blieb für sie leer.
    final seine = spieleDesVereins(alle, club);
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
      // Ohne Wettbewerb: Der Spielplan eines Spielers zeigt die Liga, in der
      // er spielt — in jeder Zeile dieselbe.
      children: fixturesWithDateHeaders(umgewandelt, mitWettbewerb: false),
    );
  }
}

/// Der Vereinskader — alle Poolspieler desselben Vereins, nach Position.
///
/// Antippen öffnet **deren** Profil: Der Weg von einem Spieler zu seinen
/// Mitspielern führte vorher über die Vereinsseite.
/// **Die Tabelle seiner Liga**, mit seinem Verein hervorgehoben.
///
/// Sie ersetzt den Vereinskader (Ansage vom 19.09.2026). Liga und Team-ID
/// stehen im Profil nicht bereit — es kennt nur den Vereins**namen** aus dem
/// Spielerpool. Beides kommt deshalb aus dem Spielplan, genau wie im
/// Spielplan-Reiter darüber: `spieleDesVereins` vergleicht kanonisch („1. FC
/// Köln" im Kader gegen „FC Köln" im Spielplan — bei sieben von achtzehn
/// Vereinen gehen die Schreibweisen auseinander), die erste Partie nennt die
/// Liga, und Heim oder Gast liefert die `TeamRef`.
class _Tabelle extends ConsumerWidget {
  const _Tabelle({required this.club});

  final String club;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alle = ref.watch(fantasySeasonFixturesProvider).valueOrNull;
    if (alle == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final seine = spieleDesVereins(alle, club);
    if (seine.isEmpty) {
      return _Leer('Für $club liegt keine Tabelle vor.');
    }
    final gesucht = vereinKanonisch(club);
    final erste = seine.first;
    final team = vereinKanonisch(erste.home.name) == gesucht
        ? erste.home
        : erste.away;
    return LigaTabelle(leagueId: erste.leagueId, eigenesTeam: team.id);
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
    _weiteresProfil(context, ref, league: league, ziel: ziel);
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
  ///
  /// **Sortiert nach den Minuten des letzten Spiels**, nicht nach Position.
  /// Der Grund steht in [_minutenZuletzt]: Wer eben noch neunzig Minuten
  /// gespielt hat und in der Prognose fehlt, gehört nach oben.
  List<FantasyPlayer> _uebrige(
      WidgetRef ref, PrognoseElf elf, Map<String, int> minuten) {
    final pool =
        ref.watch(playerPoolProvider).valueOrNull ?? const <FantasyPlayer>[];
    final drin = {for (final s in elf.elf) s.playerId};
    return [
      for (final p in pool)
        if (p.club == player.club && !p.abgewandert && !drin.contains(p.id)) p,
    ]..sort((a, b) {
        final ma = minuten[a.id] ?? 0;
        final mb = minuten[b.id] ?? 0;
        if (ma != mb) return mb.compareTo(ma);
        if (a.position.index != b.position.index) {
          return a.position.index.compareTo(b.position.index);
        }
        return a.name.compareTo(b.name);
      });
  }

  /// Die Einsatzminuten aus dem **letzten Spiel dieses Vereins**.
  ///
  /// **Die Prognose trifft rund drei von vier Namen** — gemessen über die
  /// Saison 2025/26 (306 Spiele): 77 % bei Sportmonks, und genau so gut ist
  /// die banale Regel „dieselbe Elf wie letzte Woche" (77 %). Eine bessere
  /// Quelle gibt es nur redaktionell; kicker beantwortet automatisierte
  /// Abrufe mit 403.
  ///
  /// Statt eine Prognose zu behaupten, die sie nicht ist, steht neben jedem
  /// Namen darunter, wie lange er zuletzt auf dem Platz war. Ein Kapitän mit
  /// 90 Minuten, den die Prognose vergisst (gemeldet an Lukas Pinckert),
  /// steht damit oben in der Liste und mit seiner Zahl daneben — die
  /// Entscheidung trifft der Manager, nicht die Quelle.
  Map<String, int> _minutenZuletzt(WidgetRef ref, List<Fixture> spiele) {
    final saison = ref.watch(seasonStatsProvider).valueOrNull;
    final zuletzt = letztesGespieltes(spiele, player.club);
    if (saison == null || zuletzt == null) return const {};
    return {
      for (final e in (saison[zuletzt.round] ?? const {}).entries)
        if (e.value.minutes > 0) e.key: e.value.minutes,
    };
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
      data: (elf) {
        // **Solange es keine Prognose gibt, steht die Elf der Vorwoche da.**
        // Sportmonks liefert erst ein bis zwei Tage vor Anpfiff; davor lagen
        // hier drei bis fünf Tage ohne jede Auskunft. Die Fortschreibung
        // trifft genauso gut (77 % gegen 77 %, gemessen über die Saison
        // 2025/26) und ist Tage früher da.
        final zeige = elf ??
            ref.watch(fortgeschriebeneElfProvider(player.club)).valueOrNull;
        return ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 16),
        children: [
          _PrognoseKopf(spiel: spiel, elf: zeige),
          if (zeige == null)
            _NochKeinePrognose(player: player, spiel: spiel)
          else ...[
            if (zeige.ausRunde != null)
              _FortschreibungHinweis(
                ausRunde: zeige.ausRunde!,
                ersetzt: zeige.elf.where((x) => x.ersatz).length,
                offen: zeige.elf.where((x) => x.offen).length,
              ),
            _Urteil(
              ausRunde: zeige.ausRunde,
              drin: zeige.enthaelt(player.id),
              bank: zeige.aufBank(player.id),
              // **Ein abgepfiffenes Spiel ist nie „voraussichtlich".** Seit
              // die Anzeige bis zum Ende des Spieltags auf der laufenden Runde
              // bleibt, steht hier auch eine gelaufene Partie. In aller Regel
              // ist ihre Aufstellung ohnehin gemeldet; fehlte das Kennzeichen
              // einmal, stünde sonst „voraussichtlich in der Startelf" über
              // einem Spiel von gestern.
              bestaetigt:
                  zeige.bestaetigt || spiel.status == FixtureStatus.finished,
            ),
            _Formationsfeld(
              elf: zeige,
              ich: player.id,
              verein: player.club,
              oeffnet: (id) => _ausPool(ref, id) != null,
              onTip: (id) => _oeffne(context, ref, id),
            ),
            _NichtInDerElf(
              uebrige: _uebrige(ref, zeige, _minutenZuletzt(ref, spiele)),
              minuten: _minutenZuletzt(ref, spiele),
              ich: player.id,
              onTip: (id) => _oeffne(context, ref, id),
            ),
          ],
        ],
      );
      },
    );
  }
}

/// **Die Zeile, die sagt, woher diese Elf kommt.**
///
/// Ohne sie wäre die Fortschreibung eine Behauptung: elf Trikots auf einem
/// Feld sehen aus wie eine Aufstellung, egal woher sie stammen. Hier steht
/// deshalb der Spieltag, aus dem sie kommt, und wie viele Plätze neu besetzt
/// werden mussten.
///
/// Gold, weil es kein Fehler ist, sondern eine Annahme, die man kennen muss —
/// dieselbe Farbe wie „Aufstellung · noch nicht gestellt".
class _FortschreibungHinweis extends StatelessWidget {
  const _FortschreibungHinweis({
    required this.ausRunde,
    required this.ersetzt,
    required this.offen,
  });

  final int ausRunde;
  final int ersetzt;
  final int offen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final zusatz = [
      if (ersetzt > 0)
        ersetzt == 1
            ? 'Ein Ausfall ist durch den nominellen Ersatz getauscht.'
            : '$ersetzt Ausfälle sind durch den nominellen Ersatz getauscht.',
      if (offen > 0)
        offen == 1
            ? 'Für einen Platz gibt es keinen freien Ersatz.'
            : 'Für $offen Plätze gibt es keinen freien Ersatz.',
    ].join(' ');

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      // **Ohne Hauch, ohne Farbe.** Auf Ansage (08.09.2026): „Das reicht, wenn
      // das schwarz ist, mit weißer Schrift." Und es stimmt — hier ist nichts
      // zu tun, es ist eine Auskunft darüber, woher die Elf kommt. Farbe
      // trägt in dieser App, was etwas will; eine Herkunftsangabe will
      // nichts. Der Kartengrund und die Haarlinie genügen.
      decoration: kartenDeko(context, radius: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.history, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Elf des $ausRunde. Spieltags',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                      fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    'Die voraussichtliche Aufstellung kommt ein bis zwei Tage '
                        'vor Anpfiff. Bis dahin steht hier die zuletzt '
                        'gemeldete Elf.',
                    if (zusatz.isNotEmpty) zusatz,
                  ].join(' '),
                  style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      height: 1.35,
                      fontSize: 12),
                ),
              ],
            ),
          ),
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
    required this.verein,
    required this.oeffnet,
    required this.onTip,
  });

  /// Der Verein, dessen Elf hier steht — er gibt den Trikots ihre Farbe.
  final String verein;

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
                            onTap: s.offen ||
                                    s.playerId == ich ||
                                    !oeffnet(s.playerId)
                                ? null
                                : () => onTip(s.playerId),
                            child: _Feldspieler(
                              spieler: s,
                              verein: verein,
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

/// Das Gold, mit dem in dieser App „hier ist etwas zu tun / hier steht eine
/// Annahme" markiert wird — dieselbe Farbe wie am Waiver und an „Aufstellung ·
/// noch nicht gestellt".
const _kErsatzGold = Color(0xFFFFC83D);

/// Ein Spieler auf dem Feld: Rückennummer im Kreis, Name darunter.
///
/// Hervorgehoben wird **hell**, nicht grün: Grün heißt in dieser App „hier
/// läuft etwas", und dass man gerade das eigene Profil ansieht, läuft nicht.
class _Feldspieler extends StatelessWidget {
  const _Feldspieler({
    required this.spieler,
    required this.verein,
    required this.hervor,
  });

  final PrognoseSpieler spieler;

  /// Verein der Elf — bestimmt die Trikotfarbe.
  final String verein;
  final bool hervor;

  /// Vereine ohne hinterlegte Trikotfarben (Pokalgegner aus der Oberliga)
  /// bekommen ein neutrales Weiß auf Dunkel statt einer erfundenen Farbe.
  static const _ersatz = ClubColors(Color(0xFFEDEFF4), Color(0xFF2A2A2A));

  @override
  Widget build(BuildContext context) {
    const schnee = Color(0xFFEDEFF4);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        // **Ein Trikot statt eines Kreises.** Es ist als Symbol sofort als
        // Spieler lesbar, und die Vereinsfarbe sagt vor dem Namen, welche
        // Mannschaft da steht — dasselbe `JerseyIcon` wie im Spielbericht,
        // kein zweiter Feldlook.
        if (spieler.offen)
          // **Ein unbesetzter Platz sagt, dass er unbesetzt ist.** Für die
          // Position der Vorwoche gibt es im Kader keinen freien Ersatz —
          // lieber sichtbar leer als ein Stürmer im Tor. Dieselbe Regel wie
          // beim fehlenden Torwart im Duell (0120).
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.35),
              border: Border.all(
                  color: schnee.withValues(alpha: 0.45), width: 1.2),
            ),
            child: Icon(Icons.question_mark,
                size: 16, color: schnee.withValues(alpha: 0.7)),
          )
        else
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: hervor
                  ? [
                      BoxShadow(
                        color: schnee.withValues(alpha: 0.55),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ]
                  : const [
                      BoxShadow(color: Colors.black45, blurRadius: 4),
                    ],
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                JerseyIcon(
                  colors: clubColors(verein, fallback: _ersatz),
                  number: spieler.nummer,
                  size: hervor ? 38 : 34,
                ),
                // **Der Ersatz trägt ein Zeichen.** Er steht hier nur, weil
                // der Mann der Vorwoche ausfällt; ohne Kennzeichen sähe eine
                // Vermutung aus wie eine Meldung.
                if (spieler.ersatz)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 14,
                      height: 14,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: _kErsatzGold,
                      ),
                      child: const Icon(Icons.swap_horiz,
                          size: 10, color: Colors.black),
                    ),
                  ),
              ],
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
              spieler.offen ? 'frei' : _kurzerName(spieler.name),
              maxLines: 1,
              style: TextStyle(
                fontSize: 10,
                height: 1.15,
                fontWeight: hervor ? FontWeight.w800 : FontWeight.w600,
                color: schnee.withValues(
                    alpha: spieler.offen ? 0.6 : (hervor ? 1 : 0.85)),
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
    required this.minuten,
    required this.ich,
    required this.onTip,
  });

  final List<FantasyPlayer> uebrige;

  /// Einsatzminuten aus dem letzten Spiel des Vereins, je Spieler.
  final Map<String, int> minuten;
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
          Row(
            children: [
              Expanded(
                child: Text(
                  'Nicht in der Startelf',
                  style: TextStyle(
                    fontSize: Schrift.klein,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              // **Die Zahl braucht ihre Beschriftung.** Ohne sie stünde neben
              // einem Namen eine 90, die alles heißen könnte.
              if (minuten.isNotEmpty)
                Text(
                  'Minuten zuletzt',
                  style: TextStyle(
                    fontSize: Schrift.klein,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
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
                minuten: minuten[p.id],
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
    required this.minuten,
    required this.hervor,
    required this.onTap,
  });

  final FantasyPlayer spieler;

  /// Minuten im letzten Spiel des Vereins. `null` heißt „war nicht auf dem
  /// Platz" — dann steht dort nichts. Eine 0 wäre eine Zahl über etwas, das
  /// nicht stattfand.
  final int? minuten;
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
            if (minuten != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  '$minuten',
                  style: TextStyle(
                    fontSize: Schrift.koerperKlein,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: scheme.onSurfaceVariant,
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
    this.ausRunde,
  });

  final bool drin;

  /// Er sitzt auf der Bank — das gibt es nur bei einer gemeldeten
  /// Aufstellung, und es ist eine andere Auskunft als „nicht dabei": Er kann
  /// eingewechselt werden und Punkte holen.
  final bool bank;

  /// Gemeldet statt vorhergesagt. Dann fällt das „voraussichtlich" weg — es
  /// wäre eine Unsicherheit, die es nicht mehr gibt.
  final bool bestaetigt;

  /// Die Elf ist **fortgeschrieben** und stammt aus diesem Spieltag. Dann darf
  /// hier weder „voraussichtlich" noch „in der Startelf" stehen: Beides wäre
  /// eine Aussage über das kommende Spiel, und die trifft niemand — die
  /// einzige belegbare Auskunft ist, wo er zuletzt stand.
  final int? ausRunde;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // **Farbe trägt nur der Fall, der etwas will.** Steht der Spieler nicht in
    // der Elf, muss die Aufstellung geändert werden — Gold. Steht er drin, ist
    // nichts zu tun, und die Zeile bleibt still. Grün wäre hier doppelt
    // falsch: Es heißt in dieser App „hier läuft etwas", und es lief schon
    // einmal als Dauerfarbe durch dieses Profil.
    final farbe = drin ? scheme.onSurfaceVariant : const Color(0xFFFFC83D);
    final text = ausRunde != null
        ? (drin
            ? 'Stand am $ausRunde. Spieltag in der Startelf'
            : 'Stand am $ausRunde. Spieltag nicht in der Startelf')
        : drin
            ? (bestaetigt ? 'In der Startelf' : 'Voraussichtlich in der Startelf')
            : bank
                ? 'Auf der Bank'
                : bestaetigt
                    ? 'Nicht im Kader für dieses Spiel'
                    : 'Nicht in der voraussichtlichen Elf';
    return Container(
      margin: EdgeInsets.fromLTRB(12, 0, 12, drin ? 2 : 8),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: drin ? 6 : 10),
      decoration:
          drin ? null : kartenDeko(context, hauch: farbe, radius: 12),
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
                  spiel.status == FixtureStatus.finished
                      ? 'Keine Aufstellung'
                      : 'Noch keine Aufstellung',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            // **Für ein gespieltes Spiel wäre „kommt noch" falsch.** Seit die
            // Anzeige bis zum Ende des Spieltags auf der laufenden Runde
            // bleibt, kann hier auch eine abgepfiffene Partie stehen — dann
            // fehlt die Aufstellung wirklich, statt noch unterwegs zu sein.
            spiel.status == FixtureStatus.finished
                ? 'Für dieses Spiel liegt keine Aufstellung vor.'
                : 'Die voraussichtliche Elf steht in der Regel ein bis zwei '
                    'Tage vor Anpfiff.',
            style: TextStyle(color: scheme.onSurfaceVariant, height: 1.35),
          ),
          if (stats != null && zuletzt != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: kartenDeko(context, radius: 12),
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
  const _Ausfallzeile({required this.playerId, this.jetzt});

  final String playerId;

  /// Feste Uhr für die Vorschau — sonst hinge das Bild an `DateTime.now()`
  /// und wäre morgen ein anderes.
  final DateTime? jetzt;

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

    // **Die Rückkehr steht auf einer eigenen Zeile**, nicht hinter „seit ...".
    // Sie beantwortet eine andere Frage als der Rest der Karte: nicht „was hat
    // er", sondern „kann ich ihn nächste Woche aufstellen".
    final verein = ref
        .watch(playerPoolProvider)
        .valueOrNull
        ?.where((p) => p.id == playerId)
        .firstOrNull
        ?.club;
    final spielplan =
        ref.watch(fantasySeasonFixturesProvider).valueOrNull ?? const <Fixture>[];
    final spieltag = (a.bis != null && verein != null)
        ? ersterSpieltagAb(a.bis!, spielplan, verein)
        : null;
    final rueckkehr = [
      rueckkehrSatz(a.bis, jetzt ?? DateTime.now()),
      // Der Spieltag ist die Zahl, mit der man plant. Er kommt nur dazu, wenn
      // das Datum in der Zukunft liegt — hinter „Rückkehr war für den 10.
      // September geplant" wäre er eine Behauptung.
      if (spieltag != null && !a.bis!.isBefore(DateTime.now()))
        'frühestens $spieltag. Spieltag',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
        decoration: kartenDeko(context, hauch: farbe, radius: 12),
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
                    '${a.kopf} · ${a.grund}',
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
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      rueckkehr,
                      style: TextStyle(
                        fontSize: Schrift.klein,
                        fontWeight: FontWeight.w600,
                        color: a.bis == null
                            ? Theme.of(context).colorScheme.onSurfaceVariant
                            : farbe.withValues(alpha: 0.92),
                      ),
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

