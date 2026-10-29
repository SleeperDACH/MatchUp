import '../../../app/farben.dart';
import 'package:flutter/material.dart';
import '../../../app/widgets/skelett.dart';
import '../../../app/widgets/kapitelmarke.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/typografie.dart';
import '../../../core/ui/app_avatar.dart';
import '../../auth/providers.dart';
import '../logic/fantasy_scoring_engine.dart';
import '../logic/h2h_grundlage.dart';
import '../../../core/logic/round_robin.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';
import 'manager_profile_screen.dart';
import 'playoff_bracket_screen.dart';
import 'weekly_recap_screen.dart';
import 'liga_duelle_band.dart';
import '../logic/saisonverlauf.dart';
import '../logic/playoff.dart';

/// Eigenständiger Screen (mit AppBar) — dünne Hülle um [FantasyTableBody].
class FantasyTableScreen extends StatelessWidget {
  const FantasyTableScreen({super.key, required this.league});

  final FantasyLeague league;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Liga-Tabelle')),
      body: FantasyTableBody(league: league),
    );
  }
}

/// Liga-Tabelle nach **Head-to-Head-Bilanz**: pro Spieltag ein 1-gegen-1
/// (effektive Startelf), gewertet als Sieg / Unentschieden / Niederlage.
/// Sortiert nach Siegen, dann Punktedifferenz. Body ohne Scaffold, damit er
/// als Tab einsetzbar ist.
class FantasyTableBody extends ConsumerStatefulWidget {
  const FantasyTableBody({super.key, required this.league});

  final FantasyLeague league;

  @override
  ConsumerState<FantasyTableBody> createState() => _FantasyTableBodyState();
}

class _FantasyTableBodyState extends ConsumerState<FantasyTableBody> {
  /// Gewählter Spieltag im Rückblick; `null` = der zuletzt abgepfiffene.
  int? _rueckblick;

