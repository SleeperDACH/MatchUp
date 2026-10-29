import '../../../app/farben.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import '../../../app/typografie.dart';
import '../../../app/widgets/leise_reiter.dart';
import '../../../app/widgets/skelett.dart';
import '../../../app/widgets/info_knopf.dart';
import '../../../app/widgets/punktzahl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/widgets/pill_selector.dart';
import '../../../core/models/models.dart';
import '../../auth/providers.dart';
import '../logic/fantasy_scoring_engine.dart';
import '../logic/saison_punkte.dart';
import '../logic/waiver_fenster.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';
import 'club_badge.dart';
import 'player_action_buttons.dart';
import 'player_profile_sheet.dart';
import 'waiver_claims_screen.dart';

/// Free Agency & Waiver-Wire.
///
/// * Echte Free Agents (nie gedraftet oder vom Wire gefallen) sind sofort
///   holbar — respektiert Kadergröße (sonst Drop nötig) und die 05.09.-Sperre.
/// * Frisch gedroppte Spieler liegen 24 Stunden auf dem Waiver-Wire und sind
///   nur per Antrag holbar; nach Ablauf werden die Anträge in
///   Prioritätsreihenfolge abgearbeitet, sonst wird der Spieler frei.
/// * **Spieler in fremden Kadern stehen mit drin** — darunter, als zweite
///   Gruppe, mit dem Team des Besitzers und einem Trade-Knopf statt „Holen".
///   Die Spielersuche war bis dahin ein eigener Schirm mit derselben Liste in
///   anderer Reihenfolge; zwei Listen derselben Spieler nebeneinander zu
///   pflegen war die eigentliche Fehlerquelle.
///
/// Sortiert wird in **beiden** Gruppen nach den Punkten der laufenden Saison
/// (`saisonPunkte`). Die Gruppen bleiben getrennt, weil sie verschiedene
/// Handlungen tragen: oben holen, unten fragen.
class FreeAgencyScreen extends ConsumerStatefulWidget {
  const FreeAgencyScreen({super.key, required this.league, this.jetzt});

  final FantasyLeague league;

  /// **Nur für Vorschauen.** Der Schirm rechnet sonst mit `DateTime.now()`,
  /// und damit hinge sein Bild am Wochentag des Testlaufs: „Waiver bis Mo,
  /// 15:00" wird in einer englischen Woche zu „Do, 15:00". Ein fest
  /// eingecheckter Vergleich wäre dann nicht erst am nächsten Tag rot, sondern
  /// an einem beliebigen — und niemand wüsste, warum.
  final DateTime? jetzt;

  @override
  ConsumerState<FreeAgencyScreen> createState() => _FreeAgencyScreenState();
}

class _FreeAgencyScreenState extends ConsumerState<FreeAgencyScreen> {
  String _query = '';
  PlayerPosition? _position;

  /// Leaders nur mit freien Spielern (auf Ansage, 16.10.2026) — der Rang
  /// bleibt der in der ganzen Liga, damit man sieht, wo ein Free Agent steht.
  bool _leadersNurFrei = false;

  /// **Eine Uhr für den Schirm.**
  ///
  /// Ob ein Spieler frei ist oder auf dem Waiver liegt, entscheidet ein
  /// Zeitpunkt: der Anpfiff seines Vereins. `jetzt` wurde aber **einmal je
  /// Aufbau** gerechnet, und nichts baute den Schirm neu, wenn dieser
  /// Zeitpunkt vorbeiging. Wer die Liste um 18:20 offen hatte, sah für einen
  /// Schalker um 18:35 immer noch das grüne Plus — und der Server antwortete
  /// dann mit „Er liegt auf dem Waiver – bitte per Antrag holen".
  ///
  /// Gemeldet als „ich habe versucht, einen Waiver-Antrag zu stellen, das hat
  /// aber nicht funktioniert". **Die Regel war auf beiden Seiten dieselbe, nur
  /// die Uhr des Clients stand.**
  ///
  /// **Ein einmaliger Timer auf den nächsten Anpfiff**, kein Sekundentakt:
  /// Zwischen zwei Anpfiffen ändert sich an dieser Frage nichts, und die Liste
  /// sortiert bei jedem Aufbau den ganzen Spielerpool. Dieselbe Bauart wie
  /// beim Nachladen der Live-Punkte.
  Timer? _uhr;

