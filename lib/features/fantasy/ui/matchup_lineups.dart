import 'package:flutter/material.dart';
import '../../../app/widgets/punktzahl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers.dart';
import '../logic/fantasy_scoring_engine.dart';
import '../models/fantasy_models.dart';
import '../models/player_absence.dart';
import '../providers.dart';
import 'ausfall_zeichen.dart';
import 'club_badge.dart';
import 'manager_profile_screen.dart';
import 'player_profile_sheet.dart';
import 'punkte_aufschluesselung.dart';
import '../../../core/logic/vereins_kuerzel.dart';
import '../logic/naechstes_spiel.dart';
import '../../../core/models/models.dart';
import '../../../app/typografie.dart';

// Reihenfolge der Positionsblöcke (TW zuerst).
const _order = [
  PlayerPosition.gk,
  PlayerPosition.def,
  PlayerPosition.mid,
  PlayerPosition.fwd,
];

/// Aufbereitete Startelf/Bank einer Seite für einen Spieltag.
class MatchupSideData {
  MatchupSideData(
    this.starters,
    this.bench,
    this.points,
    this.total,
    this.gespielt,
  );

  final List<FantasyPlayer> starters;
  final List<FantasyPlayer> bench;
  final Map<String, double> points;
  final double total;

  /// Wer an diesem Spieltag **schon gespielt hat**.
  ///
  /// Ohne diese Auskunft ist eine 0 doppeldeutig: „hat gespielt und nichts
  /// geholt" sieht aus wie „ist noch gar nicht dran gewesen". Genau daran
  /// hing die Hervorhebung — ein Spieler ohne Anpfiff „führte" gegen einen mit
  /// drei Gegentoren und Gelb, weil 0 größer ist als −10.
  final Set<String> gespielt;

  List<FantasyPlayer> startersAt(PlayerPosition pos) => [
    for (final p in starters)
      if (p.position == pos) p,
  ]..sort((a, b) => (points[b.id] ?? 0).compareTo(points[a.id] ?? 0));
}

/// Startelf + Bank + Punkte einer Seite (gespeicherte Aufstellung, sonst
/// automatische beste Elf) — identisch zur Wertung im MatchUp-Tab.
MatchupSideData computeSideData({
  required FantasyLeague league,
  required int round,
  required String managerId,
  required Map<String, FantasyPlayer> byId,
  required List<RosterEntry> roster,
  required List<FantasyLineup> lineups,
  required Map<String, PlayerMatchStats> stats,
}) {
  final rosterPlayers = [
    for (final r in roster)
      if (r.managerId == managerId && byId[r.playerId] != null)
        byId[r.playerId]!,
  ];
  final saved = lineups
      .where((l) => l.managerId == managerId && l.round == round)
      .map((l) => l.playerIds)
      .firstOrNull;
  final kaderPunkte = {
    for (final p in rosterPlayers)
      p: scorePlayer(
        stats[p.id] ?? const PlayerMatchStats(),
        p.position,
        league.scoring,
      ),
  };
  final starterIds = (saved != null && saved.isNotEmpty)
      ? {
          for (final id in saved)
            if (byId.containsKey(id)) id,
        }
      : bestEleven(kaderPunkte, league.roster).starterIds;

  // **Die gespeicherte Elf ist die Auskunft, nicht der heutige Kader.**
  //
  // Vorher wurden die Startelf-Spieler aus `rosterPlayers` gefiltert — also
  // aus dem Bestand von *jetzt*. Wer nach dem Anpfiff abgegeben oder getradet
  // wurde, fiel damit rückwirkend aus der Elf und nahm seine Punkte mit.
  // Gemeldet als „einen Spieler droppen beeinflusst im Nachhinein die Punkte".
  //
  // Wer zum Anpfiff in der Elf stand, punktet für diesen Spieltag — auch wenn
  // er inzwischen woanders spielt. Der Server schreibt in `fantasy_lineups`
  // ohnehin nur Spieler, die dem Manager zum Zeitpunkt des Speicherns
  // gehörten (`fantasy_set_lineup`); geprüft wird beim **Schreiben**, nicht
  // beim Lesen.
  final starters = [
    for (final id in starterIds)
      if (byId[id] != null) byId[id]!,
  ]..sort((a, b) => a.position.index.compareTo(b.position.index));
  // Gewertet wird **Kader plus Startelf** — ein Spieler, der die Elf nach dem
  // Anpfiff verlassen hat, steht in keinem Kader mehr und hätte sonst keine
  // Punkte.
  final pointsByPlayer = {
    ...kaderPunkte,
    for (final p in starters)
      p: scorePlayer(
        stats[p.id] ?? const PlayerMatchStats(),
        p.position,
        league.scoring,
      ),
  };
  final bench =
      [
        for (final p in rosterPlayers)
          if (!starterIds.contains(p.id)) p,
      ]..sort(
        (a, b) => a.position.index != b.position.index
            ? a.position.index.compareTo(b.position.index)
            : (pointsByPlayer[b] ?? 0).compareTo(pointsByPlayer[a] ?? 0),
      );

  final points = {for (final e in pointsByPlayer.entries) e.key.id: e.value};
  final total = [
    for (final p in starters) points[p.id] ?? 0.0,
  ].fold<double>(0, (a, b) => a + b);
  final gespielt = {
    for (final p in pointsByPlayer.keys)
      if (stats[p.id]?.hasContribution ?? false) p.id,
  };
  return MatchupSideData(starters, bench, points, total, gespielt);
}

