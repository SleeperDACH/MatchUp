import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/league_screen.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/vibrant_league_title.dart';
import '../../../app/widgets/team_fixture_list.dart';
import '../../../core/models/models.dart';
import '../../../core/models/team_fixture.dart';
import '../../auth/providers.dart';
import '../../tippspiel/providers.dart';
import '../../tippspiel/ui/create_tip_round.dart';
import '../logic/fantasy_scoring_engine.dart';
import '../models/fantasy_models.dart';
import '../models/roster_move.dart';
import '../providers.dart';
import 'roster_limit_banner.dart';
import 'draft_room_screen.dart';
import 'draft_start.dart';
import 'fantasy_chat_screen.dart';
import 'fantasy_settings_screen.dart';
import 'fantasy_table_screen.dart';
import 'free_agency_screen.dart';
import 'invite_players_screen.dart';
import 'lineup_screen.dart';
import 'matchup_hero.dart';
import 'matchups_screen.dart';
import 'trade_screen.dart';
import 'transfers_screen.dart';
import 'weekly_recap_screen.dart';
import '../../../app/widgets/karte.dart';
import 'draft_board_screen.dart';
import '../../../app/typografie.dart';
import '../../../app/widgets/kapitelmarke.dart';
import '../../../app/widgets/leise_reiter.dart';
import '../../../app/vorwaermen.dart';

/// Vollwertiger Fantasy-Liga-Screen mit Tabs. Zeigt schon vor dem Draft
/// Tabelle, Teilnehmer und (leeren) Kader an; die Übersicht führt durch
/// Setup und Draft.
class FantasyLeagueScreen extends ConsumerWidget {
  const FantasyLeagueScreen({
    super.key,
    required this.league,
    this.startReiter,
  });

  final FantasyLeague league;

  /// Reiter beim Öffnen ([LigaReiter]); ohne Angabe MatchUp, vor dem Ende
  /// des Draft die Übersicht.
  final int? startReiter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Live-Status, damit Draft-Änderungen sofort durchschlagen.
    final live =
        ref.watch(draftLeagueProvider(league.id)).valueOrNull ?? league;
    final isAdmin = ref.watch(currentUserProvider)?.id == league.createdBy;

    return DefaultTabController(
      length: 4,
      // **MatchUp vorn** (auf Ansage, 16.10.2026) — dort öffnet die Liga,
      // sobald es Duelle gibt. Vor dem Ende des Draft stünde der Reiter leer;
      // dann öffnet sie auf der Übersicht, wo der nächste Schritt steht
      // (einladen, Draft starten).
      initialIndex: startReiter ?? LigaReiter.start(live.draftStatus),
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 12,
          title: VibrantLeagueTitle(
            name: live.name,
            logoUrl: live.logoUrl,
            logoEmoji: live.logoEmoji,
            logoColor: live.logoColor,
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Einstellungen',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => FantasyLeagueSettingsScreen(league: live),
                ),
              ),
            ),
          ],
          // Leise Reiter statt gefüllter Segmente: Der grüne Balken war das
          // lauteste Element des Schirms und sagte nur, welcher Reiter offen
          // ist.
          //
          // **Nur Wörter, in Versalien** (14.10.2026, auf Ansage). Davor trug
          // jeder Reiter ein Symbol über dem Wort, das MatchUp-Zeichen
          // eingeschlossen; die Leiste war damit 74 statt 52 Punkte hoch für
          // vier Auskünfte, die das Wort allein schon gibt.
          //
          // **Reihenfolge MatchUp · Kader · Übersicht · Tabelle** (auf
          // Ansage, 16.10.2026): das Duell und die eigene Elf sind, wofür man
          // die Liga am Spieltag öffnet. Die Positionen stehen in
          // [LigaReiter] — nie als nackte Zahl.
          bottom: const LeiseReiter(
            titel: ['MatchUp', 'Kader', 'Übersicht', 'Tabelle'],
            horizontal: 12,
            versalien: true,
          ),
        ),
        body: Vorwaermer(
          // Kader, Aufstellungen und Trades hängen an allen vier Reitern;
          // der Unterbau (Pool, Spielplan, Saison-Stats) an fast jedem Schirm
          // dahinter — Aufstellung, Free Agency, Spielerprofil.
          holt: (ref) {
            warmeFantasyUnterbau(ref);
            warmeFantasyLiga(ref, live.id);
          },
          child: TabBarView(
            children: [
              MatchupsBody(league: live),
              _RostersTab(league: live),
              _OverviewTab(league: live, isAdmin: isAdmin),
              FantasyTableBody(league: live),
            ],
          ),
        ),
      ),
    );
  }
}