  @override
  void dispose() {
    _uhr?.cancel();
    super.dispose();
  }

  /// Weckt den Schirm zum nächsten Zeitpunkt, an dem sich etwas ändern kann:
  /// dem nächsten Anpfiff, sonst der Waiver-Frist.
  void _planeNaechstenTakt(List<Fixture> spiele, DateTime jetzt) {
    // Eine feste Uhr aus der Vorschau darf nicht weiterlaufen.
    if (widget.jetzt != null) return;
    DateTime? naechster;
    for (final f in spiele) {
      final k = f.kickoff.toLocal();
      if (!k.isAfter(jetzt)) continue;
      if (naechster == null || k.isBefore(naechster)) naechster = k;
    }
    final runde = wireRunde(spiele, jetzt);
    if (runde != null) {
      final frist = waiverFrist(spiele, runde);
      if (frist != null &&
          frist.isAfter(jetzt) &&
          (naechster == null || frist.isBefore(naechster))) {
        naechster = frist;
      }
    }
    _uhr?.cancel();
    if (naechster == null) return;
    // Eine Sekunde Zugabe, damit der Weckruf **nach** dem Anpfiff liegt und
    // nicht auf die Sekunde davor fällt.
    final dauer = naechster.difference(jetzt) + const Duration(seconds: 1);
    _uhr = Timer(dauer, () {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final league = widget.league;
    final poolAsync = ref.watch(playerPoolProvider);
    final roster =
        ref.watch(leagueRosterProvider(league.id)).valueOrNull ??
        const <RosterEntry>[];
    final onWaivers =
        ref.watch(waiverPlayersProvider(league.id)).valueOrNull ??
        const <String>{};
    final claims =
        ref.watch(myWaiverClaimsProvider(league.id)).valueOrNull ??
        const <WaiverClaim>[];
    final clubIcons =
        ref.watch(clubIconsProvider).valueOrNull ?? const <String, String?>{};
    final myId = ref.watch(currentUserProvider)?.id;

    // **Welche Vereine spielen gerade?** Dieselbe Regel wie auf dem Server
    // (`fantasy_spieler_laeuft`, Migration 0094): die niedrigste noch nicht
    // vollständig abgepfiffene Runde, und darin der Anpfiff je Verein.
    final spiele =
        ref.watch(fantasySeasonFixturesProvider).valueOrNull ??
        const <Fixture>[];
    final jetzt = widget.jetzt ?? DateTime.now();
    _planeNaechstenTakt(spiele, jetzt);
    // **Die Waiver-Regel, nicht die Anpfiff-Regel.** Ein Spieler bleibt nach
    // dem Anpfiff seines Vereins bis zur Frist auf dem Waiver — nicht nur, bis
    // der Spieltag durch ist. `wireRunde` liefert `null`, sobald die Frist
    // vorbei ist; dann ist wieder alles direkt zu holen.
    final wireR = wireRunde(spiele, jetzt);
    final frist = wireR == null ? null : waiverFrist(spiele, wireR);
    final ausfaelle =
        ref.watch(absencesProvider).valueOrNull ?? const <String, dynamic>{};

    final pendingClaims = claims.where((c) => c.status.isPending).toList();
    final claimedPlayerIds = {for (final c in pendingClaims) c.addPlayerId};

    final managers =
        ref.watch(fantasyManagersProvider(league.id)).valueOrNull ??
        const <FantasyManager>[];
    final teamName = {for (final m in managers) m.userId: m.display};
    final ownerByPlayer = {for (final r in roster) r.playerId: r.managerId};
    final saison =
        ref.watch(seasonStatsProvider).valueOrNull ??
        const <int, Map<String, PlayerMatchStats>>{};

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          // **„Spieler" statt „Free Agency"** (auf Ansage, 16.10.2026): Der
          // Schirm zeigt zwei Dinge — wen man holen kann und wer die Besten
          // sind. „Free Agency" beschrieb nur das erste.
          title: const Text('Spieler'),
          bottom: const LeiseReiter(
            titel: ['Verfügbar', 'Leaders'],
            horizontal: 12,
            versalien: true,
          ),
          actions: [
            IconButton(
              tooltip: 'Meine Anträge',
              icon: Badge(
                isLabelVisible: pendingClaims.isNotEmpty,
                label: Text('${pendingClaims.length}'),
                child: const Icon(Icons.assignment_outlined),
              ),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => WaiverClaimsScreen(league: league),
                ),
              ),
            ),
          ],
        ),
        body: poolAsync.when(
          loading: () => const Skelett(),
          error: (e, _) => Center(child: Text('Fehler: $e')),
          data: (pool) {
            final playerById = {for (final p in pool) p.id: p};
            final rosteredIds = {for (final r in roster) r.playerId};
            final myPlayers = [
              for (final r in roster)
                if (r.managerId == myId && playerById[r.playerId] != null)
                  playerById[r.playerId]!,
            ];

            final punkte = saisonPunkte(
              saison: saison,
              spieler: playerById,
              regeln: league.scoring,
            );
            // Je Spieler die Einsätze — der Schnitt zählt nur Spieltage, an
            // denen er gespielt hat (16.10.2026).
            final einsaetze = einsaetzeJeSpieler(saison);

            // **Alle Spieler, nicht nur die freien** — gefiltert wie gehabt,
            // sortiert nach der Regel „freie zuerst, in jeder Gruppe die besten".
            //
            // Ausgenommen sind Abgewanderte: Wer die Bundesliga verlassen hat,
            // steht hier nicht mehr, auch wenn seine Zeile im Pool bleiben muss
            // (Draft-Brett, gespielte Spieltage).
            final gefiltert = pool
                .where((p) => !p.abgewandert)
                .where((p) => _position == null || p.position == _position)
                .where(
                  (p) =>
                      _query.isEmpty ||
                      p.name.toLowerCase().contains(_query.toLowerCase()) ||
                      p.club.toLowerCase().contains(_query.toLowerCase()),
                )
                .toList();
            // **Verfügbar**: nur, wer frei ist — nach Saisonpunkten.
            final verfuegbar = freieZuerst(
              [
                for (final p in gefiltert)
                  if (!rosteredIds.contains(p.id)) p,
              ],
              inKadern: const {},
              punkte: punkte,
            );
            // **Leaders**: alle, nach Saisonpunkten — wer die besten Spieler
            // der Saison sind, egal wem sie gehören (auf Ansage, 16.10.2026).
            final leaders = freieZuerst(
              gefiltert,
              inKadern: const {},
              punkte: punkte,
            );

            Widget zeileFuer(FantasyPlayer p, {int? rang}) {
              final imKader = rosteredIds.contains(p.id);
              final waiver = onWaivers.contains(p.id);
              final claimed = claimedPlayerIds.contains(p.id);
              final aufWire = vereinAufWire(p.club, spiele, jetzt);
              return ListTile(
                // **Der Name führt ins Profil.** Wer entscheiden soll,
                // ob er einen Spieler holt, braucht mehr als Verein und
                // Position — Leistung, Spielplan und die
                // voraussichtliche Aufstellung stehen dort. Die Zeile
                // reagierte vorher gar nicht; nur der Knopf rechts tat
                // etwas.
                onTap: () => showPlayerProfile(
                  context,
                  league: league,
                  player: p,
                  clubIcon: clubIcons[p.club],
                  isMine: false,
                ),
                // In den Leaders steht der Rang vor dem Wappen — die
                // Liste ist eine Bestenliste, keine Auswahl.
                leading: rang == null
                    ? ClubBadge(club: p.club, iconUrl: clubIcons[p.club])
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 26,
                            child: Text(
                              '$rang',
                              style: TextStyle(
                                fontSize: Schrift.text,
                                fontWeight: FontWeight.w800,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                          ClubBadge(club: p.club, iconUrl: clubIcons[p.club]),
                        ],
                      ),
                // **Die Punkte stehen dran, weil danach sortiert
                // wird.** Eine Reihenfolge ohne sichtbaren Grund liest
                // sich wie keine. Wer keinen Einsatz hatte, bekommt
                // nichts hingeschrieben — „0" wäre eine Behauptung über
                // jemanden, der gar nicht gespielt hat.
                // **Zwei Zahlen übereinander: Summe oben, Schnitt
                // darunter.** Danach wird sortiert, und beide zusammen
                // sind die Frage, die man an einen freien Spieler hat —
                // die Summe sagt, was er gebracht hat, der Schnitt, was
                // er je Spieltag bringt. Wer im Winter kam oder verletzt
                // war, hat eine kleine Summe und kann trotzdem der
                // bessere sein.
                //
                // Den Platz dafür gab die Zeile „Waiver bis Mo, 15:00"
                // her: Sie stand wortgleich in jeder Zeile, obwohl die
                // Frist für alle dieselbe ist und **einmal** über der
                // Liste steht. Eine Auskunft, die sich je Zeile nicht
                // unterscheidet, gehört nicht in die Zeile.
                title: Row(
                  children: [
                    Expanded(child: Text(p.name)),
                    if (punkte[p.id] != null) ...[
                      const SizedBox(width: 8),
                      Punktzahl(
                        punkte[p.id]!,
                        negativRot: true,
                        stil: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
                subtitle: Row(
                  children: [
                    PositionPill(pos: p.position),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        [
                          // **Kein Vereinsname** (auf Ansage, 16.10.2026):
                          // Das Wappen links sagt ihn schon, und ohne ihn
                          // bleibt die Zeile für das, was sich je Spieler
                          // unterscheidet — wem er gehört, ob er ausfällt.
                          if (imKader)
                            teamName[ownerByPlayer[p.id]] ?? 'vergeben',
                          // **Wer ausfällt, gehört hier genannt.**
                          // Einen verletzten Spieler zu holen ist der
                          // teuerste Fehler in der Free Agency.
                          if (ausfaelle[p.id] != null) ausfaelle[p.id]!.kurz,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ausfaelle[p.id] == null
                            ? null
                            : TextStyle(
                                color: ausfaelle[p.id]!.gesperrt
                                    ? context.farben.rot
                                    : context.farben.gold,
                              ),
                      ),
                    ),
                    // **Das Ø sagt, was die Zahl ist.** Ohne es läse
                    // sich 6,1 als zweite Summe — und die ist bei einem
                    // Spieler mit zwölf Spieltagen zehnmal so hoch.
                    if (punkte[p.id] != null && (einsaetze[p.id] ?? 0) > 0) ...[
                      const SizedBox(width: 8),
                      Text(
                        'Ø ${formatPoints(punkte[p.id]! / einsaetze[p.id]!)}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ],
                ),
                trailing: PlayerActionButton(
                  aufWire: aufWire,
                  league: league,
                  player: p,
                  ownerId: ownerByPlayer[p.id],
                  onWaiver: waiver,
                  claimed: claimed,
                  myPlayers: myPlayers,
                  nextRank: pendingClaims.length + 1,
                  myId: myId,
                ),
              );
            }

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Spieler oder Verein suchen',
                      contentPadding: EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      _chip(
                        'Alle',
                        _position == null,
                        () => setState(() => _position = null),
                      ),
                      for (final pos in PlayerPosition.values)
                        _chip(
                          pos.label,
                          _position == pos,
                          () => setState(() => _position = pos),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      Column(
                        children: [
                          // Die Waiver-Frist gehört zu dem, was man holen kann.
                          _WaiverBanner(frist: frist),
                          Expanded(
                            child: ListView.builder(
                              itemCount: verfuegbar.length,
                              itemBuilder: (context, i) =>
                                  zeileFuer(verfuegbar[i]),
                            ),
                          ),
                        ],
                      ),
                      Builder(builder: (context) {
                        final rangVon = {
                          for (final (i, p) in leaders.indexed) p.id: i + 1,
                        };
                        final sichtbar = _leadersNurFrei
                            ? [
                                for (final p in leaders)
                                  if (!rosteredIds.contains(p.id)) p,
                              ]
                            : leaders;
                        return Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                              child: Row(
                                children: [
                                  _chip(
                                    'Alle Spieler',
                                    !_leadersNurFrei,
                                    () =>
                                        setState(() => _leadersNurFrei = false),
                                  ),
                                  _chip(
                                    'Nur Free Agents',
                                    _leadersNurFrei,
                                    () =>
                                        setState(() => _leadersNurFrei = true),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: ListView.builder(
                                itemCount: sichtbar.length,
                                itemBuilder: (context, i) => zeileFuer(
                                  sichtbar[i],
                                  rang: rangVon[sichtbar[i].id],
                                ),
                              ),
                            ),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// **Kein `ChoiceChip`.** Es zieht seine Auswahlfarbe aus
  /// `secondaryContainer` — aus dem grünen Seed dieser App wird das ein
  /// stumpfes Oliv, und seine Beschriftung erbt die App-Schrift nicht: In der
  /// ersten Vorschau dieses Schirms standen dort schwarze Balken statt
  /// „Tor", „Abwehr", „Mittelfeld", „Sturm". Die Regel steht seit langem in
  /// CLAUDE.md; dieser Schirm hatte sie nur nie jemand angesehen.
  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: PillChip(label: label, selected: selected, onTap: onTap),
  );
}

/// Hinweis auf die Waiver-Regel — **und darauf, welche Phase gerade läuft.**
///
/// Die beiden Zustände sind verschiedene Spiele: Im Fenster wird beantragt und
/// zur Frist nach Priorität vergeben; danach zählt, wer zuerst tippt. Ein
/// Balken, der immer dasselbe sagt, verschweigt genau den Unterschied.
class _WaiverBanner extends StatelessWidget {
  const _WaiverBanner({required this.frist});

  /// Ende des laufenden Waivers — `null` in der freien Phase.
  final DateTime? frist;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // **Nicht `secondaryContainer`.** Aus dem grünen Seed wird das ein stumpfes
    // Oliv, und ein olivgrüner Balken über der ganzen Breite sagt nichts —
    // hier läuft nichts, hier steht eine Regel. Die Farbe des Waivers ist
    // Gold, und sie trägt nur den Hauch, den ein Hinweis braucht.
    return Container(
      width: double.infinity,
      color: context.farben.gold.withValues(alpha: 0.10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.schedule_outlined, size: 18, color: context.farben.gold),
          const SizedBox(width: 8),
          // **Die Auskunft, nicht die Regel** (Design-Ideen Punkt 4). Wie
          // der Waiver arbeitet, steht hinter dem ⓘ — gelesen wird es
          // einmal, die Frist bei jedem Besuch.
          Expanded(
            child: Text(
              frist == null
                  ? 'Freie Bahn — direkt holen'
                  : 'Waiver bis ${fristKurz(frist!)}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(
            height: 20,
            width: 28,
            child: OverflowBox(
              maxHeight: 44,
              maxWidth: 44,
              child: InfoKnopf(
                titel: 'So funktioniert der Waiver',
                text:
                    'Ab dem Anpfiff seines Vereins liegt ein freier Spieler '
                    'auf dem Waiver: Holen geht dann nur per Antrag. Bis '
                    'Montag 15:00 (in englischen Wochen Donnerstag) werden '
                    'die Anträge nach Priorität vergeben, danach ist wieder '
                    'freie Bahn.\n\nGedroppte Spieler liegen außerhalb dieser '
                    'Zeit 24 Stunden auf dem Waiver.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