/// Spieler-Gegenüberstellung einer Head-to-Head-Paarung: beide Aufstellungen
/// positionsweise nebeneinander mit den (Live-)Punkten je Spieler, darunter
/// die ausklappbare Bank. Bei einem Bye (`away == null`) nur die eigene Seite.
/// Rendert als [Column] — passt in eine umgebende [ListView].
class MatchupLineups extends ConsumerWidget {
  const MatchupLineups({
    super.key,
    required this.league,
    required this.runde,
    required this.home,
    required this.away,
    required this.homeId,
    required this.awayId,
    required this.homeName,
    this.awayName,
    this.stats = const {},
  });

  final FantasyLeague league;

  /// Spieltag, um den es geht — für „wann spielt er als Nächstes?".
  final int runde;
  final MatchupSideData home;
  final MatchupSideData? away;
  final String homeId;
  final String? awayId;
  final String homeName;
  final String? awayName;

  /// **Die Roh-Statistik dieses Spieltags** — je Spieler-ID.
  ///
  /// Sie kommt vom Aufrufer und nicht aus einem eigenen Provider, und zwar
  /// aus demselben Grund, aus dem [computeSideData] sie bekommt: Die Zahl in
  /// der Punktebox und die Aufschlüsselung dahinter müssen **dieselbe**
  /// Rechnung zeigen. Zwei Quellen dafür wären zwei Wahrheiten.
  ///
  /// Leer heißt: keine Aufschlüsselung, die Box bleibt eine Anzeige.
  final Map<String, PlayerMatchStats> stats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clubIcons =
        ref.watch(clubIconsProvider).valueOrNull ?? const <String, String?>{};
    final myId = ref.watch(currentUserProvider)?.id;
    // Der Spielplan sagt, wer wann anpfeift — nicht der Statistik-Datensatz.
    final spiele =
        ref.watch(fantasySeasonFixturesProvider).valueOrNull ??
        const <Fixture>[];
    final jetzt = DateTime.now();
    // **Auch hier, nicht nur auf dem Feld.** Das MatchUp ist der Schirm, den
    // man am Spieltag offen hat; wer dort sieht, dass sein Stürmer gesperrt
    // ist, kann noch tauschen.
    final ausfaelle = ref.watch(absencesProvider).valueOrNull ??
        const <String, PlayerAbsence>{};
    bool angepfiffen(String verein) {
      final s = naechstesSpiel(spiele, runde, verein);
      return s != null && !s.anpfiff.isAfter(jetzt);
    }

    final homeMine = homeId == myId;
    final awayMine = awayId != null && awayId == myId;

    void openPlayer(FantasyPlayer p, bool mine) => showPlayerProfile(
      context,
      league: league,
      player: p,
      clubIcon: clubIcons[p.club],
      isMine: mine,
    );