/// Positionen der Liga-Reiter — eine Stelle, damit ein Umsortieren nicht
/// still einen Sprung ins falsche Ziel schickt.
abstract final class LigaReiter {
  static const matchup = 0;
  static const kader = 1;
  static const uebersicht = 2;
  static const tabelle = 3;

  /// Wo die Liga öffnet: MatchUp, sobald es Duelle gibt — vorher die
  /// Übersicht mit dem nächsten Schritt.
  static int start(DraftStatus status) =>
      status == DraftStatus.done ? matchup : uebersicht;
}

// ---------------------------------------------------------------------------
// Übersicht
// ---------------------------------------------------------------------------

// Signalfarben der Liga-Ansicht — nur noch für Zustände (Auftrag, Zähler,
// Playoffs). Die Symbolkreise der Aktionszeilen sind seit dem 15.10.2026
// grau (Design-Ideen Punkt 3).

/// Übersicht der Fantasy-Liga.
///
/// Umgesetzt ist „Richtung C" aus `design/liga-uebersicht/`: **Das Duell
/// führt.** In der laufenden Saison steht oben das eigene Head-to-Head, und
/// sein Sockel sagt, was ansteht („Aufstellung setzen"). Im Aufbau und im
/// Draft gibt es kein Duell — dort steht stattdessen der eine Auftrag, der
/// gerade dran ist (Richtung A). Darunter in beiden Fällen zwei kurze
/// Zeilengruppen: **Mein Team** und **Liga**.
///
/// Was dabei weggefallen ist: die 165 Punkte hohe Zustandskarte mit dem
/// halbtransparenten Dekor-Chevron (größte Fläche des Schirms für zwei
/// Wörter, und nicht antippbar), die Rubrik „Schnellzugriff" über zwei
/// gefüllten Kacheln, und die dritte Variante der Spielplan-Zeile.
class _OverviewTab extends ConsumerWidget {
  const _OverviewTab({required this.league, required this.isAdmin});

  final FantasyLeague league;
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Während des Resets (0143) gibt es keinen Transfermarkt: Die Kader
    // sind leer, und der Server lehnt jeden Zugang außer dem Draft ab.
    final drafted =
        league.draftStatus != DraftStatus.setup && !league.imReset;
    final draftFullyDone = league.draftStatus == DraftStatus.done;
    // Die Saison läuft auch während des Resets — Tabelle und Rückblick
    // bleiben, nur das Duell oben weicht dem Auftrag „Reset-Draft".
    final seasonRunning = league.saisonGestartet;
    final currentRound = ref.watch(fantasyCurrentRoundProvider).valueOrNull;
    final openTrades = ref.watch(incomingTradeOffersProvider(league.id));
    final managers = ref.watch(fantasyManagersProvider(league.id)).valueOrNull;
    final vorgemerkt = ref.watch(vorgemerkteTradesProvider(league.id)).length;
    final chatNeu = ref.watch(fantasyUnreadChatProvider(league.id));
    // Für die Transfers-Zeile: was auf mich wartet (eingehende Angebote plus
    // eigene offene Anträge), und wie viele Wechsel es in der Liga gab. Der
    // **Draft zählt dabei nicht** — er erzeugt bei sechzehn Teams Hunderte
    // Zeilen und ist keine Bewegung, die man nachliest.
    final offeneTransfers = ref.watch(offeneTransfersProvider(league.id));
    final bewegungen = [
      for (final m
          in ref.watch(rosterMovesProvider(league.id)).valueOrNull ??
              const <RosterMove>[])
        if (m.weg != 'draft' && m.weg != 'reset') m,
    ];

