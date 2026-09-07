import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/fantasy/providers.dart';
import '../features/news/providers.dart';
import '../features/tippspiel/providers.dart';

/// **Was ein Tipp gleich braucht, wird vorher geholt.**
///
/// Gemeldet: *„Auch bei guter Internetverbindung sind ganz oft Ladescreens.
/// Wenn man auf etwas tippt, soll gleich alles da sein."*
///
/// Der Grund war nicht die Leitung, sondern der **Zeitpunkt**: Jeder Schirm
/// fing erst mit dem Laden an, als er schon zu sehen war. Ein `TabBarView`
/// baut zudem nur den sichtbaren Reiter — die Torjägerliste wurde also in dem
/// Moment angefragt, in dem jemand sie sehen wollte, und der sah zuerst einen
/// Kreis.
///
/// Ein Vorwärmer stellt die Fragen **eine Bewegung früher**: beim Aufbau des
/// Schirms für alle seine Reiter, und beim Start der App für den Unterbau, an
/// dem fast jeder Fantasy-Schirm hängt. Es kostet nichts Zusätzliches — es
/// sind dieselben Abrufe, nur nicht mehr im Weg.
///
/// Drei Eigenschaften, die das tragen und ohne die es Unsinn wäre:
///
/// * **Kein `autoDispose` in dieser App.** Ein einmal geholtes Ergebnis bleibt
///   für die Laufzeit stehen; Vorwärmen ist deshalb kein Vorrat, der wieder
///   verfällt.
/// * **`ref.read`, nicht `ref.watch`.** Der Vorwärmer will die Abfrage
///   anstoßen, nicht auf ihr Ergebnis reagieren — mit `watch` baute sich der
///   ganze Schirm bei jeder Live-Aktualisierung neu auf.
/// * **Gebündelt** ([AbfrageBuendel]): Fragt der sichtbare Reiter dasselbe wie
///   der Vorwärmer, teilen sich beide eine Verbindung statt zwei zu öffnen.
class Vorwaermer extends ConsumerStatefulWidget {
  const Vorwaermer({super.key, required this.holt, required this.child});

  /// Was im Hintergrund angestoßen wird. Läuft genau einmal je Schirm.
  final void Function(WidgetRef ref) holt;
  final Widget child;

  @override
  ConsumerState<Vorwaermer> createState() => _VorwaermerState();
}

class _VorwaermerState extends ConsumerState<Vorwaermer> {
  @override
  void initState() {
    super.initState();
    // Nach dem ersten Frame: Der Schirm soll zuerst erscheinen. Ein Dutzend
    // Abfragen im selben Frame anzustoßen verzögert den Aufbau, und gerade
    // darum geht es hier.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.holt(ref);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Der gemeinsame Unterbau der Fantasy-Welt.
///
/// Diese vier hängen an **fast jedem** Fantasy-Schirm — Kader, Aufstellung,
/// MatchUp, Tabelle, Free Agency, Spielerprofil. Sie einmal beim Start zu
/// holen macht jeden davon zum sofortigen Aufbau.
///
/// `seasonStatsProvider` ist bewusst dabei, obwohl es die größte Antwort ist
/// (gemessen 357 KB nach zwei Spieltagen): Ohne sie steht in der Tabelle und
/// in jeder Bilanz eine Null, und sie wächst mit der Saison — je später im
/// Jahr, desto mehr lohnt es, sie nicht im Weg zu haben.
void warmeFantasyUnterbau(WidgetRef ref) {
  ref.read(playerPoolProvider);
  ref.read(fantasySeasonFixturesProvider);
  ref.read(fantasyCurrentRoundProvider);
  ref.read(seasonStatsProvider);
}

/// Was hinter einer Fantasy-Liga steckt, für alle vier Reiter zugleich.
void warmeFantasyLiga(WidgetRef ref, String leagueId) {
  ref.read(fantasyManagersProvider(leagueId));
  ref.read(leagueRosterProvider(leagueId));
  ref.read(leagueLineupsProvider(leagueId));
  ref.read(incomingTradeOffersProvider(leagueId));
  ref.read(rosterMovesProvider(leagueId));
  ref.read(fantasyTipRoundProvider(leagueId));
}

/// Alle Reiter der Wettbewerbs-Übersicht: Spieltage, Tabelle, Torjäger, News.
///
/// Die Torjägerliste ist hier der eigentliche Gewinn — sie hängt an keinem
/// anderen Schirm, wird also garantiert erst beim Antippen geholt.
void warmeWettbewerb(WidgetRef ref, String leagueId) {
  ref.read(leagueSeasonFixturesProvider(leagueId));
  ref.read(leagueTableProvider(leagueId));
  ref.read(leagueTopScorersProvider(leagueId));
  ref.read(leagueNewsProvider(leagueId));
}