    // **Die Punktebox öffnet die Aufschlüsselung, die Karte das Profil.**
    // Zwei Ziele in einer Zeile, aber mit sichtbarer Grenze: Die Box ist ein
    // eigener Kasten, und die Frage „woher kommen die Punkte?" stellt sich
    // beim Vergleich zweier Aufstellungen eher als im Profil.
    //
    // `null` heißt: kein Ziel. Ohne Statistikzeile gibt es nichts
    // aufzuschlüsseln, und dann soll die Box den Tipp an die Karte
    // durchreichen, statt ein leeres Blatt zu öffnen.
    void Function()? openBreakdown(FantasyPlayer p) {
      final st = stats[p.id];
      if (st == null || !st.hasContribution) return null;
      return () => zeigePunkteAufschluesselung(
            context,
            titel: '${p.name} · $runde. Spieltag',
            score: scorePlayerDetailed(st, p.position, league.scoring),
            gespielt: true,
          );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final pos in _order)
          ..._positionBlock(
            context,
            pos: pos,
            // **Nur der Torwart hat eine feste Zahl.** Abwehr, Mittelfeld und
            // Sturm stehen in Spannen — dort heißt eine leere Zelle bloß, dass
            // die andere Seite eine andere Formation spielt, und das ist kein
            // Mangel. Beim Torwart heißt sie: Es ist keiner da.
            pflicht: pos == PlayerPosition.gk ? league.roster.gk : null,
            home: home,
            away: away,
            homeMine: homeMine,
            awayMine: awayMine,
            clubIcons: clubIcons,
            ausfaelle: ausfaelle,
            spiele: spiele,
            angepfiffen: angepfiffen,
            onTap: openPlayer,
            onPunkte: openBreakdown,
          ),
        const SizedBox(height: 12),
        // **Keine Bank über nichts.** Steht auf keiner Seite jemand auf der
        // Bank, gibt es auch nichts aufzuklappen — die Zeile hätte nur
        // gesagt, dass sie leer ist.
        if (home.bench.isNotEmpty || (away?.bench.isNotEmpty ?? false))
          _BenchSection(
            home: home,
            away: away,
            league: league,
            homeId: homeId,
            awayId: awayId,
            homeName: homeName,
            awayName: awayName,
            clubIcons: clubIcons,
            ausfaelle: ausfaelle,
            homeMine: homeMine,
            awayMine: awayMine,
            onTap: openPlayer,
          ),
      ],
    );
  }

  /// Ein Positionsblock: Überschrift + zeilenweise Gegenüberstellung der
  /// Starter beider Seiten (nach Index innerhalb der Position gepaart).
  List<Widget> _positionBlock(
    BuildContext context, {
    required PlayerPosition pos,
    required int? pflicht,
    required MatchupSideData home,
    required MatchupSideData? away,
    required bool homeMine,
    required bool awayMine,
    required Map<String, String?> clubIcons,
    required Map<String, PlayerAbsence> ausfaelle,
    required List<Fixture> spiele,
    required bool Function(String verein) angepfiffen,
    required void Function(FantasyPlayer, bool) onTap,
    required void Function()? Function(FantasyPlayer) onPunkte,
  }) {
    final hs = home.startersAt(pos);
    final as = away?.startersAt(pos) ?? const <FantasyPlayer>[];

    // **Fehlt eine Pflichtposition, ist das der Inhalt der Zeile.** Verlässt
    // der einzige Torwart die Bundesliga, nimmt ihn der Abgangs-Lauf aus dem
    // Kader (0117) und die Elf hat nur zehn Mann (0120). Vorher blieb davon
    // nichts übrig: Die leere Zelle war ein `SizedBox` und der ganze Block
    // verschwand, wenn auf beiden Seiten keiner stand. **Ein Zustand „hier
    // fehlt jemand" sah aus wie „alles in Ordnung"** — derselbe Fehler wie
    // beim leeren Feld im Draft-Brett und beim Phantom in der Elf.
    final fehltHeim = pflicht != null && hs.length < pflicht;
    final fehltGast = pflicht != null && away != null && as.length < pflicht;

    if (hs.isEmpty && as.isEmpty && !fehltHeim && !fehltGast) return const [];
    final rows = <Widget>[];
    var n = hs.length > as.length ? hs.length : as.length;
    if (pflicht != null && n < pflicht) n = pflicht;
    for (var i = 0; i < n; i++) {
      final h = i < hs.length ? hs[i] : null;
      final a = i < as.length ? as[i] : null;
      final hp = h == null ? null : (home.points[h.id] ?? 0.0);
      final ap = a == null ? null : (away?.points[a.id] ?? 0.0);
      rows.add(
        _PlayerRow(
          home: h,
          away: a,
          homeFehlt: h == null && fehltHeim ? pos : null,
          awayFehlt: a == null && fehltGast ? pos : null,
          homePts: hp,
          awayPts: ap,
          // **Angepfiffen, nicht „hat Statistiken".** Vorher entschied das
          // Vorhandensein einer Statistikzeile darüber, ob Punkte statt eines
          // Strichs erscheinen — und die war schon vor dem Anstoß da. Genau
          // deshalb standen zum Start des Spieltags überall 0,0 Punkte.
          homeGespielt: h != null && angepfiffen(h.club),
          awayGespielt: a != null && angepfiffen(a.club),
          homeSpiel: h == null ? null : naechstesSpiel(spiele, runde, h.club),
          awaySpiel: a == null ? null : naechstesSpiel(spiele, runde, a.club),
          homeMine: homeMine,
          awayMine: awayMine,
          clubIcons: clubIcons,
          ausfaelle: ausfaelle,
          onTap: onTap,
          onPunkte: onPunkte,
        ),
      );
    }
    // **Der Vergleich steht im Kopf, nicht in der Zeile.**
    //
    // Vorher trug die punktbessere der beiden gegenübergestellten Zellen einen
    // grünen Rahmen — „führt dieses Duell". Gemeldet, und zu Recht: *„Das
    // macht wenig Sinn, wenn verschiedene Anzahl an jeweiligen Positionen
    // existieren."* Die Paarung entsteht über den **Index innerhalb der
    // Position**, und der ist keine Rangfolge: Er kommt aus der Reihenfolge,
    // in der die Elf gespeichert wurde. Spielt die eine Seite mit vier
    // Verteidigern und die andere mit dreien, wird zusätzlich willkürlich
    // gepaart, und der vierte hat gar kein Gegenüber.
    //
    // Die **Summe je Positionsblock** ist dagegen unabhängig von der Anzahl
    // definiert und beantwortet dieselbe Frage besser: Wer gewinnt die
    // Abwehr? Grün trägt sie, weil „ein führendes Team" in dieser App eine
    // erlaubte Verwendung des Signals ist — hier führt wirklich jemand.
    final hSum = _summe(hs, home.points, angepfiffen);
    final aSum = away == null ? null : _summe(as, away.points, angepfiffen);

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: positionColor(pos),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                pos.label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: positionColor(pos),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (hSum != null || aSum != null)
              _BlockStand(heim: hSum, gast: aSum),
          ],
        ),
      ),
      ...rows,
    ];
  }
}