    void go(Widget screen) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 24),
      children: [
        // --- Kopf ----------------------------------------------------------
        if (seasonRunning && !league.imReset && currentRound != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: MatchupHero(
              league: league,
              round: currentRound,
              // **In den MatchUp-Reiter, nicht in eine Extra-Seite** (auf
              // Ansage, 14.10.2026). Dort steht dasselbe Duell samt
              // Aufstellungen; die Detailseite war eine zweite, abgeschlossene
              // Fassung davon. Gesprungen wird auf das eigene Duell des
              // aktuellen Spieltags.
              onTap: () {
                ref
                        .read(matchupKarussellSeiteProvider(league.id).notifier)
                        .state =
                    0;
                ref.read(matchupSprungProvider(league.id).notifier).state++;
                DefaultTabController.of(context).animateTo(LigaReiter.matchup);
              },
              fallback: _NaechsterSchritt(
                league: league,
                isAdmin: isAdmin,
                managerZahl: managers?.length,
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: _NaechsterSchritt(
              league: league,
              isAdmin: isAdmin,
              managerZahl: managers?.length,
            ),
          ),

        // Wochen-Recap (versteckt sich, bis es gewertete Punkte gibt).
        if (seasonRunning)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: WeeklyRecapCard(league: league),
          ),

        // --- Transfermarkt -------------------------------------------------
        // **Spieler und Trades stehen vorn** (auf Ansage, 16.10.2026). Sie
        // lagen als drei kleine Kacheln im Kader-Reiter über dem Feld und als
        // Zeilen hier — jetzt gibt es einen Ort, und der ist hier, groß.
        if (drafted) ...[
          const _Abschnittsmarke('Transfermarkt'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Expanded(
                  child: _FokusKachel(
                    titel: 'Spieler',
                    zeile: 'Verfügbar · Leaders',
                    icon: Icons.person_search_outlined,
                    onTap: () => go(FreeAgencyScreen(league: league)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _FokusKachel(
                    titel: 'Trades',
                    zeile: openTrades > 0
                        ? (openTrades == 1
                              ? 'Ein Angebot wartet'
                              : '$openTrades Angebote warten')
                        : vorgemerkt > 0
                        ? '$vorgemerkt warten auf den Spieltag'
                        : 'Angebot machen',
                    icon: Icons.swap_horiz,
                    zahl: openTrades,
                    onTap: () => go(TradeScreen(league: league)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _Zeilengruppe([
            // **Was die Liga bewegt hat** — eingehende Angebote und eigene
            // Anträge zählt der rote Zähler, darunter die Wechsel.
            _LigaZeile(
              label: 'Transfers',
              icon: Icons.compare_arrows,
              hinweis: bewegungen.isEmpty
                  ? null
                  : (bewegungen.length == 1
                        ? 'Ein Wechsel in der Liga'
                        : '${bewegungen.length} Wechsel in der Liga'),
              zahl: offeneTransfers,
              onTap: () => go(TransfersScreen(league: league)),
            ),
          ]),
        ],

        // --- Reset-Draft ---------------------------------------------------
        // **Das offizielle Board** (0145, auf Ansage).
        // Während der Hinrunde lassen sich die Picks handeln; das Board zeigt
        // die Reihenfolge nach der aktuellen Tabelle samt gehandelter Picks.
        // Nach dem Reset-Draft ist beides erledigt und verschwindet.
        if (league.resetAktiv &&
            league.saisonGestartet &&
            !(league.draftPhase == 'reset' &&
                league.draftStatus == DraftStatus.done)) ...[
          // Die eigenen Picks stehen nicht mehr hier (auf Ansage, 20.10.2026):
          // Sie stehen auf dem Board und im Kader unter der Bank.
          const _Abschnittsmarke('Reset-Draft'),
          _Zeilengruppe([
            _LigaZeile(
              label: 'Draft-Board',
              icon: Icons.grid_view_outlined,
              hinweis: league.resetErfolgtAt == null
                  ? 'Wo du gerade stehst'
                  : 'Reihenfolge steht fest',
              onTap: () =>
                  go(DraftBoardScreen(league: league, phase: 'reset')),
            ),
          ]),
        ],

        // **Kein Abschnitt „Mein Team" mehr** (auf Ansage, 17.10.2026): Die
        // Zeile „Aufstellung" führte nur in den Kader-Reiter, der direkt
        // nebenan liegt.

        // --- Liga ----------------------------------------------------------
        const _Abschnittsmarke('Liga'),
        _Zeilengruppe([
          if (!draftFullyDone)
            _LigaZeile(
              label: 'Draft-Raum',
              icon: Icons.meeting_room_outlined,
              hinweis: switch (league.draftStatus) {
                DraftStatus.setup => 'noch nicht gestartet',
                DraftStatus.reset => 'Reset-Draft wartet',
                DraftStatus.drafting => 'läuft',
                DraftStatus.done => null,
              },
              onTap: () => go(DraftRoomScreen(league: league)),
            ),
          // Ligainternes Tippspiel — nur wenn die Liga eines anbietet.
          if (league.tipEnabled ||
              ref.watch(fantasyTipRoundProvider(league.id)).valueOrNull != null)
            _LeagueTipspielButton(league: league, isAdmin: isAdmin),
          _LigaZeile(
            label: 'Liga-Chat',
            icon: Icons.forum_outlined,
            hinweis: chatNeu ? 'Neue Nachrichten' : null,
            onTap: () => go(FantasyChatScreen(league: league)),
          ),
          if (!draftFullyDone && !league.saisonGestartet)
            _LigaZeile(
              label: 'Spieler einladen',
              icon: Icons.person_add_alt_1,
              hinweis: managers == null ? null : '${managers.length} dabei',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => InvitePlayersScreen(league: league),
                ),
              ),
            ),
        ]),

        // --- Spieltag ------------------------------------------------------
        _MatchdayFixtures(league: league),
      ],
    );
  }
}

/// Der eine Auftrag, der gerade dran ist — Kopf des Schirms in allen Phasen
/// ohne laufendes Duell.
///
/// Vorher stand hier eine Zustandsmeldung („Setup") in einer 165 Punkte hohen
/// Karte, die nicht antippbar war; was zu tun ist, steckte hinter einer Kachel
/// weiter unten. Ein Zustand ist kein Auftrag.
class _NaechsterSchritt extends ConsumerWidget {
  const _NaechsterSchritt({
    required this.league,
    required this.isAdmin,
    this.managerZahl,
  });

  final FantasyLeague league;
  final bool isAdmin;
  final int? managerZahl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final gold = const Color(0xFFFFC83D);

    void openRoom() => Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => DraftRoomScreen(league: league)));

    final (
      String titel,
      String knopf,
      VoidCallback tun,
    ) = switch (league.draftStatus) {
      DraftStatus.setup =>
        league.maxTeams != null && managerZahl != null
            ? (
                'Noch ${(league.maxTeams! - managerZahl!).clamp(0, 99)} Plätze frei',
                'Spieler einladen',
                () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => InvitePlayersScreen(league: league),
                  ),
                ),
              )
            : (
                'Die Liga steht',
                'Spieler einladen',
                () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => InvitePlayersScreen(league: league),
                  ),
                ),
              ),
      // **Reset zur Winterpause** (0143): Der Admin startet den Draft
      // selbst, alle anderen warten im Raum.
      DraftStatus.reset => isAdmin
          ? (
              'Reset zur Winterpause',
              'Reset-Draft starten',
              () async {
                final gestartet =
                    await draftStartenMitBestaetigung(context, ref, league);
                if (gestartet && context.mounted) openRoom();
              },
            )
          : ('Reset zur Winterpause', 'Zum Draft-Raum', openRoom),
      DraftStatus.drafting => (
        league.draftPhase == 'reset'
            ? 'Der Reset-Draft läuft'
            : 'Der Draft läuft',
        'Zum Draft',
        openRoom,
      ),
      DraftStatus.done => (
        'Die Saison läuft',
        'Aufstellung',
        () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => LineupScreen(league: league))),
      ),
    };

    // **Luft statt Gedränge** (19.10.2026, gemeldet: „sieht zusammengequetscht
    // aus"). Vorher standen Marke, Titel, ein Satz und zwei Knöpfe
    // nebeneinander in knappem Polster — „Spieler einladen" brach im Knopf auf
    // zwei Zeilen um. Jetzt: die Zahl groß, ein Balken für die Plätze, kein
    // Erklärsatz, die Knöpfe untereinander in voller Breite.
    final belegt = managerZahl;
    final gesamt = league.maxTeams;
    final mitBalken =
        league.draftStatus == DraftStatus.setup &&
        belegt != null &&
        gesamt != null &&
        gesamt > 0;
    final hoch = const Size.fromHeight(50);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Karte(
        hauch: gold,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'ALS NÄCHSTES',
              style: TextStyle(
                color: gold,
                fontSize: Schrift.label,
                fontWeight: Schrift.ueberschriftGewicht,
                fontStyle: Schrift.ueberschriftStil,
                letterSpacing: 1.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              titel,
              style: const TextStyle(
                fontSize: Schrift.gross,
                fontWeight: FontWeight.w800,
                height: 1.15,
              ),
            ),
            if (league.draftStatus == DraftStatus.reset) ...[
              const SizedBox(height: 8),
              Text(
                'Alle Kader sind geleert, die Tabelle bleibt. Im Draft pickt '
                'der Tabellenletzte zuerst.',
                style: TextStyle(
                  fontSize: Schrift.text,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            if (mitBalken) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: (belegt / gesamt).clamp(0.0, 1.0),
                  minHeight: 6,
                  color: gold,
                  backgroundColor: scheme.onSurface.withValues(alpha: 0.08),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$belegt von $gesamt Teams',
                style: TextStyle(
                  fontSize: Schrift.label,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton(
              onPressed: tun,
              style: FilledButton.styleFrom(
                backgroundColor: gold,
                foregroundColor: scheme.surface,
                minimumSize: hoch,
              ),
              child: Text(knopf),
            ),
            // Den Draft startet nur der Ersteller — und nur, solange er noch
            // nicht läuft. Der Knopf **startet** ihn auch, statt bloß den Raum
            // zu öffnen; die Rückfrage steckt in `draftStartenMitBestaetigung`
            // und kommt auf beiden Wegen.
            if (isAdmin && league.draftStatus == DraftStatus.setup) ...[
              const SizedBox(height: 10),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: hoch,
                  // Grau statt Grün: Ein Knopf läuft nicht, er wartet.
                  foregroundColor: scheme.onSurface,
                  side: BorderSide(color: Theme.of(context).dividerColor),
                ),
                onPressed: () async {
                  final gestartet = await draftStartenMitBestaetigung(
                    context,
                    ref,
                    league,
                  );
                  // Nach dem Start gehört man in den Raum — dort läuft ab
                  // jetzt die Uhr.
                  if (gestartet && context.mounted) openRoom();
                },
                child: const Text('Draft starten'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Kapitelmarke wie im Live-, Favoriten- und Menü-Schirm — **mit dem
/// farbigen Strich des Bereichs**. Grau auf Grau trennten die drei Rubriken
/// der Übersicht nichts; der Strich gliedert, ohne eine Fläche einzufärben
/// (dieselben Farben wie in den Fantasy-Einstellungen: Mein Team türkis,
/// Liga grün).
class _Abschnittsmarke extends StatelessWidget {
  const _Abschnittsmarke(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14),
    child: Kapitelmarke(text),
  );
}

/// **Große Kachel des Transfermarkts** — Spieler und Trades, nebeneinander.
///
/// Eine Karte, weil man sie antippt (Design-Ideen Punkt 1). Symbol grau,
/// Farbe trägt nur der rote Zähler, wenn ein Angebot wartet.
class _FokusKachel extends StatelessWidget {
  const _FokusKachel({
    required this.titel,
    required this.zeile,
    required this.icon,
    required this.onTap,
    this.zahl = 0,
  });

  final String titel;
  final String zeile;
  final IconData icon;
  final VoidCallback onTap;
  final int zahl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: [titel, zeile, if (zahl > 0) '$zahl offen'].join(', '),
      excludeSemantics: true,
      child: Karte(
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.onSurface.withValues(alpha: 0.07),
                  ),
                  child: Icon(icon, size: 22, color: scheme.onSurface),
                ),
                const Spacer(),
                if (zahl > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.error,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$zahl',
                      style: TextStyle(
                        color: scheme.onError,
                        fontSize: Schrift.label,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                else
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              titel,
              style: const TextStyle(
                fontSize: Schrift.titel,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              zeile,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: Schrift.label,
                fontWeight: FontWeight.w600,
                color: zahl > 0 ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Eine Aktion der Übersicht: farbiges Symbol, Beschriftung, optional ein
/// leiser Zusatz und ein roter Zähler.
///
/// Zwischenstand war die reine Textzeile — sie ersetzte die gefüllten
/// „Schnellzugriff"-Kacheln und war dann zu leise: Draft-Raum, Liga-Chat und
/// „Spieler einladen" lasen sich nicht mehr als Knöpfe. Das Symbol in seiner
/// getönten Kachel gibt ihnen das Gewicht zurück, ohne dass die Fläche wieder
/// den halben Schirm einnimmt: 36 Punkte statt eines 44er-Kreises auf einer
/// 100 Punkte hohen Karte. Die Farbe trägt das Symbol, nicht der Text.
/// Eine Gruppe von [_LigaZeile] auf **eigener Fläche**.
///
/// Vorher lagen die Zeilen nackt auf dem Grund des Schirms, nur durch
/// Haarlinien getrennt. Zwischen dem Duell-Kasten oben und dem Spieltag unten —
/// beides Bereiche mit Fläche und Inhalt — war die Mitte damit das Flachste,
/// was es gibt: fünf Wörter untereinander. „Trostlos" war die Rückmeldung, und
/// sie war berechtigt.
///
/// Dieselbe Sprache wie die Karten auf dem Startbildschirm: Kartengrund,
/// Haarlinie, runde Ecken. **Keine gefüllten Kacheln** — die gab es hier
/// schon einmal als „Schnellzugriff" und sie nahmen den halben Schirm ein.
class _Zeilengruppe extends StatelessWidget {
  const _Zeilengruppe(this.zeilen);

  final List<Widget> zeilen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      // Dieselbe Hülle wie der Rückblick und der MatchUp-Kasten: eine Kante
      // für alle. Die Zeilen bringen ihren eigenen Innenabstand mit, deshalb
      // hat die Karte hier keinen.
      child: Karte(
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < zeilen.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    indent: 68,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.07),
                  ),
                zeilen[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LigaZeile extends StatelessWidget {
  const _LigaZeile({
    required this.label,
    required this.icon,
    required this.onTap,
    this.hinweis,
    this.zahl = 0,
  });

  final String label;
  final IconData icon;

  /// `null` = die Zeile ist da, aber (noch) nicht bedienbar. Sie bekommt dann
  /// **kein** `InkWell`: Eine Zeile, die auf Tippen reagiert und nichts tut,
  /// verspricht etwas, das es nicht gibt.
  final VoidCallback? onTap;

  /// Leiser Zusatz rechts („läuft", „3 dabei").
  final String? hinweis;

  /// Roter Zähler — etwas wartet auf dich.
  final int zahl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: [label, ?hinweis, if (zahl > 0) '$zahl offen'].join(', '),
      onTap: onTap,
      excludeSemantics: true,
      child: Opacity(
        opacity: onTap == null ? 0.55 : 1,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  // **Grau, nicht bunt** (Design-Ideen Punkt 3, 15.10.2026).
                  // Fünf Kreise in fünf Farben sagten nur „hier ist eine
                  // Zeile"; Farbe trägt in dieser Zeile allein, was wartet —
                  // der rote Zähler und der goldene Auftrag.
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.onSurface.withValues(alpha: 0.07),
                  ),
                  child: Icon(icon, size: 20, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(width: 14),
                Expanded(
                  // **Der Hinweis steht jetzt unter dem Wort, nicht daneben.**
                  // Rechtsbündig war er ein Zusatz, den man übersah; als zweite
                  // Zeile gibt er der Zeile Inhalt. Fünf Zeilen, die alle nur
                  // ein Wort trugen, waren zwischen dem Duell-Kasten oben und
                  // dem Spieltag unten das Flachste auf dem Schirm.
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                        ),
                      ),
                      if (hinweis != null) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                hinweis!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: Schrift.label,
                                  fontWeight: FontWeight.w500,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (zahl > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    constraints: const BoxConstraints(minWidth: 20),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: MatchUpColors.red,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$zahl',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                // Der Pfeil sitzt in einer kleinen Mulde: Er bleibt leise, liest
                // sich aber als Knopf statt als Satzzeichen.
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LeagueTipspielButton extends ConsumerWidget {
  const _LeagueTipspielButton({required this.league, required this.isAdmin});

  final FantasyLeague league;
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final round = ref.watch(fantasyTipRoundProvider(league.id)).valueOrNull;

    if (round != null) {
      return _TipTile(
        title: 'Tippspiel öffnen',
        onTap: () {
          activateRound(ref, round);
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => LeagueScreen(round: round)));
        },
      );
    }
    if (isAdmin) {
      return _TipTile(
        title: 'Ligainternes Tippspiel aktivieren',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CreateTipRoundScreen(
              fantasyLeagueId: league.id,
              initialName: league.name,
            ),
          ),
        ),
      );
    }
    // Mitglied, aber noch nicht aktiviert.
    return const _TipTile(
      title: 'Ligainternes Tippspiel — noch nicht aktiviert',
    );
  }
}

/// Flache Zeile für den Ligainternen-Tippspiel-Button (gelber Akzent, ohne
/// Box, ohne Untertitel; deaktiviert = ausgegraut).
class _TipTile extends StatelessWidget {
  const _TipTile({required this.title, this.onTap});

  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Benutzt dieselbe Zeile wie die Nachbarn. Vorher zeichnete sie sich
    // selbst — blankes Symbol statt getönter Kachel, andere Abstände, andere
    // Schriftgröße. In der Zeilengruppe fiel das sofort auf.
    return _LigaZeile(
      label: title,
      icon: Icons.emoji_events_outlined,
      onTap: onTap,
    );
  }
}

// ---------------------------------------------------------------------------
// Kader
// ---------------------------------------------------------------------------

/// Kader-Tab: oben der Aufstellungs-Editor, darunter die Aktionen
/// Free Agency (gelb), Trade (rot) und Transfers (blau).
class _RostersTab extends ConsumerWidget {
  const _RostersTab({required this.league});

  final FantasyLeague league;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drafted = league.draftStatus != DraftStatus.setup;
    if (!drafted) {
      return Stack(
        children: [
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Die Kader entstehen im Draft — sobald er läuft, stellst du '
                'hier deine Elf auf, holst Free Agents und tradest.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DraftRoomScreen(league: league),
                ),
              ),
              icon: const Icon(Icons.sports_esports_outlined),
              label: const Text('Zum Draft'),
            ),
          ),
        ],
      );
    }

    void open(Widget page) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

    final myId = ref.watch(currentUserProvider)?.id;
    final roster =
        ref.watch(leagueRosterProvider(league.id)).valueOrNull ??
        const <RosterEntry>[];
    final myCount = myId == null ? 0 : rosterCountOf(myId, roster);
    final vorgemerkt = ref.watch(vorgemerkteTradesProvider(league.id));

    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        RosterLimitBanner(count: myCount, limit: league.roster.squadSize),
        // **Keine Kacheln mehr über dem Feld** (16.10.2026): Spieler, Trades
        // und Transfers stehen auf der Übersicht unter „Transfermarkt". Der
        // Kader-Reiter ist die eigene Elf — sonst nichts.
        // Beschlossene, aber noch nicht vollzogene Trades. Nur da, wenn es
        // welche gibt — eine Zeile „0 offene Trades" wäre eine Meldung über
        // nichts. Sie steht **über** dem Aufstellungs-Editor: Wer seine Elf
        // stellt, muss wissen, dass sich der Kader nach dem Spieltag noch
        // ändert.
        if (vorgemerkt.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: _VorgemerkteTradesZeile(
              anzahl: vorgemerkt.length,
              onTap: () => open(VorgemerkteTradesScreen(league: league)),
            ),
          ),
        LineupEditor(league: league),
      ],
    );
  }
}