  @override
  Widget build(BuildContext context) {
    final league = widget.league;
    final managersAsync = ref.watch(fantasyManagersProvider(league.id));
    final poolAsync = ref.watch(playerPoolProvider);
    // Lädt den Pool nach, wenn eine Elf einen Spieler enthält, den er nicht
    // kennt — sonst fehlten dessen Punkte nur auf diesem Gerät.
    ref.watch(poolVollstaendigProvider(league.id));
    final roster = ref.watch(leagueRosterProvider(league.id)).valueOrNull ??
        const <RosterEntry>[];
    final seasonStatsAsync = ref.watch(seasonStatsProvider);
    final lineups = ref.watch(leagueLineupsProvider(league.id)).valueOrNull ??
        const <FantasyLineup>[];
    final myId = ref.watch(currentUserProvider)?.id;

    // Nur wenn nichts dasteht: Der Mitgliederstrom meldet bei jedem
    // Wiederverbinden „lädt", und die Tabelle fiel dabei auf einen leeren
    // Kreis zurück.
    final managers = managersAsync.valueOrNull;
    final pool = poolAsync.valueOrNull;
    if (managers == null || pool == null) {
      return const Skelett();
    }
    final playerById = {for (final p in pool) p.id: p};
    final nameOf = {for (final m in managers) m.userId: m.display};
    final seasonStats = seasonStatsAsync.valueOrNull ??
        const <int, Map<String, PlayerMatchStats>>{};

    if (managers.length < 2) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Die Tabelle braucht mindestens zwei Manager.',
              textAlign: TextAlign.center),
        ),
      );
    }

    // Reihenfolge und gewertete Punkte kommen aus derselben Funktion wie im
    // Saisonverlauf des Ligaprofils — sonst widersprächen sich die Bilanzen.
    final grundlage = h2hGrundlage(
      league: league,
      managers: managers,
      roster: roster,
      lineups: lineups,
      playerById: playerById,
      seasonStats: seasonStats,
      abgepfiffen: ref.watch(abgepfiffeneRundenProvider),
    );
    final ids = grundlage.ids;
    final totalsByRound = grundlage.summen;
    final standings =
        h2hStandings(ids, totalsByRound, remisGrenze: grundlage.remis);
    final nonePlayed = standings.every((r) => r.played == 0);

    // Nur veröffentlichte Rückblicke (seit 19.10.2026: ab dem Wechsel auf
    // den nächsten Spieltag).
    final veroeffentlicht = ref.watch(veroeffentlichteRueckblickeProvider);
    final rueckblick = _rueckblick ??
        (veroeffentlicht.isEmpty ? null : veroeffentlicht.last);

    // Zeile und Trennlinie stehen als Helfer da, weil die Tabelle seit dem
    // Podest **zwei** Schleifen hat (die ersten drei auf gemeinsamer Fläche,
    // der Rest darunter) — zwei Kopien derselben Zeile wären die nächste
    // Stelle, an der etwas auseinanderläuft.
    Widget trenner() => Divider(
          height: 1,
          indent: 12,
          endIndent: 12,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.07),
        );

    // **Bewegung seit dem vorigen Spieltag**: dieselbe Tabelle ohne den
    // zuletzt gewerteten Spieltag. Erst ab zwei gewerteten Spieltagen — beim
    // ersten gibt es nichts, wovon man sich bewegt hätte.
    final gewertet = totalsByRound.keys.toList()..sort();
    final vorher = gewertet.length < 2
        ? null
        : h2hStandings(ids, {
            for (final e in totalsByRound.entries)
              if (e.key != gewertet.last) e.key: e.value,
          }, remisGrenze: grundlage.remis);
    final rangVorher = vorher == null
        ? null
        : {for (final (i, r) in vorher.indexed) r.managerId: i + 1};
    final byId = {for (final m in managers) m.userId: m};

    Widget zeile(int i, H2HRecord r) {
      final verlauf = saisonverlauf(
        ids: ids,
        managerId: r.managerId,
        gewertet: totalsByRound,
        letzteRunde: kRegularSeasonMatchdays,
        remisGrenze: grundlage.remis,
      );
      final alt = rangVorher?[r.managerId];
      return _TabellenZeile(
        rank: i + 1,
        manager: byId[r.managerId],
        record: r,
        serie: serie(verlauf),
        bewegung: alt == null ? null : alt - (i + 1),
        me: r.managerId == myId,
        onTap: () => showManagerProfile(context,
            league: league,
            managerId: r.managerId,
            managerName: nameOf[r.managerId] ?? '?'),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (seasonStatsAsync.isLoading)
          const LinearProgressIndicator(minHeight: 2),
        // **Alle Duelle des Spieltags auf einen Blick** (16.10.2026, nach
        // dem Vorbild Sleeper) — wischbar, ein Tipp führt in den
        // MatchUp-Reiter.
        if (ref.watch(fantasyCurrentRoundProvider).valueOrNull
            case final runde?) ...[
          _Marke('Spieltag $runde'),
          LigaDuelleBand(league: league),
        ],
        _Marke('Tabelle', info: (
          'So wird gewertet',
          'Je Spieltag ein Duell mit der effektiven Startelf — 3 Punkte für '
              'einen Sieg, 1 für ein Unentschieden. '
              '${league.remisGrenze == null ? 'Unentschieden ist ein Duell nur bei exakt gleicher Punktzahl.' : 'Unentschieden ist ein Duell, wenn höchstens ${formatPoints(league.remisGrenze!)} Punkte dazwischen liegen.'} '
              'Bei Gleichstand in der Tabelle zählen die erzielten '
              'Spielerpunkte.\n\nØ ist der Schnitt je Duell; spielfreie '
              'Spieltage zählen nicht mit.',
        )),
        if (nonePlayed)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Text(
              'Noch keine gewerteten Spieltage — die Bilanz startet bei 0.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        // **Kopfzeile statt Erklärabsatz.** Vorher stand unter der Tabelle ein
        // fünfzeiliger Text, der erklärte, wofür S, U, N und „erzielt" stehen —
        // an der Stelle, an der ihn niemand liest. Jetzt steht es über den
        // Spalten, wo es hingehört.
        const _TabellenKopf(),
        // **Ohne Kasten** (16.10.2026, nach dem Vorbild Sleeper): Die
        // Zeilen stehen auf dem Grund, Haarlinien trennen sie. Der Rahmen um
        // die ganze Tabelle sagte nichts, was die Linien nicht schon sagen.
        for (final (i, r) in standings.indexed) ...[
          if (i > 0) trenner(),
          zeile(i, r),
        ],

        // --- Rückblick -----------------------------------------------------
        // Der Wochen-Recap wohnt hier, nicht mehr nur auf der Übersicht: Dort
        // zeigte er allein den laufenden Spieltag, und wer auf eine frühere
        // Woche zurückwollte, hatte keinen Weg dorthin.
        if (veroeffentlicht.isNotEmpty && rueckblick != null) ...[
          const _Marke('Rückblick'),
          _SpieltagWahl(
            runden: veroeffentlicht,
            gewaehlt: rueckblick,
            onWahl: (r) => setState(() => _rueckblick = r),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: WeeklyRecapCard(league: league, runde: rueckblick),
          ),
        ],

        // --- Playoffs ------------------------------------------------------
        // **Das Bracket steht unten**, auf Ansage. Es war die erste Zeile des
        // Reiters und nahm sie der Tabelle weg — dabei ist es der Ausblick
        // aufs Saisonende und nicht die Auskunft, wegen der man hier
        // hereinkommt. Mit eigener Kapitelmarke, sonst schwebte der Knopf
        // hinter dem Rueckblick ohne Bezug.
        if (league.hasPlayoffs) ...[
          const _Marke('Playoffs'),
          _BracketButton(league: league),
        ],
      ],
    );
  }
}