/// Die Punktesumme eines Positionsblocks — `null`, wenn dort noch niemand
/// angepfiffen hat.
///
/// **`null` statt 0**, denn beides sähe sonst gleich aus: „hat gespielt und
/// nichts geholt" ist etwas anderes als „spielt erst noch". Dieselbe
/// Unterscheidung wie in der Punktebox der Zeile.
double? _summe(
  List<FantasyPlayer> spieler,
  Map<String, double> punkte,
  bool Function(String verein) angepfiffen,
) {
  var gab = false;
  var summe = 0.0;
  for (final p in spieler) {
    if (!angepfiffen(p.club)) continue;
    gab = true;
    summe += punkte[p.id] ?? 0;
  }
  return gab ? summe : null;
}

/// „34 : 21" im Kopf eines Positionsblocks, die führende Seite in Grün.
///
/// Steht rechts neben dem Positionsnamen und ersetzt die frühere
/// Hervorhebung je Zeile. Ein Strich heißt „hier hat noch niemand gespielt" —
/// eine 0 wäre an der Stelle eine Behauptung.
class _BlockStand extends StatelessWidget {
  const _BlockStand({required this.heim, required this.gast});

  final double? heim;
  final double? gast;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Verglichen wird nur, wo auf **beiden** Seiten gespielt wurde. Sonst
    // führte die Seite, die zufällig früher angepfiffen hat.
    final vergleichbar = heim != null && gast != null;
    final heimFuehrt = vergleichbar && heim! > gast!;
    final gastFuehrt = vergleichbar && gast! > heim!;

    TextStyle stil(bool fuehrt) => TextStyle(
          fontSize: 13,
          fontWeight: fuehrt ? FontWeight.w800 : FontWeight.w600,
          color: fuehrt ? scheme.primary : scheme.onSurfaceVariant,
          fontFeatures: const [FontFeature.tabularFigures()],
        );

    Widget zahl(double? wert, bool fuehrt) => Text(
          wert == null ? '–' : formatPoints(wert),
          style: stil(fuehrt),
        );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        zahl(heim, heimFuehrt),
        if (gast != null || heim != null) ...[
          Text(' : ',
              style: TextStyle(
                  fontSize: 13, color: scheme.onSurfaceVariant)),
          zahl(gast, gastFuehrt),
        ],
      ],
    );
  }
}