/// Hinweiszeile im Kader-Tab: Es sind Trades abgemacht, die erst nach dem
/// Spieltag greifen.
///
/// Bewusst eine ruhige Zeile und keine der farbigen Aktions-Kacheln daneben:
/// Hier ist nichts zu tun, es ist eine **Auskunft**. Antippbar ist sie
/// trotzdem, weil die Frage „welche denn?" unmittelbar folgt.
class _VorgemerkteTradesZeile extends StatelessWidget {
  const _VorgemerkteTradesZeile({required this.anzahl, required this.onTap});

  final int anzahl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: kartenDeko(context, hauch: scheme.primary, radius: 12),
          child: Row(
            children: [
              Icon(Icons.schedule_outlined, size: 18, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      anzahl == 1
                          ? 'Ein offener Trade'
                          : '$anzahl offene Trades',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'Beschlossen — die Kader wechseln erst nach dem Spieltag.',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Die Partien des aktuellen Spieltags, unten in der Übersicht.
///
/// Benutzt dieselbe Zeilenform wie Live- und Favoriten-Tab
/// (`fixturesWithDateHeaders`) statt einer eigenen Box mit eigener Anordnung.
/// Der Spielplan kommt hier als [Fixture] und wird dafür auf [TeamFixture]
/// gedreht — dieselben Felder, nur ein anderer Einstiegspunkt in dieselben
/// Daten. Drei Darstellungen derselben Liste waren zwei zu viel.
class _MatchdayFixtures extends ConsumerWidget {
  const _MatchdayFixtures({required this.league});

  final FantasyLeague league;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final round = ref.watch(fantasyCurrentRoundProvider).valueOrNull;
    final all = ref.watch(fantasySeasonFixturesProvider).valueOrNull;
    if (round == null || all == null) return const SizedBox.shrink();
    final fx = [
      for (final f in all)
        if (f.round == round) f,
    ]..sort((a, b) => a.kickoff.compareTo(b.kickoff));
    if (fx.isEmpty) return const SizedBox.shrink();

    final liga = Leagues.byId(fx.first.leagueId);
    final umgewandelt = [
      for (final f in fx)
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Abschnittsmarke('$round. Spieltag'),
        // Ohne Wettbewerb: Die Marke direkt darüber sagt den Spieltag, und
        // diese Liste zeigt nur die eine Liga der Fantasy-Runde.
        //
        // **Auf eigener Fläche**, wie die beiden Gruppen darüber und die
        // Wettbewerbe im Live-Tab. Lose auf dem Grund war der Spieltag das
        // Einzige auf dem Schirm ohne Kante und sah aus wie angehängt.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Karte(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: fixturesWithDateHeaders(
                umgewandelt,
                mitWettbewerb: false,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