/// Kapitelmarke: farbiger Strich, Wort, Haarlinie bis an den Rand — dieselbe
/// Gliederung wie auf dem Startbildschirm und im Live-Tab.
class _Marke extends StatelessWidget {
  const _Marke(this.wort, {this.info});

  final String wort;
  final (String, String)? info;

  // Die App-weite Kapitelmarke statt einer eigenen Fassung mit grünem
  // Strich — Grün heißt „ich / gut", eine Rubrik ist keins von beidem
  // (Design-Ideen Punkt 3, 15.10.2026).
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Kapitelmarke(wort, obenLuft: 14, info: info),
      );
}

/// Spaltenköpfe der Tabelle.
///
/// Die Breiten müssen zu [_TabellenZeile] passen — sie stehen deshalb als
/// Konstanten an einer Stelle, nicht zweimal als Zahl im Layout.
class _TabellenKopf extends StatelessWidget {
  const _TabellenKopf();

  static const rangBreite = 30.0;
  static const bildBreite = 36.0;
  /// **Zwei Zahlenspalten, beide groß** (auf Ansage, 16.10.2026): „Für" und
  /// „Gegen" sind raus, damit Punkte und Schnitt Platz und Größe bekommen —
  /// in vier Spalten à 14 Punkt war keine auf einen Blick zu lesen.
  static const punkteBreite = 48.0;

  /// **Der Schnitt je Duell in eigener Spalte** (auf Ansage, 14.10.2026):
  /// Die Gesamtpunkte vergleichen nur, solange alle gleich oft gespielt
  /// haben.
  static const schnittBreite = 64.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stil = TextStyle(
      fontSize: Schrift.label,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.8,
      color: scheme.onSurfaceVariant,
    );
    Widget zahl(String t, double b) =>
        SizedBox(width: b, child: Text(t, style: stil, textAlign: TextAlign.end));
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
      child: Row(
        children: [
          SizedBox(width: rangBreite, child: Text('#', style: stil)),
          const SizedBox(width: bildBreite + 10),
          Expanded(child: Text('TEAM', style: stil)),
          // Ø links, die Punkte ganz rechts (auf Ansage, 16.10.2026): Die
          // Zahl, nach der sortiert wird, steht an der Außenkante.
          zahl('Ø', schnittBreite),
          zahl('PKT', punkteBreite),
        ],
      ),
    );
  }
}

/// Spieltagswahl im Rückblick: ‹ Spieltag N ›.
///
/// Die Pfeile nennen ihr **Ziel**, nicht ihre Richtung — dieselbe Regel wie
/// bei den übrigen Blätter-Pfeilen der App: Vorgelesen sagt „Zurück" allein
/// nicht, wohin es geht.
class _SpieltagWahl extends StatelessWidget {
  const _SpieltagWahl({
    required this.runden,
    required this.gewaehlt,
    required this.onWahl,
  });

  final List<int> runden;
  final int gewaehlt;
  final ValueChanged<int> onWahl;