/// Eine Vergleichszeile: links Heim-Spieler, rechts Gast-Spieler, die Punkte
/// jeweils zur Mitte hin.
///
/// **Kein Sieger je Zeile.** Die Paarung entsteht über den Index innerhalb
/// der Position und ist keine Rangfolge; bei verschiedenen Formationen wird
/// zusätzlich willkürlich gepaart. Verglichen wird deshalb im Kopf des
/// Positionsblocks, wo die Summe unabhängig von der Anzahl gilt.
class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.home,
    required this.away,
    required this.homePts,
    required this.awayPts,
    required this.homeGespielt,
    required this.awayGespielt,
    required this.homeSpiel,
    required this.awaySpiel,
    required this.homeMine,
    required this.awayMine,
    required this.clubIcons,
    required this.ausfaelle,
    required this.onTap,
    required this.onPunkte,
    this.homeFehlt,
    this.awayFehlt,
  });

  /// Ausfälle je Spieler-ID — verletzt oder gesperrt.
  final Map<String, PlayerAbsence> ausfaelle;

  final FantasyPlayer? home;
  final FantasyPlayer? away;

  /// Gesetzt, wenn an dieser Stelle eine **Pflichtposition** unbesetzt ist —
  /// heute nur der Torwart. Ohne die Angabe bleibt eine leere Zelle leer:
  /// Dort spielt die andere Seite bloß eine andere Formation.
  final PlayerPosition? homeFehlt;
  final PlayerPosition? awayFehlt;
  final double? homePts;
  final double? awayPts;

  /// **Hat sein Verein schon angepfiffen?** Erst dann sind Punkte eine
  /// Auskunft; vorher steht in der Box, gegen wen und wann er spielt.
  final bool homeGespielt;
  final bool awayGespielt;

  /// Sein Spiel an diesem Spieltag — `null`, wenn sein Verein frei hat.
  final NaechstesSpiel? homeSpiel;
  final NaechstesSpiel? awaySpiel;

  final bool homeMine;
  final bool awayMine;
  final Map<String, String?> clubIcons;
  final void Function(FantasyPlayer, bool) onTap;

  /// Liefert das Ziel für einen Tipp auf die Punktebox — oder `null`, wenn es
  /// nichts aufzuschlüsseln gibt.
  final void Function()? Function(FantasyPlayer) onPunkte;

  @override
  Widget build(BuildContext context) {
    // **Die Hervorhebung heißt „führt in dieser Paarung" — und das darf nur
    // sagen, wer auch gespielt hat.** Vorher zählte allein die Punktzahl:
    // Ein Spieler ohne Anpfiff steht bei 0, und 0 ist mehr als die −10 eines
    // Verteidigers mit drei Gegentoren und Gelb. Also bekam der Umrahmung, der
    // noch gar nicht dran war, und der, der gespielt hatte, keine. Wer noch
    // nicht gespielt hat, führt nicht — er hat noch nicht angefangen.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: _cell(
              context,
              player: home,
              pts: homePts,
              mine: homeMine,
              gespielt: homeGespielt,
              spiel: homeSpiel,
              start: true,
              fehltPos: homeFehlt,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _cell(
              context,
              player: away,
              pts: awayPts,
              mine: awayMine,
              gespielt: awayGespielt,
              spiel: awaySpiel,
              start: false,
              fehltPos: awayFehlt,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(
    BuildContext context, {
    required FantasyPlayer? player,
    required double? pts,
    required bool mine,
    required bool gespielt,
    required NaechstesSpiel? spiel,
    required bool start,
    PlayerPosition? fehltPos,
  }) {
    final scheme = Theme.of(context).colorScheme;
    if (player == null) {
      // Ohne [fehltPos] ist die Zelle nur die Gegenseite einer anderen
      // Formation — dort fehlt nichts, dort steht bloß niemand.
      if (fehltPos == null) return const SizedBox(height: 60);
      return _FehlendePosition(pos: fehltPos);
    }
    final pos = positionColor(player.position);
    final ausfall = ausfaelle[player.id];
    // **Die Box nimmt den Tipp selbst an**, wenn es etwas aufzuschlüsseln
    // gibt. Ein inneres `GestureDetector` gewinnt gegen das umgebende
    // `InkWell`, die Karte behält also ihren Weg ins Profil — zwei Ziele in
    // einer Zeile, getrennt durch den sichtbaren Kasten.
    final aufPunkte = onPunkte(player);
    // **Die Zahl steht frei in der Karte, ohne Kasten darunter.** Auf Ansage:
    // „Glaube die Zahlen brauchen da keinen Hintergrund, sondern können
    // einfach so in der Karte stehen." Und das stimmt: Die Zeile ist schon
    // eine Karte — Verlauf, Haarlinie, Radius 14. Ein zweiter Kasten darin
    // umrandet etwas, das ohnehin abgegrenzt ist; auf dem Rasen (Feld im
    // Kader-Tab) bleibt die Pille dagegen, dort liegt die Zahl auf Wappen und
    // Gras und wäre ohne Grund stellenweise unlesbar.
    //
    // **Die Mindestbreite bleibt.** Ohne sie rutschte der Name bei jeder
    // Aktualisierung hin und her, sobald aus „7" eine „12,5" wird — dieselbe
    // Unruhe, gegen die die gleichbreiten Ziffern in [Punktzahl] gebaut sind.
    final ptsBox = Container(
      // **Feste Breite, nicht bloß eine Mindestbreite — und nur für die
      // Zahl.** Gemeldet: „Die Punkte im MatchUp-Tab sind immer noch krumm
      // und schief."
      //
      // Drei Dinge wirkten zusammen: Die Box wuchs mit ihrem Inhalt („12" ist
      // breiter als „5"), sie trug beidseitig Polster, und die Zahl stand
      // darin **zentriert**. Dadurch verschob sich jede Zahl je nach
      // Stellenzahl — auf der Heimseite nach links, auf der Gastseite nach
      // rechts. Rechtsbündig war nur die Box, nicht die Ziffer darin.
      //
      // Der Anstoß-Hinweis behält seine freie Breite: Er ist zweizeilig
      // (Kürzel über Uhrzeit) und würde in 36 Punkten gequetscht.
      constraints: gespielt
          ? const BoxConstraints(minWidth: 40, maxWidth: 40)
          : const BoxConstraints(minWidth: 36),
      padding: gespielt
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      // **Vor dem Anpfiff steht hier das Spiel, nicht ein Strich.** „Noch
      // nicht gespielt" ist kein Nullpunktespiel — vorher stand in beiden
      // Fällen „0", dann ein Strich. Ein Strich sagt nichts Falsches, aber
      // auch nichts; die Frage vor einem Spieltag ist „gegen wen und wann?".
      //
      // `formatPoints` statt roher Interpolation: Die Wertung kennt −0,4 je
      // Foul, und `0.4`-Summen tragen sonst einen Fließkomma-Rattenschwanz
      // hinter sich her.
      child: gespielt
          ? _punkte(
              gespielt,
              pts,
              // **Zur Außenkante hin, nicht mittig.** Heimseite rechts,
              // Gastseite links — dann steht jede Zahl einer Spalte an
              // derselben Stelle, unabhängig von ihrer Stellenzahl.
              textAlign: start ? TextAlign.end : TextAlign.start,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
            )
          : _AnstossHinweis(spiel: spiel),
    );
    // Ohne Ziel bleibt die Box eine Anzeige und reicht den Tipp durch — vor
    // dem Anpfiff steht dort ohnehin die Partie und keine Punktzahl.
    final ptsFeld = aufPunkte == null
        ? ptsBox
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: aufPunkte,
            child: Semantics(
              button: true,
              label: '${player.name}: Punkte aufschlüsseln',
              child: ptsBox,
            ),
          );
    final badge = ClubBadge(
      club: player.club,
      iconUrl: clubIcons[player.club],
      size: 34,
    );
    final info = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: start
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          // Die Gastseite liest sich von rechts nach links — dort steht das
          // Zeichen hinter dem Namen, sonst davor.
          children: [
            if (ausfall != null && !start) ...[
              AusfallZeichen(ausfall: ausfall, size: 13),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                shortPlayerName(player.name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: start ? TextAlign.start : TextAlign.end,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: mine ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
            if (ausfall != null && start) ...[
              const SizedBox(width: 4),
              AusfallZeichen(ausfall: ausfall, size: 13),
            ],
          ],
        ),
        // **Kein Positionskürzel je Zeile.** Über jedem Block steht die
        // Position schon als Überschrift (Punkt und Wort), und die Zeilen
        // darunter tragen ihre Farbe ohnehin im Verlauf. Dieselbe Regel wie
        // beim „LIVE" in der Tipp-Tabelle und der Uhrzeit im Live-Tab: Eine
        // Auskunft, die sich je Zeile nicht unterscheidet, gehört nicht in
        // die Zeile — sie kostet nur Höhe.
      ],
    );

    final children = start
        ? [
            badge,
            const SizedBox(width: 9),
            Expanded(child: info),
            const SizedBox(width: 8),
            ptsFeld,
          ]
        : [
            ptsFeld,
            const SizedBox(width: 8),
            Expanded(child: info),
            const SizedBox(width: 9),
            badge,
          ];

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onTap(player, mine),
        child: Container(
          // Einzeilig statt zweizeilig: 60 auf 48. Bei elf Startern plus Bank
          // sind das über zweihundert Punkte, die der Spieltag kürzer wird.
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            // Karten-Look: dezenter Verlauf mit Positions-Ton.
            gradient: LinearGradient(
              begin: start ? Alignment.centerLeft : Alignment.centerRight,
              end: start ? Alignment.centerRight : Alignment.centerLeft,
              colors: [
                pos.withValues(alpha: 0.13),
                scheme.surfaceContainerHighest.withValues(alpha: 0.35),
              ],
            ),
            // **Eine Kante für alle.** Der grüne Rahmen markierte hier den
            // Sieger des Zeilenduells — eine Paarung, die es so nicht gibt
            // (siehe Kopf des Positionsblocks). Und selbst als Signal gehörte
            // die Farbe in die Fläche, nicht an den Rand.
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Row(children: children),
        ),
      ),
    );
  }
}

/// Kürzt einen Spielernamen auf den Nachnamen (falls mehrteilig).
String shortPlayerName(String name) {
  final parts = name.trim().split(' ');
  return parts.length > 1 ? parts.last : name;
}

/// Die Bank beider Seiten, die nicht für die Wertung zählt —
/// **immer sichtbar, nicht hinter einem Ausklapper**.
///
/// Sie steckte in einer `ExpansionTile`, war also zugeklappt, bis jemand darauf
/// tippte. Wer wissen wollte, wen der Gegner noch draußen hat, musste das erst
/// aufmachen — und beim nächsten Öffnen des MatchUps wieder. Gemeldet als „die
/// Bank soll nicht durch so einen Dropdown angezeigt werden, sondern immer".
///
/// **Die Zeilen bleiben klein** (ausdrücklich so gewünscht: „keine vollen
/// Boxen"): Positionspunkt, 20er-Wappen, gekürzter Name, Punktzahl — zwei
/// Spalten nebeneinander. Die große Gegenüberstellung mit Wappen an den
/// Außenkanten gehört der Startelf; die Bank ist die Auskunft daneben und darf
/// nicht so laut sein wie sie.
class _BenchSection extends StatelessWidget {
  const _BenchSection({
    required this.home,
    required this.away,
    required this.league,
    required this.homeId,
    required this.awayId,
    required this.homeName,
    required this.awayName,
    required this.clubIcons,
    required this.ausfaelle,
    required this.homeMine,
    required this.awayMine,
    required this.onTap,
  });