  @override
  Widget build(BuildContext context) {
    final i = runden.indexOf(gewaehlt);
    // `runden` ist aufsteigend: links geht es zum **früheren** Spieltag.
    final frueher = i > 0 ? runden[i - 1] : null;
    final spaeter = i >= 0 && i < runden.length - 1 ? runden[i + 1] : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip:
                frueher == null ? 'Zurück' : 'Zurück zu Spieltag $frueher',
            onPressed: frueher == null ? null : () => onWahl(frueher),
            icon: const Icon(Icons.chevron_left),
          ),
          Text('Spieltag $gewaehlt',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          IconButton(
            tooltip:
                spaeter == null ? 'Weiter' : 'Weiter zu Spieltag $spaeter',
            onPressed: spaeter == null ? null : () => onWahl(spaeter),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

/// Einstieg zum Playoff-Bracket (Winner- + Loser-Bracket, Endplatzierung).
class _BracketButton extends StatelessWidget {
  const _BracketButton({required this.league});

  final FantasyLeague league;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
      child: Material(
        color: context.farben.gold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => PlayoffBracketScreen(league: league))),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.account_tree_outlined, color: context.farben.gold),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Playoff-Bracket',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(
                        'Winner- & Loser-Bracket — alle Abschlussplätze',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// **Eine Zeile der Tabelle — nach dem Vorbild Sleeper** (16.10.2026).
///
/// Ohne Kasten auf dem Grund, durch Haarlinien getrennt. Links der Rang und
/// darunter, wie er sich seit dem vorigen Spieltag bewegt hat („+1" grün,
/// „−2" rot). Dann Bild, Name, darunter Bilanz und Serie. Rechts die Zahlen:
/// Der Schnitt je Duell, ganz rechts groß die Tabellenpunkte. Erzielte und kassierte
/// Spielerpunkte standen kurz als zwei weitere Spalten da und sind auf
/// Ansage wieder raus (16.10.2026) — sie nahmen den beiden Zahlen den Platz,
/// auf die es ankommt.
///
/// **Das Podest mit drei Größen ist damit weg** — alle Zeilen gleich hoch,
/// wie bei Sleeper; die ersten drei tragen ihren Rang in Medaillenfarbe. Die
/// eigene Zeile ist hell hinterlegt, nicht farbig: Hell heißt in dieser App
/// „das bist du".
class _TabellenZeile extends StatelessWidget {
  const _TabellenZeile({
    required this.rank,
    required this.manager,
    required this.record,
    required this.serie,
    required this.bewegung,
    required this.me,
    required this.onTap,
  });

  final int rank;
  final FantasyManager? manager;
  final H2HRecord record;
  final ({DuellAusgang ausgang, int anzahl})? serie;

  /// Plätze gewonnen (positiv) oder verloren seit dem vorigen Spieltag;
  /// `null`, solange es keinen vorigen gibt.
  final int? bewegung;
  final bool me;
  final VoidCallback onTap;


  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = record;
    final m = manager;
    final rangFarbe = switch (rank) {
      1 => context.farben.gold,
      2 => context.farben.silber,
      3 => context.farben.bronze,
      _ => scheme.onSurfaceVariant,
    };
    final zahlStil = TextStyle(
      fontSize: Schrift.text,
      fontWeight: FontWeight.w600,
      color: scheme.onSurface,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    Widget zahl(String t, double b, {TextStyle? stil}) => SizedBox(
          width: b,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(t, style: stil ?? zahlStil, textAlign: TextAlign.end),
          ),
        );

    final (pfeil, buchstabe, serieFarbe) = switch (serie?.ausgang) {
      DuellAusgang.sieg => ('▲', 'S', context.farben.gruen),
      DuellAusgang.niederlage => ('▼', 'N', context.farben.rot),
      _ => ('■', 'U', context.farben.neutral),
    };
    final hatTeamname = m?.teamName != null && m!.teamName!.trim().isNotEmpty;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: me
            ? BoxDecoration(
                color: scheme.onSurface.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
              )
            : null,
        child: Row(
          children: [
            SizedBox(
              width: _TabellenKopf.rangBreite,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$rank',
                    style: TextStyle(
                      fontSize: Schrift.titel,
                      fontWeight: FontWeight.w800,
                      color: rangFarbe,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (bewegung != null && bewegung != 0)
                    Text(
                      bewegung! > 0 ? '+$bewegung' : '−${-bewegung!}',
                      style: TextStyle(
                        fontSize: Schrift.label,
                        fontWeight: FontWeight.w800,
                        color: bewegung! > 0
                            ? context.farben.gruen
                            : context.farben.rot,
                      ),
                    ),
                ],
              ),
            ),
            AppAvatar(
              imageUrl: m?.avatarUrl,
              emoji: m?.avatarEmoji,
              colorHex: m?.avatarColor,
              fallbackText: m?.display,
              size: _TabellenKopf.bildBreite,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      m?.display ?? '?',
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: Schrift.text,
                        fontWeight: me ? FontWeight.w800 : FontWeight.w700,
                      ),
                    ),
                  ),
                  // Wie bei Sleeper der Nutzername unter dem Teamnamen — nur,
                  // wenn es einen Teamnamen gibt; sonst stünde er doppelt.
                  if (hatTeamname)
                    Text(
                      '@${m.username}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: Schrift.label,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  const SizedBox(height: 2),
                  Text.rich(
                    TextSpan(children: [
                      // Reihenfolge Sieg – Unentschieden – Niederlage.
                      TextSpan(text: '${r.wins}-${r.ties}-${r.losses}'),
                      if (serie != null) ...[
                        const TextSpan(text: ' · '),
                        TextSpan(
                          text: '$pfeil${serie!.anzahl}$buchstabe',
                          style: TextStyle(
                              color: serieFarbe, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ]),
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: Schrift.label,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            zahl(
              r.played == 0 ? '–' : formatPoints(r.pointsFor / r.played),
              _TabellenKopf.schnittBreite,
              stil: zahlStil.copyWith(
                  fontSize: Schrift.titel,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant),
            ),
            zahl('${record.points}', _TabellenKopf.punkteBreite,
                stil: zahlStil.copyWith(
                    fontSize: Schrift.gross, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}