  /// Liga und Manager-IDs — dafür, dass der Name über der Spalte ins
  /// Ligaprofil führt, genau wie im Duell-Kopf.
  final FantasyLeague league;
  final String homeId;
  final String? awayId;

  /// Ausfälle je Spieler-ID — verletzt oder gesperrt.
  final Map<String, PlayerAbsence> ausfaelle;

  final MatchupSideData home;
  final MatchupSideData? away;
  final String homeName;
  final String? awayName;
  final Map<String, String?> clubIcons;
  final bool homeMine;
  final bool awayMine;
  final void Function(FantasyPlayer, bool) onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Kopf wie bei den Positionsblöcken darüber — grauer Punkt, weil die
        // Bank keine Position ist, sondern deren Rest.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Bank',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _column(
                context,
                homeName,
                homeId,
                home.bench,
                home.points,
                homeMine,
              ),
            ),
            if (awayName != null && away != null)
              Expanded(
                child: _column(
                  context,
                  awayName!,
                  awayId,
                  away!.bench,
                  away!.points,
                  awayMine,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _column(
    BuildContext context,
    String title,
    String? managerId,
    List<FantasyPlayer> bench,
    Map<String, double> points,
    bool mine,
  ) {
    final scheme = Theme.of(context).colorScheme;
    // **Auch hier führt der Name ins Ligaprofil** — dieselbe Regel wie im
    // Duell-Kopf darüber (Ansage vom 19.09.2026). Über der Bank steht der
    // Name des Managers; wer wissen will, wer das ist und was er sonst
    // aufgestellt hat, tippt genau dort hin.
    final kopf = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(
        context,
      ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (managerId == null)
            kopf
          else
            Semantics(
              button: true,
              label: 'Profil von $title',
              child: InkWell(
                onTap: () => showManagerProfile(
                  context,
                  league: league,
                  managerId: managerId,
                  managerName: title,
                ),
                borderRadius: BorderRadius.circular(6),
                child: kopf,
              ),
            ),
          const SizedBox(height: 6),
          if (bench.isEmpty)
            Text(
              '—',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            )
          else
            for (final p in bench)
              InkWell(
                onTap: () => onTap(p, mine),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: positionColor(p.position),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      ClubBadge(
                        club: p.club,
                        iconUrl: clubIcons[p.club],
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      // **Ein `Expanded`, kein `Flexible` neben einem
                      // `Spacer`.**
                      //
                      // Genau daran lag die schiefe Spalte — nachgemessen,
                      // nicht geraten: Die Punktespalte war überall exakt 44
                      // Punkte breit, saß aber an fünf verschiedenen Stellen
                      // (rechte Kante 172,2 / 173,4 / 179,6 / 189,0). Ursache:
                      // `Flexible` und `Spacer` teilen sich den freien Platz
                      // je zur Hälfte. Was ein kurzer Name von seiner Hälfte
                      // nicht braucht, **verfällt** — es geht nicht an den
                      // `Spacer`. Die Zeile endete deshalb je nach
                      // Namenslänge früher, und die Zahl wanderte mit.
                      //
                      // Mit einem `Expanded` nimmt der Namensblock den ganzen
                      // Rest, und die Punktespalte steht am echten rechten
                      // Rand — in jeder Zeile an derselben Stelle. Das
                      // Zeichen bleibt darin direkt am Namen.
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                shortPlayerName(p.name),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (ausfaelle[p.id] != null) ...[
                              const SizedBox(width: 4),
                              AusfallZeichen(
                                ausfall: ausfaelle[p.id]!,
                                size: 12,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      // **Die Spalte muss die breiteste Zahl tragen, sonst
                      // fluchtet nur, was zufällig schmal genug ist.**
                      //
                      // Erst standen die Zahlen rechtsbündig ohne feste
                      // Breite, dann in 36 Punkten — beides half nicht: Ein
                      // `SizedBox` schneidet zu breiten Inhalt nicht ab, er
                      // steht über. „6" und „12" saßen damit an der Kante,
                      // „8,8" und „−2" ragten nach rechts heraus. Im
                      // Vergleichsbild war das nicht zu sehen, weil dort
                      // **jeder** Spieler 6,0 Punkte hatte; bei lauter
                      // gleichen Zahlen ist eine schiefe Spalte unsichtbar.
                      // Die Vorschau trägt deshalb jetzt 0, 12, 8,8, −2 und
                      // 12,5.
                      //
                      // 44 Punkte fassen die breiteste vorkommende Zahl
                      // („−12,5") bei fetter 14-Punkt-Schrift; `FittedBox`
                      // fängt alles darüber ab, statt es überstehen zu
                      // lassen. Die gleichbreiten Ziffern aus [Punktzahl]
                      // halten die Spalte auch bei laufender Wertung ruhig.
                      SizedBox(
                        width: 44,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Punktzahl(
                              points[p.id] ?? 0,
                              stil:
                                  const TextStyle(fontWeight: FontWeight.bold),
                              negativRot: true,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

/// Punkte einer Zeile — oder ein Strich, wenn noch nicht gespielt wurde.
///
/// **Noch nicht gespielt ist kein Nullpunktespiel.** Vorher stand in beiden
/// Fällen „0"; man konnte nicht unterscheiden, ob jemand gespielt und nichts
/// geholt hat oder noch gar nicht dran war.
Widget _punkte(
  bool gespielt,
  double? pts, {
  required TextStyle style,
  TextAlign? textAlign,
}) {
  if (!gespielt) {
    return Text('–', textAlign: textAlign, style: style);
  }
  // **Die Ausrichtung folgt dem übergebenen `textAlign`.** Vorher kannte der
  // Helfer nur „mittig oder links": Jedes `textAlign`, das nicht `center`
  // war, landete links — auch `TextAlign.end`. Damit ließ sich eine Zahl gar
  // nicht an die rechte Kante setzen, und die Spalte blieb schief.
  return Align(
    alignment: switch (textAlign) {
      TextAlign.end || TextAlign.right => Alignment.centerRight,
      TextAlign.start || TextAlign.left => Alignment.centerLeft,
      _ => Alignment.center,
    },
    child: Punktzahl(pts ?? 0, stil: style, negativRot: true),
  );
}

/// Was in der Punktebox steht, solange sein Verein nicht angepfiffen hat:
/// **Gegner und Anstoß**, zweizeilig.
///
/// Zwei Zeilen und keine, weil „SVE Sa 15:30" in einer Zeile die Box auf die
/// doppelte Breite zöge — und die Box steht in einer Reihe mit Wappen und
/// Namen, die ihren Platz brauchen. Übereinander bleibt sie so breit wie eine
/// Punktzahl und wächst nur um wenige Punkte in der Höhe, die die Zeile
/// ohnehin hat.
class _AnstossHinweis extends StatelessWidget {
  const _AnstossHinweis({required this.spiel});

  final NaechstesSpiel? spiel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = spiel;
    // **Kein Spiel ist etwas anderes als „noch nicht angepfiffen".** Wessen
    // Verein an diesem Spieltag frei hat, für den gibt es nichts anzukündigen.
    if (s == null) {
      return Text(
        '–',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          vereinsKuerzel(s.gegner),
          maxLines: 1,
          style: TextStyle(
            fontSize: Schrift.klein,
            height: 1.1,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
            color: scheme.onSurface,
          ),
        ),
        Text(
          anpfiffKurz(s.anpfiff),
          maxLines: 1,
          style: TextStyle(
            fontSize: Schrift.mikro,
            height: 1.25,
            fontWeight: FontWeight.w600,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// **Eine Pflichtposition, die niemand besetzt.**
///
/// Sie entsteht nicht durch eine Entscheidung: Verlässt der einzige Torwart
/// die Bundesliga, nimmt ihn der Abgangs-Lauf aus dem Kader (Migration 0117),
/// und die Elf hat von da an zehn Mann (0120). Vorher war davon in der
/// Duell-Ansicht **nichts** zu sehen — die Zelle war ein leerer `SizedBox`,
/// und stand auf beiden Seiten keiner, verschwand der ganze Block. Wer
/// draufschaute, sah eine ordentliche Aufstellung mit einer Reihe weniger.
///
/// Gold, nicht Rot: Es ist kein Fehler, sondern etwas, das noch zu tun ist —
/// dieselbe Farbe wie „Aufstellung · Noch nicht gestellt" auf der
/// Liga-Übersicht.
class _FehlendePosition extends StatelessWidget {
  const _FehlendePosition({required this.pos});

  final PlayerPosition pos;

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFFFC83D);
    return SizedBox(
      height: 60,
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: gold.withValues(alpha: 0.12),
              border: Border.all(color: gold.withValues(alpha: 0.55)),
            ),
            child: const Icon(Icons.priority_high, size: 17, color: gold),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  // **Nicht `pos.label`.** Das ist „Tor", und „Kein Tor" wäre
                  // in einer Fußball-App die denkbar falscheste Auskunft.
                  switch (pos) {
                    PlayerPosition.gk => 'Kein Torwart',
                    PlayerPosition.def => 'Kein Abwehrspieler',
                    PlayerPosition.mid => 'Kein Mittelfeldspieler',
                    PlayerPosition.fwd => 'Kein Stürmer',
                  },
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: Schrift.koerperKlein,
                    fontWeight: FontWeight.w700,
                    color: gold,
                  ),
                ),
                Text(
                  'Position unbesetzt',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: Schrift.klein,
                    color: gold.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
