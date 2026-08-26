import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/config/app_config.dart';
import '../core/models/models.dart';
import '../core/models/team_fixture.dart';
import '../core/util/club_colors.dart';
import '../core/ui/app_avatar.dart';
import '../features/auth/providers.dart';
import '../features/fantasy/logic/draft_order.dart';
import '../features/fantasy/logic/league_status.dart';
import '../features/fantasy/models/fantasy_models.dart';
import '../features/fantasy/providers.dart';
import '../features/fantasy/ui/create_fantasy_league.dart';
import '../features/fantasy/ui/fantasy_league_screen.dart';
import '../features/fantasy/ui/league_colors.dart';
import '../features/leagues/providers.dart';
import '../features/leagues/ui/join_by_code.dart';
import '../features/leagues/ui/league_search_screen.dart';
import '../features/messaging/providers.dart';
import '../features/messaging/ui/conversations_screen.dart';
import '../features/news/models/news_item.dart';
import '../features/news/providers.dart';
import '../features/news/ui/transfers_screen.dart';
import '../features/news/ui/news_list_screen.dart';
import '../features/news/ui/news_tile.dart';
import '../features/tippspiel/models/tip_round.dart';
import '../features/tippspiel/providers.dart';
import '../features/tippspiel/ui/create_tip_round.dart';
import '../features/tippspiel/ui/team_badge.dart';
import 'home_favorites.dart';
import 'home_menu_drawer.dart';
import 'home_tip_status.dart';
import 'league_screen.dart';
import 'match_detail_screen.dart';
import 'theme.dart';
import 'widgets/league_logo.dart';
import 'widgets/matchup_chevron.dart';
import 'widgets/pulsing_dot.dart';

/// Startbildschirm. Fantasy ist der Hauptfokus und steht oben; das
/// Tippspiel folgt als zweiter Bereich darunter.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final configured = AppConfig.isSupabaseConfigured;

    return Scaffold(
      // Seitenmenü (Profil · Freunde · Chats) über das Hamburger-Symbol.
      drawer: (configured && user != null) ? const HomeMenuDrawer() : null,
      appBar: AppBar(
        centerTitle: true,
        // Hamburger oben links öffnet das schmale Seitenmenü.
        leading: (configured && user != null)
            ? Builder(
                builder: (context) => IconButton(
                  tooltip: 'Menü',
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              )
            : null,
        title: const _MatchUpTitle(),
        actions: [
          // Öffentliche Ligasuche direkt neben dem Erstellen/Beitreten-Knopf.
          if (configured && user != null)
            IconButton(
              tooltip: 'Ligen entdecken',
              icon: const Icon(Icons.search, size: 25),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LeagueSearchScreen()),
              ),
            ),
          // Erstellen & Beitreten zusammengefasst in einem Knopf oben rechts.
          if (configured && user != null)
            IconButton(
              tooltip: 'Erstellen oder beitreten',
              icon: const Icon(Icons.add_circle_outline, size: 27),
              onPressed: () => showCreateOrJoin(context, ref),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myFantasyLeaguesProvider);
          ref.invalidate(myRoundsProvider);
        },
        child: ListView(
          // Unten extra Platz, damit der letzte Inhalt nicht unter der
          // schwebenden Glas-Navigationsleiste liegt.
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (!configured)
              // Sollte im ausgelieferten Build nie erscheinen — die
              // Server-Adresse steckt seit dem TestFlight-Fehlschlag fest in
              // AppConfig. Bleibt als Auffangnetz für Builds, die sie per
              // --dart-define bewusst leeren. Deshalb kein Entwickler-Hinweis
              // mehr im Text: Beta-Tester können damit nichts anfangen.
              const _InfoCard(
                'Fantasy & Ligen brauchen eine Server-Verbindung. Diese '
                'App-Version wurde ohne Server ausgeliefert.',
              )
            else ...[
              const _Appear(child: _GreetingBar()),
              const SizedBox(height: 12),
              // Die Kopfkarte führt: das nächste Spiel des eigenen Vereins
              // ist der Inhalt, an dem eine Zeit hängt. Sie blendet sich
              // aus, wenn es keinen Favoriten gibt.
              const _Appear(delayMs: 40, child: _NaechstesSpiel()),
              const SizedBox(height: 18),
              // Noch gar keine Liga (Fantasy + Tippspiel beide leer geladen):
              // statt zweier leerer Abschnitte ein großer Einstieg.
              if (_beideLeer(ref))
                const _Appear(delayMs: 80, child: _NoLeaguesHero())
              else ...[
                // Der Abschnitt mit Inhalt steht oben. Wer nur ein Tippspiel
                // hat, sah sonst zuerst eine leere Ligareihe, in der nur die
                // große „+"-Karte stand.
                for (final abschnitt
                    in _tippspielZuerst(ref)
                        ? [
                            _tippspielSection(context, ref),
                            _fantasySection(context, ref),
                          ]
                        : [
                            _fantasySection(context, ref),
                            _tippspielSection(context, ref),
                          ]) ...[
                  _Appear(
                    delayMs: 80,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: abschnitt,
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
              ],
              // Die Abschnitte bringen ihren Abstand schon mit.
              const SizedBox(height: 4),
              const _Appear(delayMs: 190, child: _FavoritenSpiele()),
              const _Appear(delayMs: 220, child: _NewsSection()),
            ],
          ],
        ),
      ),
    );
  }

  /// Eigenständige Tipprunden. Ligainterne Tippspiele (an eine Fantasy-Liga
  /// gekoppelt) erreicht man ausschließlich über die Liga; `null` = lädt noch.
  List<TipRound>? _standaloneRounds(WidgetRef ref) => ref
      .watch(myRoundsProvider)
      .valueOrNull
      ?.where((r) => !r.isFantasyLinked)
      .toList();

  bool _beideLeer(WidgetRef ref) =>
      (ref.watch(myFantasyLeaguesProvider).valueOrNull?.isEmpty ?? false) &&
      (_standaloneRounds(ref)?.isEmpty ?? false);

  /// Nur ein Tippspiel, keine Fantasy-Liga → Tippspiel nach oben.
  bool _tippspielZuerst(WidgetRef ref) =>
      (ref.watch(myFantasyLeaguesProvider).valueOrNull?.isEmpty ?? false) &&
      (_standaloneRounds(ref)?.isNotEmpty ?? false);

  // ------------------------------------------------------------------
  // Fantasy (Hauptbereich): quer zu wischende Karten. Bewusst eine andere
  // Form als das Tippspiel darunter und die News ganz unten — drei gleich
  // gebaute Listen untereinander waren der Grund, warum der Screen überall
  // gleich aussah.
  // ------------------------------------------------------------------
  List<Widget> _fantasySection(BuildContext context, WidgetRef ref) {
    final leagues = ref.watch(myFantasyLeaguesProvider);
    final list = leagues.valueOrNull;
    return [
      abschnittsKopf(
        context,
        'Meine Ligen',
        count: list?.length,
        marke: MatchUpColors.green,
      ),
      if (leagues.hasError)
        _InfoCard(
          'Deine Ligen ließen sich nicht laden.',
          hinweis:
              'Zieh den Screen nach unten, um es noch einmal zu '
              'versuchen.',
          technisch: '${leagues.error}',
        )
      else if (list == null)
        SizedBox(
          height: kartenHoehe(context, _kLeagueCardHeight),
          child: const Center(child: CircularProgressIndicator()),
        )
      else if (list.isEmpty)
        // Wer noch keine Liga hat, braucht den Einstieg — sonst stünde hier
        // eine leere Überschrift. Als Zeile statt als Karte: so nimmt er ein
        // Sechstel des Platzes und sagt nebenbei, wozu das gut ist.
        const _CreateRow(
          text: 'Fantasy-Liga anlegen',
          hint: 'Draften, Kader managen, Saison spielen',
          farbe: MatchUpColors.green,
        )
      else
        // Hier hängt **keine** „+"-Karte mehr hinter den Ligen. Sie stand die
        // ganze Saison in der Reihe für etwas, das man ein- oder zweimal im
        // Jahr tut, und war bei vier Ligen die angeschnittene fünfte Karte am
        // rechten Rand — genau die Stelle, an der man eine weitere Liga
        // vermutet. Angelegt wird über das „+" oben rechts; wer noch gar keine
        // Liga hat, sieht statt der Reihe die `_CreateRow`.
        _Bleed(
          hoehe: kartenHoehe(context, _kLeagueCardHeight),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: _kLeagueRowPad),
            physics: const BouncingScrollPhysics(),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(width: _kLeagueCardGap),
            itemBuilder: (_, i) => _FantasyLeagueCard(league: list[i]),
          ),
        ),
    ];
  }

  // ------------------------------------------------------------------
  // Tippspiel: Zeilen. Bewusst eine **andere Form** als die Kartenreihe der
  // Ligen darüber — vorher war es dieselbe Reihe, nur flacher, und dadurch
  // sah der halbe Screen gleich aus. Die Zeile gibt dem Namen zugleich die
  // Breite, die eine Karte für vier nebeneinander nie hat.
  // ------------------------------------------------------------------
  List<Widget> _tippspielSection(BuildContext context, WidgetRef ref) {
    final rounds = ref.watch(myRoundsProvider);
    final standalone = _standaloneRounds(ref);
    return [
      abschnittsKopf(
        context,
        'Tippspiel',
        count: standalone?.length,
        marke: _kTipGold,
      ),
      if (rounds.hasError)
        _InfoCard(
          'Deine Tipprunden ließen sich nicht laden.',
          hinweis:
              'Zieh den Screen nach unten, um es noch einmal zu '
              'versuchen.',
          technisch: '${rounds.error}',
        )
      else if (standalone == null)
        SizedBox(
          height: minTastflaeche(context) + 12,
          child: const Center(child: CircularProgressIndicator()),
        )
      else if (standalone.isEmpty)
        const _CreateRow(
          text: 'Tippspiel anlegen',
          hint: 'Spieltage tippen, Punkte sammeln',
          farbe: _kTipGold,
        )
      else
        // Zeilen, keine Reihe: die Runden laufen längs und reichen deshalb
        // nur bis zum Seitenrand — kein `_Bleed`, kein Schrift-Deckel.
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < standalone.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  color: Theme.of(
                    context,
                  ).colorScheme.outlineVariant.withValues(alpha: 0.6),
                ),
              _TipRoundRow(round: standalone[i]),
            ],
          ],
        ),
    ];
  }
}

/// Kleinste Tastfläche der Plattform: **44 Punkte auf iOS, 48 auf Android**.
///
/// Zwei Zahlen, nicht eine. Hier stand einmal 36, begründet mit den 24 aus
/// WCAG 2.2 — die gelten aber für Web. Beides in eine plattformübergreifende
/// Zahl zusammenzuziehen ist der Fehler, den Apples und Googles Richtlinien
/// beide ausdrücklich nennen: sie sagen verschiedene Maße, weil Finger auf
/// beiden Systemen verschieden geführt werden.
double minTastflaeche(BuildContext context) =>
    Theme.of(context).platform == TargetPlatform.android ? 48 : 44;

/// Kopf eines Abschnitts: kleine Versalien, Zähler, rechts entweder ein
/// Zusatz (das Datum bei „Meine Vereine") oder ein Link. Vorher trug jeder
/// Abschnitt denselben fetten Balken mit Symbol — drei gleiche Köpfe über
/// drei gleichen Kästen.
///
/// Eine Funktion für alle vier Abschnitte; „Meine Vereine" und „News" hatten
/// die Zeile abgeschrieben, samt der 12-px-Versalien und des `letterSpacing`.
/// Beim Vorlesen zahlt sich das aus: die Versalien stehen nur im Bild —
/// VoiceOver und TalkBack buchstabieren „NEWS" sonst als N-E-W-S. Als
/// Überschrift ausgezeichnet ist die Zeile obendrein, damit sich der Screen
/// abschnittsweise durchspringen lässt statt Zeile für Zeile.
Widget abschnittsKopf(
  BuildContext context,
  String titel, {
  int? count,
  String? zusatz,
  String? moreLabel,
  VoidCallback? onMore,
  Color? marke,
}) {
  final scheme = Theme.of(context).colorScheme;
  final versalien = TextStyle(
    color: scheme.onSurface.withValues(alpha: 0.92),
    fontSize: 12,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.2,
  );
  return Padding(
    // Steht rechts ein Link, bringt dessen Tastfläche die Luft nach unten
    // schon mit — sonst klaffte unter der Überschrift das Doppelte.
    padding: EdgeInsets.fromLTRB(4, 0, onMore == null ? 4 : 0, 4),
    child: ConstrainedBox(
      // Mindest-, keine Festhöhe: Der Kopf ist zugleich die Tastfläche des
      // Links, also bekommt er das Maß der Plattform — und weil alle Köpfe
      // dasselbe Maß tragen sollen, gilt es für alle. Kostet gegenüber der
      // reinen Textzeile rund 26 Punkte je Abschnitt; der Screen hat sie.
      // Nach oben offen, damit die Zeile bei großer Systemschrift umbrechen
      // darf.
      constraints: BoxConstraints(minHeight: minTastflaeche(context)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Beide Seiten dürfen schrumpfen und umbrechen. Bei dreifacher
          // Systemschrift passten „MEINE VEREINE" und das Datum sonst nicht
          // mehr nebeneinander — die Zeile lief 67 Punkte über den rechten
          // Rand hinaus, mit dem gelb-schwarzen Balken darüber.
          Flexible(
            flex: 3,
            child: Semantics(
              header: true,
              label: count != null && count > 0 ? '$titel, $count' : titel,
              excludeSemantics: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Ein kurzer Strich in der Farbe des Abschnitts. Fünf
                  // gleiche graue Versalzeilen untereinander gaben dem Screen
                  // keinen Takt — man sah fünfmal dasselbe und wusste nicht,
                  // wo ein Bereich anfängt. Der Strich ist die kleinste
                  // Menge Farbe, die das trennt, und er wiederholt die Farbe,
                  // die im Abschnitt darunter ohnehin vorkommt.
                  if (marke != null) ...[
                    Container(
                      width: 3,
                      height: 13,
                      decoration: BoxDecoration(
                        color: marke,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Flexible(child: Text(titel.toUpperCase(), style: versalien)),
                  if (count != null && count > 0) ...[
                    const SizedBox(width: 8),
                    Text(
                      '$count',
                      style: versalien.copyWith(
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (zusatz != null) ...[
            const SizedBox(width: 8),
            Flexible(
              flex: 2,
              child: Text(
                zusatz,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          if (onMore != null)
            _MehrLink(label: moreLabel ?? 'Alle', onTap: onMore),
        ],
      ),
    ),
  );
}

/// „Alle ›" am rechten Rand einer Abschnittsüberschrift.
///
/// War ein `GestureDetector` um 13-px-Text: gut 22 Punkte hoch, halb so viel
/// wie [minTastflaeche] verlangt — und für die Vorlesehilfe gar kein Knopf,
/// sondern vorgelesener Text mit einem Chevron am Ende („Alle, geschlossenes
/// Anführungszeichen"). Jetzt ein echtes Feld über die volle Kopfhöhe; das
/// Chevron ist Zierde und bleibt draußen.
class _MehrLink extends StatelessWidget {
  const _MehrLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: '$label anzeigen',
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          constraints: BoxConstraints(
            minWidth: minTastflaeche(context),
            minHeight: minTastflaeche(context),
          ),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            '$label ›',
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// Die Kopfkarte: das **nächste Spiel eines favorisierten Vereins**.
///
/// Sie steht ganz oben, weil die Zeit führt. Vorher war die größte und
/// fetteste Schrift auf dem Schirm „Hallo, SFV03" — eine Zeile ohne
/// Information —, und das nächste Spiel des eigenen Vereins stand als 46
/// Punkte hohe Zeile weit unten zwischen Ligen und News. Jetzt trägt es den
/// Kopf, und die Begrüßung ist auf eine graue Zeile zurückgetreten.
///
/// Gezeigt wird das Spiel des **obersten Favoriten** — nicht das früheste des
/// Tages. Wer Bayern über Bochum stellt, will an einem Samstag mit beiden
/// Bayern oben sehen, auch wenn Bochum um 13:30 anfängt. Welcher Verein oben
/// steht, entscheidet dieselbe Reihenfolge wie im Favoriten-Tab
/// (`favoritenRaenge`); vorsortiert wird im `favoritenSpieleProvider`, hier
/// steht deshalb schlicht der erste Eintrag.
///
/// Die übrigen Partien desselben Tages bleiben unten in [_FavoritenSpiele].
class _NaechstesSpiel extends ConsumerWidget {
  const _NaechstesSpiel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spiele = ref.watch(favoritenSpieleProvider).valueOrNull;
    // Ohne Favoriten (oder solange nichts geladen ist) fällt die Kopfkarte
    // weg und der Screen beginnt mit den Ligen — ein leerer Platzhalter an
    // der auffälligsten Stelle wäre schlechter als keine Karte.
    if (spiele == null || spiele.isEmpty) return const SizedBox.shrink();
    final fixture = spiele.first;
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final anstoss = fixture.kickoff.toLocal();
    final laeuft = fixture.status == FixtureStatus.live;
    final tonHeim = vereinsTon(fixture.home.name);
    final tonAusw = vereinsTon(fixture.away.name);

    void oeffnen() => Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MatchDetailScreen(fixtureId: fixture.id),
      ),
    );

    // Die große Zahl ist der Anstoß — sobald gespielt wird, das Ergebnis.
    final zahl = fixture.hasScore
        ? '${fixture.homeScore}:${fixture.awayScore}'
        : DateFormat('HH:mm', 'de_DE').format(anstoss);

    return _PressScale(
      eineAnsage: false,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: oeffnen,
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              // **Die Farben der beiden Vereine**, von links und rechts
              // hereingezogen — aber nur als Andeutung an den Rändern. Die
              // eigentliche Farbe sitzt im Hof hinter den Wappen
              // ([_HeroVerein]). Über die ganze Karte gezogen war sie
              // falsch: Bayern gegen Stuttgart sind zwei rote Vereine, das
              // ergab eine durchgehend rote Fläche, auf der weder die beiden
              // Seiten auseinanderzuhalten waren noch der goldene Sockel
              // sauber lag. So gehört die Farbe zum Verein, nicht zur Karte.
              // Die Mitte bleibt in jedem Fall neutral — dort steht die
              // Uhrzeit, und die soll nicht auf Farbe liegen.
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  _heroGrund(scheme, dark, tonHeim),
                  _heroGrund(scheme, dark, null),
                  _heroGrund(scheme, dark, null),
                  _heroGrund(scheme, dark, tonAusw),
                ],
                stops: const [0.0, 0.30, 0.70, 1.0],
              ),
              border: Border.all(
                color: scheme.onSurface.withValues(alpha: 0.10),
                width: 0.8,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Eine Ansage für das Spiel. Ohne sie wären es sieben
                // Stationen — Wettbewerb, zwei Wappen, zwei Namen, ein
                // nacktes „20:30" und ein Datum —, und keine sagte, in
                // welchem Verhältnis die beiden Vereine zueinander stehen.
                // Der Sockel bleibt draußen: er ist ein eigener Knopf mit
                // einem eigenen Ziel.
                Semantics(
                  button: true,
                  label: [
                    '${fixture.home.name} gegen ${fixture.away.name}',
                    if (fixture.hasScore)
                      'steht $zahl'
                    else
                      '$zahl Uhr, ${DateFormat('EEEE, d. MMMM', 'de_DE').format(anstoss)}',
                    fixture.leagueName,
                  ].join(', '),
                  onTap: oeffnen,
                  excludeSemantics: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                        child: Row(
                          children: [
                            // Das Wettbewerbslogo ist keine Zierde: am selben Tag
                            // stehen hier Pokal und Liga nebeneinander.
                            LeagueLogo(
                              logoUrl: fixture.leagueLogo,
                              name: fixture.leagueName,
                              size: 15,
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                fixture.leagueName.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.4,
                                ),
                              ),
                            ),
                            // Farbe nur, wo etwas ansteht: an einem gewöhnlichen
                            // Spieltag in drei Wochen bleibt die Ecke leer.
                            if (laeuft)
                              const _Marke(
                                text: 'LIVE',
                                farbe: MatchUpColors.red,
                                pulsiert: true,
                              )
                            else if (_istHeute(anstoss))
                              const _Marke(text: 'HEUTE', farbe: _kTipGold),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: _HeroVerein(
                                team: fixture.home,
                                ton: tonHeim,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    zahl,
                                    maxLines: 1,
                                    style: TextStyle(
                                      fontSize: 38,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -1,
                                      height: 1.0,
                                      color: laeuft
                                          ? MatchUpColors.red
                                          : scheme.onSurface,
                                      // Tabellenziffern: die Zahl steht mittig
                                      // zwischen zwei Wappen und darf beim
                                      // Umspringen von 20:30 auf 1:1 nicht wandern.
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    // Der Tag steht hier, nicht die Spielstätte —
                                    // die liefert der Vereins-Spielplan nicht mit,
                                    // und für sie einen zweiten Abruf je Spiel zu
                                    // machen wäre der Zeile nicht wert.
                                    DateFormat(
                                      'EEEE, d. MMM',
                                      'de_DE',
                                    ).format(anstoss),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: scheme.onSurfaceVariant,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: _HeroVerein(
                                team: fixture.away,
                                ton: tonAusw,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                _HeroSockel(fixture: fixture),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ein Verein der Kopfkarte: Wappen über ausgeschriebenem Namen — und hinter
/// dem Wappen ein weicher Hof in der Trikotfarbe.
///
/// Der Hof ist die Stelle, an der die Vereinsfarbe wirklich hingehört: Er
/// klebt am Verein, nicht an der Karte. Wappen sind klein, vielfarbig und im
/// Test wie bei fehlendem Netz gar nicht da; der Hof trägt die Farbe auch
/// dann. Unbekannte Vereine bekommen keinen — siehe [vereinsTon].
class _HeroVerein extends StatelessWidget {
  const _HeroVerein({required this.team, required this.ton});

  final TeamRef team;
  final Color? ton;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 68,
        height: 68,
        alignment: Alignment.center,
        decoration: ton == null
            ? null
            : BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  stops: const [0.34, 1.0],
                  colors: [
                    ton!.withValues(alpha: 0.62),
                    ton!.withValues(alpha: 0.0),
                  ],
                ),
              ),
        child: TeamBadge(team: team, size: 44),
      ),
      const SizedBox(height: 3),
      Text(
        // Ausgeschrieben und zweizeilig: „Borussia Mönchengladbach" soll
        // nicht zu „Borussia M…" werden, und die Kurzform („ENE") sagt
        // ohne Tabelle daneben wenig.
        team.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          height: 1.1,
        ),
      ),
    ],
  );
}

/// Kleine Marke am oberen Rand der Kopfkarte („HEUTE", „LIVE").
class _Marke extends StatelessWidget {
  const _Marke({
    required this.text,
    required this.farbe,
    this.pulsiert = false,
  });

  final String text;
  final Color farbe;
  final bool pulsiert;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (pulsiert) ...[
        PulsingDot(size: 7, color: farbe),
        const SizedBox(width: 5),
      ],
      Text(
        text,
        style: TextStyle(
          color: farbe,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
        ),
      ),
    ],
  );
}

/// Sockel der Kopfkarte: was **ich** mit diesem Spiel noch zu tun habe.
///
/// Die Karte zeigt das Spiel meines Vereins; ob es zugleich in einer meiner
/// Tipprunden liegt, beantwortet [spielTippProvider] über die Fixture-ID.
/// Liegt es in keiner, bleibt der Sockel weg — eine Handlungsleiste ohne
/// Handlung wäre schlimmer als keine.
///
/// Eine **ligainterne** Tipprunde darf hier verlinkt werden, obwohl sie im
/// Tippspiel-Abschnitt bewusst fehlt. Die Regel dort heißt „nicht als eigener
/// Eintrag auflisten, man erreicht sie über die Liga"; hier steht kein
/// Eintrag, sondern der Weg zu **diesem einen** Spiel. `LeagueScreen` kennt
/// den gekoppelten Fall und blendet Liga- und Chat-Tab selbst aus.
class _HeroSockel extends ConsumerWidget {
  const _HeroSockel({required this.fixture});

  final TeamFixture fixture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final treffer = ref.watch(spielTippProvider(fixture.id)).valueOrNull;
    if (treffer == null) return const SizedBox.shrink();

    final tipp = treffer.tipp;
    final anstoss = fixture.kickoff.toLocal();
    final abgelaufen = !anstoss.isAfter(DateTime.now());
    // Nach Anpfiff ist nichts mehr zu tun: dann steht dort der eigene Tipp
    // oder, wenn keiner abgegeben wurde, gar nichts mehr.
    if (tipp == null && abgelaufen) return const SizedBox.shrink();

    final offen = tipp == null;
    final ton = offen ? _kTipGold : scheme.onSurfaceVariant;
    final text = offen
        ? 'Noch nicht getippt'
        : 'Dein Tipp: ${tipp.homeGoals}:${tipp.awayGoals}';
    final detail = offen ? kurzeFrist(anstoss, DateTime.now()) : null;

    void oeffnen() {
      activateRound(ref, treffer.round);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LeagueScreen(round: treffer.round, initialTab: 0),
        ),
      );
    }

    return Semantics(
      button: true,
      label: [text, ?detail, 'in ${treffer.round.name}'].join(', '),
      onTap: oeffnen,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: oeffnen,
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(19),
            bottomRight: Radius.circular(19),
          ),
          child: Container(
            constraints: BoxConstraints(minHeight: minTastflaeche(context)),
            decoration: BoxDecoration(
              color: ton.withValues(alpha: offen ? 0.12 : 0.07),
              border: Border(
                top: BorderSide(color: scheme.outlineVariant, width: 0.8),
              ),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(19),
                bottomRight: Radius.circular(19),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(color: ton, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ton,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (detail != null) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '· $detail',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                Icon(Icons.chevron_right, size: 18, color: ton),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Grund der Kopfkarte an einer Stelle: der Seitengrund, leicht angehoben,
/// und — wo ein Verein steht — mit dessen Farbe unterlegt.
Color _heroGrund(ColorScheme scheme, bool dark, Color? verein) {
  final grund = Color.alphaBlend(
    scheme.surfaceContainerHighest.withValues(alpha: dark ? 0.55 : 0.75),
    scheme.surface,
  );
  if (verein == null) return grund;
  return Color.alphaBlend(verein.withValues(alpha: dark ? 0.16 : 0.10), grund);
}

/// Die Farbe, mit der ein Verein auf einer dunklen Fläche **erkennbar** ist.
///
/// [clubColors] liefert die Trikotfarben, und deren `primary` ist oft Weiß
/// (Stuttgart, Gladbach, Köln, HSV) oder Schwarz (Frankfurt, Freiburg). Beides
/// verschwindet auf dem fast schwarzen Grund oder überstrahlt ihn; erkennbar
/// ist dann die Farbe des Kragens. Deshalb hier die Ausweichregel: zu helle
/// oder zu dunkle Grundfarben treten an `secondary` ab.
///
/// `null` heißt **unbekannter Verein** — und dann bleibt die Karte an dieser
/// Seite grau. Eine erfundene Farbe für einen Pokalgegner aus der Oberliga
/// wäre schlimmer als keine: sie sähe aus wie eine Auskunft.
Color? vereinsTon(String teamName) {
  const unbekannt = ClubColors(Color(0x00000000), Color(0x00000000));
  final farben = clubColors(teamName, fallback: unbekannt);
  if (farben.primary.a == 0) return null;
  final l = farben.primary.computeLuminance();
  return (l > 0.55 || l < 0.05) ? farben.secondary : farben.primary;
}

/// Fällt der Anstoß auf den heutigen Tag?
bool _istHeute(DateTime zeit) {
  final jetzt = DateTime.now();
  return zeit.year == jetzt.year &&
      zeit.month == jetzt.month &&
      zeit.day == jetzt.day;
}

/// Nächste Spiele der favorisierten Vereine — zwischen den eigenen Ligen und
/// den News. Es ist die einzige Stelle auf dem Screen, an der es um Fußball
/// statt um die eigenen Runden geht; deshalb steht sie hinter den Ligen und
/// vor den News.
///
/// Gezeigt wird der **Tag** des nächsten Spiels mit allen Partien darauf: an
/// einem Bundesliga-Samstag will man nicht nur den 15:30-Anstoß sehen.
class _FavoritenSpiele extends ConsumerWidget {
  const _FavoritenSpiele();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alle = ref.watch(favoritenSpieleProvider).valueOrNull;
    // Das erste Spiel trägt die Kopfkarte — es ist das des **obersten
    // Favoriten**, dafür sortiert `favoritenSpielZuerst` die Liste vor. Hier
    // stehen die übrigen Partien desselben Tages, weiter nach Anstoß: An
    // einem Bundesliga-Samstag will man nicht nur den 15:30-Anstoß sehen.
    // Ohne Favoriten, solange nichts geladen ist oder wenn es bei dem einen
    // Spiel bleibt, fällt der Abschnitt weg — eine leere Überschrift wäre
    // schlechter als gar keine.
    final spiele = alle?.skip(1).toList();
    if (spiele == null || spiele.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final tag = spiele.first.kickoff.toLocal();
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          abschnittsKopf(
            context,
            'Meine Vereine',
            zusatz: DateFormat('EEEE, d. MMM', 'de_DE').format(tag),
            marke: _kVereinsBlau,
          ),
          Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.7),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < spiele.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      color: scheme.outlineVariant.withValues(alpha: 0.6),
                    ),
                  _FavoritSpielZeile(fixture: spiele[i]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Eine Partie: Wettbewerbslogo, beide Wappen, beide Kurznamen, rechts die
/// Anstoßzeit. Das Wettbewerbslogo ist nicht Zierde — am selben Tag können
/// Pokal und Liga nebeneinander stehen, und zwei Vereine desselben Klubs
/// (Profis und zweite Mannschaft) tragen denselben Kurznamen.
class _FavoritSpielZeile extends StatelessWidget {
  const _FavoritSpielZeile({required this.fixture});

  final TeamFixture fixture;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final anstoss = DateFormat(
      'HH:mm',
      'de_DE',
    ).format(fixture.kickoff.toLocal());
    void oeffnen() => Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MatchDetailScreen(fixtureId: fixture.id),
      ),
    );
    // Vorgelesen ergab die Zeile fünf Stationen, darunter ein alleinstehendes
    // „15:30" und zwei Vereinsnamen ohne erkennbares Verhältnis zueinander.
    // Ein Satz sagt dasselbe, was das Auge in der Zeile sofort sieht — das
    // „gegen" steht im Bild als Anordnung da und muss hier ausgesprochen
    // werden. Der Wettbewerb gehört dazu: am selben Tag stehen hier Pokal
    // und Liga nebeneinander.
    return Semantics(
      button: true,
      label:
          '${fixture.home.name} gegen ${fixture.away.name}, '
          '$anstoss Uhr, ${fixture.leagueName}',
      onTap: oeffnen,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: oeffnen,
          child: Container(
            // Mit den 20er-Wappen kam die Zeile auf 38 Punkte und blieb damit
            // unter dem Maß beider Plattformen. Als Mindesthöhe statt als
            // ausgerechnetes Polster: 12 Punkte oben und unten ergaben genau
            // Apples 44 und hätten Androids 48 wieder verfehlt.
            constraints: BoxConstraints(minHeight: minTastflaeche(context)),
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  child: LeagueLogo(
                    logoUrl: fixture.leagueLogo,
                    name: fixture.leagueName,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 8),
                TeamBadge(team: fixture.home, size: 20),
                const SizedBox(width: 7),
                // Ausgeschriebene Namen: die Kurzformen („ENE", „HAN") sagen
                // ohne Tabellenkontext wenig. Zwei Zeilen erlaubt, damit
                // „Borussia Mönchengladbach" nicht zu „Borussia M…" wird.
                Expanded(
                  child: Text(
                    fixture.home.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.1,
                    ),
                  ),
                ),
                // Anstoßzeit mittig zwischen beiden Mannschaften.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    anstoss,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    fixture.away.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.1,
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                TeamBadge(team: fixture.away, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// News ganz unten als schmale Querleiste — die dritte Form auf dem Screen
/// (Karten quer, Zeilen längs, Leiste). Früher standen hier fünf Meldungen
/// unter zwei Überschriften und füllten die halbe Seite.
class _NewsSection extends ConsumerWidget {
  const _NewsSection();

  static const _maxTransfers = 6;

  void _openList(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const NewsListScreen(
          topic: 'transfers',
          title: 'News',
          intro:
              'Aktuelle Bundesliga-Schlagzeilen, neueste zuerst. '
              'Tippen öffnet den Artikel.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transfers = ref.watch(newsProvider('transfers'));
    return transfers.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        final shown = items.take(_maxTransfers).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            abschnittsKopf(
              context,
              'News',
              onMore: () => _openList(context),
              marke: _kVereinsBlau,
            ),
            _Bleed(
              hoehe: kartenHoehe(context, 92),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                physics: const BouncingScrollPhysics(),
                itemCount: shown.length + 1,
                separatorBuilder: (_, _) => const SizedBox(width: 9),
                itemBuilder: (_, i) => i < shown.length
                    ? _NewsCard(item: shown[i])
                    : _MoreNewsCard(onTap: () => _openList(context)),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Eine Schlagzeile als schmale Karte der News-Leiste.
class _NewsCard extends StatelessWidget {
  const _NewsCard({required this.item});

  final NewsItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final meta = [
      if (item.source != null) item.source!,
      if (item.publishedAt != null) relativeNewsTime(item.publishedAt!),
    ].join(' · ');
    return SizedBox(
      width: 232,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => openNews(context, item.url),
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.7),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(11, 10, 11, 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    item.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      height: 1.15,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.newspaper, size: 12, color: _kVereinsBlau),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Abschluss der News-Leiste: alles Weitere in der vollen Liste.
class _MoreNewsCard extends StatelessWidget {
  const _MoreNewsCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 96,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.8),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(height: 6),
                Text(
                  'Alle News',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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

/// Einstieg, wenn noch gar keine Liga existiert: schlicht zwei Buttons
/// „Liga erstellen" und „Liga suchen" (ohne Überschrift/Beschreibung).
class _NoLeaguesHero extends ConsumerWidget {
  const _NoLeaguesHero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Zwei Knöpfe nebeneinander gibt es hier nicht, also darf die Schrift
    // weiter mitwachsen als in den Kartenreihen — aber nicht unbegrenzt:
    // „Liga erstellen" steht mit dem Symbol in einer Zeile, die nicht
    // umbricht, und lief bei dreifacher Systemschrift seitlich aus dem Bild.
    // Die Höhen sind Mindesthöhen geworden: 64 fest hieß, dass eine 56 Punkte
    // hohe Zeile Schrift unten abgeschnitten wurde.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.6,
      child: Column(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.add, size: 26),
                label: const Text(
                  'Liga erstellen',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                onPressed: () => showCreateOrJoin(context, ref),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.search),
                label: const Text(
                  'Liga suchen',
                  style: TextStyle(fontSize: 16),
                ),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LeagueSearchScreen()),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Schlanke Kopfzeile: Gruß links, die beiden Direktzugänge rechts.
///
/// Die Begrüßung **tritt zurück**. Sie war zweimal hintereinander das
/// Auffälligste auf dem Schirm: erst als Kasten mit Verlauf über den halben
/// Bildschirmkopf, dann als größte und fetteste Schrift der Seite — und
/// „Hallo, SFV03" trägt keine Information. Jetzt ist sie eine graue Zeile
/// über der Kopfkarte, die den Platz übernommen hat.
///
/// Die beiden Symbole daneben sind aus derselben Überlegung entfärbt: Gold
/// und Grün versprachen etwas Anstehendes, wo nichts anstand. Farbe hat auf
/// diesem Screen nur noch, was gerade läuft oder wartet — beim
/// Nachrichten-Knopf also der rote Zähler, wenn tatsächlich etwas ungelesen
/// ist.
class _GreetingBar extends ConsumerWidget {
  const _GreetingBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(currentUsernameProvider).valueOrNull;
    final unreadCount = ref.watch(unreadDmCountProvider);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        children: [
          // Der Gruß füllt den Platz bis zu den beiden Knöpfen — die bleiben
          // dadurch am rechten Rand. Ein `Spacer` neben einem `Flexible`
          // teilte den freien Platz hälftig: der Name bekam nur die Hälfte
          // und brach bei großer Systemschrift zu „Hallo" / „, S…" um, das
          // Komma führte die zweite Zeile an.
          Expanded(
            child: Text(
              // Zwei Zeilen erlaubt: bei größter Systemschrift blieb von
              // „Hallo, SFV03" in einer Zeile nur „H…" übrig.
              name == null ? 'Willkommen' : 'Hallo, $name',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          // Transfers und Direktnachrichten bleiben als Direktzugänge
          // erhalten — entfärbt, siehe oben.
          _HeaderAction(
            tooltip: 'Transfers',
            icon: Icons.swap_horiz,
            color: scheme.onSurfaceVariant,
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const TransfersScreen())),
          ),
          _HeaderAction(
            tooltip: 'Direktnachrichten',
            icon: Icons.forum_outlined,
            color: scheme.onSurfaceVariant,
            badge: unreadCount,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ConversationsScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kompakter Icon-Knopf der Kopfzeile, optional mit rotem Zähler.
class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onTap,
    this.badge = 0,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    // Knopf und Zähler sind **eine** Ansage. Vorgelesen wurden vorher zwei
    // Stationen: „Direktnachrichten, Schaltfläche" und daneben ein nacktes
    // „3", das nicht sagte, wovon es drei zählt.
    return Semantics(
      button: true,
      label: badge > 0 ? '$tooltip, $badge ungelesen' : tooltip,
      onTap: onTap,
      excludeSemantics: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            tooltip: tooltip,
            onPressed: onTap,
            visualDensity: VisualDensity.compact,
            // Vorher 40 — unter dem Maß beider Plattformen. Die fehlenden
            // Punkte holt sich der Knopf aus dem Luftraum um das Symbol,
            // sichtbar ändert sich nichts.
            constraints: BoxConstraints(
              minWidth: minTastflaeche(context),
              minHeight: minTastflaeche(context),
            ),
            icon: Icon(icon, size: 26, color: color),
          ),
          if (badge > 0)
            Positioned(
              right: 2,
              top: 2,
              child: Container(
                constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: MatchUpColors.red,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.surface,
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Text(
                    badge > 99 ? '99+' : '$badge',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Leerer Tippspiel-Abschnitt als antippbare Zeile statt als Satz: der
/// Hinweis „oben rechts mit +" ließ eine halbe Seite ungenutzt und war
/// obendrein nur eine Wegbeschreibung.
class _CreateRow extends ConsumerWidget {
  const _CreateRow({
    required this.text,
    required this.hint,
    required this.farbe,
  });

  final String text;
  final String hint;

  /// Farbe des Abschnitts, in dem die Zeile steht. Ein Leerzustand ist die
  /// **Einladung** in einen Bereich; als grauer Umriss neben einem grauen
  /// Kopf sah er aus wie etwas Abgeschaltetes. Das „+" trägt jetzt die Farbe
  /// des Bereichs, in den es führt.
  final Color farbe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return _PressScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => showCreateOrJoin(context, ref),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: farbe.withValues(alpha: 0.06),
              border: Border.all(color: farbe.withValues(alpha: 0.30)),
            ),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: farbe.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.add_rounded, size: 20, color: farbe),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        text,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        hint,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
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

/// Fuß einer Liga- oder Tipprunden-Karte: der Zustand sitzt in einer eigenen,
/// abgesetzten Leiste.
///
/// Vorher trennte eine dünne Linie den Zustand vom Rest, und Name samt
/// Untertitel schwebten mit viel totem Raum in der Kartenmitte. Die Leiste
/// gibt der Karte einen Boden: oben Marke und Name, unten der Zustand — was
/// zu tun ist, steht immer an derselben Stelle, auch wenn der Name zwei
/// Zeilen braucht.
///
/// Die Leiste trägt den Ton des **Zustands**, nicht mehr die Farbe der Liga.
/// Die Farbe sagte vorher den Modus an — Redraft oder Dynasty —, und danach
/// sucht auf dem Startbildschirm niemand. Jetzt ist sie das einzige Farbfeld
/// der Karte und sagt, ob etwas ansteht.
class _KartenSockel extends StatelessWidget {
  const _KartenSockel({required this.sockel});

  final _Sockel sockel;

  @override
  Widget build(BuildContext context) {
    // Lädt der Zustand noch, bleibt der Boden leer statt einen Ladepunkt in
    // jede Karte zu setzen — die Höhe steht trotzdem, damit die Reihe beim
    // Nachladen nicht springt.
    final s = sockel;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: s == null
            ? Colors.transparent
            : s.ton.withValues(alpha: s.dringend ? 0.18 : 0.10),
        // 15, nicht 16: innen am 1px-Rahmen entlang, sonst blitzt in den
        // unteren Ecken die Kartenfläche durch.
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(15),
          bottomRight: Radius.circular(15),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(9, 5, 8, 5),
        child: s == null
            ? SizedBox(height: kartenHoehe(context, 26))
            : _StatusZeile(
                label: s.label,
                detail: s.detail,
                ton: s.ton,
                pulsiert: s.pulsiert,
              ),
      ),
    );
  }
}

/// Wie weit die Systemschrift innerhalb der Kartenreihen mitwächst.
///
/// Knapp vier Karten nebeneinander können nicht breiter werden — bei
/// dreifacher Systemschrift stünde auf jeder noch ein halbes Wort. Deshalb
/// ist die Schrift **in den Reihen** bei 1,3 gedeckelt (überall sonst auf dem
/// Screen wächst sie ungebremst weiter: Begrüßung, Kopfkarte, Tippspiel-
/// Zeilen, Vereinszeilen und Leerzustände stehen längs und haben den Platz).
const double _kMaxKartenSkala = 1.3;

/// Die gedeckelte Textskala an dieser Stelle.
TextScaler kartenSkala(BuildContext context) =>
    MediaQuery.textScalerOf(context).clamp(maxScaleFactor: _kMaxKartenSkala);

/// Kartenmaß bei der eingestellten Systemschrift.
///
/// Der Deckel allein genügt nicht: schon bei 1,3 braucht ein zweizeiliger
/// Liganame 38 statt 29 Punkte, und in eine feste 132-Punkte-Karte passte er
/// dann samt Modus und Sockel nicht mehr — Flutter meldete das als
/// „RenderFlex overflowed", auf dem Gerät sah man den Namen abgeschnitten
/// hinter dem Sockel verschwinden. Die Karte wächst also mit der Schrift.
double kartenHoehe(BuildContext context, double basis) =>
    basis * (kartenSkala(context).scale(14) / 14);

/// Höhe der Liga-Karten im Querlauf — auch für den Ladeplatz und die
/// „Neue Liga"-Karte, damit die Reihe nicht springt. Grundmaß bei
/// Standardschrift; auf dem Gerät durch [kartenHoehe] geschickt.
const double _kLeagueCardHeight = 132;

/// Blau der Abschnitte, die nicht mir gehören, sondern dem Fußball: die
/// Spiele meiner Vereine und die News. Grün und Rot sind vergeben (Marke und
/// Modusfarben), Gold gehört dem Tippspiel.
const Color _kVereinsBlau = Color(0xFF5B9DF9);

/// Marken-Gold des Tippspiels (Fallback, wenn die Runde kein Logo hat).
const Color _kTipGold = Color(0xFFFFC83D);

/// Abstand zwischen zwei Karten der Reihe.
const double _kLeagueCardGap = 8;

/// Seitlicher Innenabstand der Reihe (passend zum Seitenrand).
const double _kLeagueRowPad = 12;

/// Fläche einer Kachel: grauer Grund mit einem **Hauch** der eigenen Farbe in
/// der Ecke, in der die Marke sitzt. Der Rahmen färbt sich nur, wenn etwas
/// ansteht.
///
/// Zwei Extreme lagen davor, und beide waren falsch. Zuerst trug jede Karte
/// einen kräftigen Verlauf in ihrer Farbe: vier Farbflächen nebeneinander,
/// die gleich laut riefen und ausgerechnet den Modus ansagten — wonach auf dem
/// Startbildschirm niemand sucht. Dann gar keine: flaches Grau, Farbe nur noch
/// im Sockel. Das nahm der Reihe aber jede Identität, und weil ringsum ohnehin
/// alles dunkelgrau ist, war der halbe Schirm einfarbig und leblos. Wer nichts
/// Dringendes offen hatte, sah vier gleiche Rechtecke.
///
/// Der Hauch ist die Mitte: Er sitzt oben links, wo die Marke ohnehin in
/// derselben Farbe steht, und ist bei drei Vierteln der Diagonale verklungen.
/// Die Karte behält damit ihr Gesicht, ohne dass die Fläche mit dem Sockel um
/// die Aufmerksamkeit streitet — der bleibt das einzige **volle** Farbfeld.
///
/// Gemischt wird gegen den **Seitengrund**, nicht gegen die graue
/// Kartenfläche: 28 % Markengrün über einem blaustichigen Grau ergaben ein
/// stumpfes Salbeigrün — die Farbe sah blass aus, obwohl es dieselbe war.
BoxDecoration _kartenFlaeche(
  BuildContext context,
  _Sockel sockel,
  Color farbe,
) {
  final scheme = Theme.of(context).colorScheme;
  final dark = Theme.of(context).brightness == Brightness.dark;
  final dringend = sockel?.dringend ?? false;
  final grund = Color.alphaBlend(
    scheme.surfaceContainerHighest.withValues(alpha: 0.45),
    scheme.surface,
  );
  return BoxDecoration(
    borderRadius: BorderRadius.circular(16),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      stops: const [0.0, 0.75],
      colors: [
        Color.alphaBlend(farbe.withValues(alpha: dark ? 0.26 : 0.14), grund),
        grund,
      ],
    ),
    border: Border.all(
      color: dringend
          ? sockel!.ton.withValues(alpha: 0.45)
          : farbe.withValues(alpha: dark ? 0.22 : 0.18),
      width: 0.8,
    ),
  );
}

/// Kartenbreite so, dass die vierte Karte am rechten Rand **angeschnitten**
/// wird.
///
/// Vorher passten genau vier hinein. Das war als Ordnung gedacht und las sich
/// als starres Raster: nichts an der Reihe sagte, dass es seitlich
/// weitergeht, und wer eine fünfte Liga hatte, fand sie nicht. Ein Viertel
/// Karte über der Kante sagt es ohne ein Wort. Gerechnet statt fest
/// verdrahtet — auf einem kleinen iPhone wären vier feste 186er nur
/// zweieinhalb.
double leagueCardWidth(BuildContext context) {
  final frei =
      MediaQuery.sizeOf(context).width -
      2 * _kLeagueRowPad -
      3 * _kLeagueCardGap;
  return frei / 3.75;
}

/// Eine Fantasy-Liga als schmale Karte: eigene Farbe, eigener Zustand.
/// Die Farbe kommt deterministisch aus der Liga-ID — aber aus der Palette
/// ihres Modus, damit Redraft (kühl) und Dynasty (warm) auf einen Blick
/// auseinanderzuhalten sind. Vorher trugen alle Ligen dieselbe Marke in nur
/// zwei Typ-Farben und waren dadurch gar nicht zu unterscheiden.
class _FantasyLeagueCard extends ConsumerWidget {
  const _FantasyLeagueCard({required this.league});

  final FantasyLeague league;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final myId = ref.watch(currentUserProvider)?.id;
    final managers = ref.watch(fantasyManagersProvider(league.id)).valueOrNull;
    final status = _draftGeschaerft(
      fantasyStatus(league, teams: managers?.length),
      league,
      managers,
      myId,
    );
    final farbe = parseColor(league.logoColor) ?? leagueColor(league.mode);
    final sockel = _ligaSockel(context, ref, league, status, farbe);

    // Offene Beitrittsanfragen nur für den Admin einer öffentlich–auf-
    // Einladung-Liga (Live über Realtime).
    final showBadge =
        league.isPublic && league.isInviteOnly && myId == league.createdBy;
    final pending = showBadge
        ? (ref
                  .watch(fantasyJoinRequestsProvider(league.id))
                  .valueOrNull
                  ?.length ??
              0)
        : 0;

    return _PressScale(
      child: SizedBox(
        width: leagueCardWidth(context),
        height: kartenHoehe(context, _kLeagueCardHeight),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => FantasyLeagueScreen(league: league),
              ),
            ),
            borderRadius: BorderRadius.circular(16),
            child: Ink(
              decoration: _kartenFlaeche(context, sockel, farbe),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(9, 9, 8, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _LeagueMark(
                                league: league,
                                farbe: farbe,
                                size: 30,
                              ),
                              const Spacer(),
                              if (pending > 0) _CountBadge(count: pending),
                            ],
                          ),
                          // Der Zwischenraum liegt **über** dem Namen: so
                          // sitzt der Text am Sockel statt in der Mitte zu
                          // schweben, und eine zweite Namenszeile wächst nach
                          // oben in den freien Platz.
                          const Spacer(),
                          Flexible(
                            child: Text(
                              league.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                height: 1.05,
                              ),
                            ),
                          ),
                          // Modus als Wort, weil die Marke allein nur die
                          // Farbfamilie verrät, nicht den Namen. Leiser als
                          // der Name — sonst sind beide Zeilen gleich laut.
                          Text(
                            league.mode.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurface.withValues(alpha: 0.78),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 7),
                        ],
                      ),
                    ),
                  ),
                  _KartenSockel(sockel: sockel),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Schärft den Draft-Zustand für die Karte nach: **wer** dran ist und **bis
/// wann**. Beides steht nicht in [fantasyStatus] — die Logik dort kennt nur
/// die Liga, nicht den angemeldeten Nutzer, und soll ohne Uhrzeit-Format
/// auskommen.
LeagueStatus _draftGeschaerft(
  LeagueStatus status,
  FantasyLeague league,
  List<FantasyManager>? managers,
  String? myId,
) {
  if (league.draftStatus != DraftStatus.drafting) return status;
  final dran = managers == null
      ? null
      : currentManager(managers, league.picksMade)?.userId;
  final frist = league.currentPickDeadline?.toLocal();
  return LeagueStatus(
    dran != null && dran == myId ? 'Du bist dran' : status.label,
    detail: [
      if (status.detail != null) status.detail!,
      if (frist != null) kurzeFrist(frist, DateTime.now()),
    ].join(' · '),
    tone: status.tone,
  );
}

/// Liga-Zeichen: eigenes Logo, sonst die MatchUp-Marke in der Liga-Farbe.
class _LeagueMark extends StatelessWidget {
  const _LeagueMark({
    required this.league,
    required this.farbe,
    required this.size,
  });

  final FantasyLeague league;
  final Color farbe;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hasCustom =
        (league.logoUrl != null && league.logoUrl!.isNotEmpty) ||
        (league.logoEmoji != null && league.logoEmoji!.isNotEmpty);
    if (hasCustom) {
      return AppAvatar(
        imageUrl: league.logoUrl,
        emoji: league.logoEmoji,
        colorHex: league.logoColor,
        fallbackIcon: Icons.shield_outlined,
        size: size,
        cornerRadius: 10,
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: farbe,
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: MatchUpChevron(size: size * 0.5, color: MatchUpColors.base),
    );
  }
}

/// Fußzeile der Liga-Karte. Läuft ein Draft, gewinnt der — seine Uhr tickt in
/// Minuten. Sonst zeigt die Karte, was im **ligainternen Tippspiel** offen
/// ist: dessen Runde taucht im Tippspiel-Abschnitt bewusst nicht auf (man
/// erreicht sie über die Liga), ihre offenen Tipps hätten sonst nirgends
/// mehr Platz. Ist auch dort nichts offen, bleibt es beim Liga-Zustand.
/// Was im Sockel einer Karte steht — **und in welchem Ton**.
///
/// Als Wert statt als Widget, weil die Karte den Ton selbst braucht: Seit die
/// Karten flach sind, ist der Sockel die einzige Farbe darauf, und ein
/// dringender Zustand färbt zusätzlich den Rahmen. Solange die Zustandszeile
/// ihre Farbe erst beim Bauen kannte, kam sie beim Rahmen nie an.
typedef _Sockel = ({
  String label,
  String? detail,
  Color ton,
  bool pulsiert,

  /// Hier ist etwas **zu tun** — nicht nur etwas zu vermelden. Nur das färbt
  /// den Kartenrahmen; ein Tabellenplatz ist eine Auskunft, kein Auftrag.
  bool dringend,
})?;

/// Sockel einer Liga-Karte. Läuft ein Draft, gewinnt der — seine Uhr tickt in
/// Minuten. Sonst zeigt die Karte, was im **ligainternen Tippspiel** offen
/// ist: dessen Runde taucht im Tippspiel-Abschnitt bewusst nicht auf (man
/// erreicht sie über die Liga), ihre offenen Tipps hätten sonst nirgends mehr
/// Platz. Ist auch dort nichts offen, bleibt es beim Liga-Zustand.
_Sockel _ligaSockel(
  BuildContext context,
  WidgetRef ref,
  FantasyLeague league,
  LeagueStatus status,
  Color farbe,
) {
  _Sockel ausZustand() {
    final scheme = Theme.of(context).colorScheme;
    final ton = switch (status.tone) {
      LeagueStatusTone.wartet => scheme.onSurfaceVariant,
      LeagueStatusTone.laeuft => MatchUpColors.green,
      LeagueStatusTone.bereit => farbe,
    };
    return (
      label: status.label,
      detail: status.detail,
      ton: ton,
      // Der laufende Draft ist das einzige, was wirklich tickt.
      pulsiert: status.tone == LeagueStatusTone.laeuft,
      dringend: status.tone == LeagueStatusTone.laeuft,
    );
  }

  if (league.draftStatus == DraftStatus.drafting) return ausZustand();
  // Läuft die Saison, ist der Tabellenplatz die Auskunft, die zählt —
  // „Kader steht" sagt dann nichts mehr. Vor dem ersten gewerteten
  // Spieltag gibt es keinen Platz; dann bleibt es beim Zustand.
  final platz = ref.watch(myFantasyRankProvider(league.id));
  if (platz != null) {
    return (
      label: 'Platz ${platz.rank}',
      detail: 'von ${platz.total}',
      ton: platz.rank == 1 ? _kTipGold : MatchUpColors.green,
      pulsiert: false,
      dringend: false,
    );
  }
  final runde = ref.watch(fantasyTipRoundProvider(league.id)).valueOrNull;
  if (runde == null) return ausZustand();
  final offen = ref.watch(offeneTippsProvider(runde.id)).valueOrNull;
  if (offen == null || offen.anzahl == 0) return ausZustand();
  final frist = offen.frist;
  return (
    label: offen.anzahl == 1 ? '1 Tipp offen' : '${offen.anzahl} Tipps offen',
    detail: frist == null ? null : kurzeFrist(frist, DateTime.now()),
    ton: _kTipGold,
    pulsiert:
        frist != null &&
        frist.difference(DateTime.now()) < const Duration(hours: 1),
    dringend: true,
  );
}

/// Sockel einer Tipprunden-Karte. Lädt still nach — solange nichts feststeht,
/// bleibt der Sockel leer, statt einen Ladepunkt in jede Karte zu setzen.
_Sockel _tippSockel(BuildContext context, WidgetRef ref, String roundId) {
  final scheme = Theme.of(context).colorScheme;
  final offen = ref.watch(offeneTippsProvider(roundId)).valueOrNull;
  if (offen == null) return null;
  if (offen.anzahl == 0) {
    return (
      label: 'Alles getippt',
      detail: null,
      ton: scheme.onSurfaceVariant,
      pulsiert: false,
      dringend: false,
    );
  }
  final frist = offen.frist;
  return (
    label: offen.anzahl == 1 ? '1 Tipp offen' : '${offen.anzahl} Tipps offen',
    detail: frist == null ? null : kurzeFrist(frist, DateTime.now()),
    ton: _kTipGold,
    // Es drängt: das nächste Spiel stößt in unter einer Stunde an.
    pulsiert:
        frist != null &&
        frist.difference(DateTime.now()) < const Duration(hours: 1),
    dringend: true,
  );
}

/// Fußzeile beider Kartensorten: farbiger Punkt, kurzes Wort, leise
/// Zusatzzeile. Texte schrumpfen im Zweifel, statt zu kappen — auf einer
/// Karte, von der vier nebeneinander passen, sagt „Kader ste…" nichts.
class _StatusZeile extends StatelessWidget {
  const _StatusZeile({
    required this.label,
    required this.detail,
    required this.ton,
    required this.pulsiert,
  });

  final String label;
  final String? detail;
  final Color ton;
  final bool pulsiert;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (pulsiert)
              PulsingDot(size: 7, color: ton)
            else
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: ton, shape: BoxShape.circle),
              ),
            const SizedBox(width: 6),
            // Den Ton trägt der Punkt, nicht die Schrift: auf der farbigen
            // Karte wäre farbige Schrift schlecht zu lesen.
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (detail != null)
          Padding(
            padding: const EdgeInsets.only(left: 13, top: 1),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                detail!,
                maxLines: 1,
                style: TextStyle(
                  color: scheme.onSurface.withValues(alpha: 0.82),
                  fontSize: 11,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Eine Tipprunde als **Zeile**, nicht als Karte.
///
/// Die Runden standen bis hierher in derselben quer zu wischenden Kartenreihe
/// wie die Ligen darüber — zwei gleich gebaute Reihen untereinander, nur die
/// zweite etwas flacher. Als Zeile bekommt der Abschnitt eine eigene Form und
/// der Name den Platz, den eine 95 Punkte breite Karte ihm nie geben konnte:
/// „Xcode Xcode" musste dort auf zwei Zeilen, hier steht es einmal quer.
///
/// Und weil die Zeile längs läuft, gilt hier der Schrift-Deckel der Reihen
/// nicht: sie darf mit der Systemschrift wachsen, sie hat den Platz.
class _TipRoundRow extends ConsumerWidget {
  const _TipRoundRow({required this.round});

  final TipRound round;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final league = Leagues.byId(round.leagueId);
    // Mehrere Wettbewerbe → „Bundesliga +2".
    final extra = round.competitions.length - 1;
    final wettbewerb = extra > 0 ? '${league.name} +$extra' : league.name;
    final farbe = parseColor(round.logoColor) ?? _kTipGold;
    final sockel = _tippSockel(context, ref, round.id);

    final myId = ref.watch(currentUserProvider)?.id;
    final showBadge =
        round.isPublic && round.isInviteOnly && myId == round.createdBy;
    final pending = showBadge
        ? (ref.watch(tipJoinRequestsProvider(round.id)).valueOrNull?.length ??
              0)
        : 0;

    // Wettbewerb und Frist stehen in einer Zeile unter dem Namen: beides ist
    // Beiwerk zur selben Runde, und zwei eigene Zeilen dafür machten die
    // Reihe dreizeilig.
    final unterzeile = [
      wettbewerb,
      if (sockel != null && sockel.detail != null) sockel.detail!,
    ].join(' · ');

    void oeffnen() {
      activateRound(ref, round);
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => LeagueScreen(round: round)));
    }

    return Semantics(
      button: true,
      // Eine Ansage für die ganze Zeile. Einzeln vorgelesen wären es vier
      // Stationen, darunter ein nacktes „18 offen".
      label: [
        round.name,
        unterzeile,
        if (sockel != null) sockel.label,
        if (pending == 1)
          '1 offene Beitrittsanfrage'
        else if (pending > 1)
          '$pending offene Beitrittsanfragen',
      ].join(', '),
      onTap: oeffnen,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: oeffnen,
          child: Container(
            constraints: BoxConstraints(minHeight: minTastflaeche(context)),
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
            child: Row(
              children: [
                _RoundMark(round: round, farbe: farbe, size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        round.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                        ),
                      ),
                      Text(
                        unterzeile,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (pending > 0) ...[
                  const SizedBox(width: 8),
                  _CountBadge(count: pending),
                ],
                if (sockel != null) ...[
                  const SizedBox(width: 8),
                  _OffenPille(sockel: sockel),
                ],
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Was an einer Tipprunde offen ist, am rechten Rand ihrer Zeile.
///
/// Nur was drängt bekommt die goldene Fläche; „Alles getippt" steht als
/// leiser Text ohne Kasten da. Ein Kasten für jeden Zustand hieße vier
/// gleich laute Pillen untereinander, und dann sagt keine mehr etwas.
class _OffenPille extends StatelessWidget {
  const _OffenPille({required this.sockel});

  final _Sockel sockel;

  @override
  Widget build(BuildContext context) {
    final s = sockel!;
    final text = Text(
      s.label,
      maxLines: 1,
      style: TextStyle(
        color: s.ton,
        fontSize: 13,
        fontWeight: s.dringend ? FontWeight.w700 : FontWeight.w500,
      ),
    );
    if (!s.dringend) return text;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (s.pulsiert) ...[
          PulsingDot(size: 6, color: s.ton),
          const SizedBox(width: 5),
        ],
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: s.ton.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(8),
          ),
          child: text,
        ),
      ],
    );
  }
}

/// Zeichen einer Tipprunde: eigenes Logo, sonst die MatchUp-Marke in Gold.
class _RoundMark extends StatelessWidget {
  const _RoundMark({
    required this.round,
    required this.farbe,
    required this.size,
  });

  final TipRound round;
  final Color farbe;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hasCustom =
        (round.logoUrl != null && round.logoUrl!.isNotEmpty) ||
        (round.logoEmoji != null && round.logoEmoji!.isNotEmpty);
    if (hasCustom) {
      return AppAvatar(
        imageUrl: round.logoUrl,
        emoji: round.logoEmoji,
        colorHex: round.logoColor,
        fallbackIcon: Icons.emoji_events_outlined,
        size: size,
        cornerRadius: 8,
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: farbe,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: MatchUpChevron(size: size * 0.5, color: MatchUpColors.base),
    );
  }
}

/// Kleiner roter Zähler für offene Beitrittsanfragen (Home-Liga-Karte).
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: count == 1
          ? '1 offene Beitrittsanfrage'
          : '$count offene Beitrittsanfragen',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minWidth: 20),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: scheme.error,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Text(
          '$count',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: scheme.onError,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

/// Lässt eine Querleiste über den Seitenrand hinauslaufen: der Seiten-
/// ListView hat 12 px Innenabstand, eine Kachelreihe soll aber bis an die
/// Bildschirmkante reichen, damit die angeschnittene Karte zeigt, dass es
/// weitergeht.
///
/// Hier sitzt zugleich der Deckel für die Systemschrift ([_kMaxKartenSkala]):
/// alles, was quer gewischt wird, steht in einer festen Kartenbreite und kann
/// nicht beliebig mitwachsen. Wer die Höhe setzt, rechnet sie mit
/// [kartenHoehe] aus derselben Skala aus.
class _Bleed extends StatelessWidget {
  const _Bleed({required this.hoehe, required this.child});

  final double hoehe;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final breite = MediaQuery.sizeOf(context).width;
    return SizedBox(
      height: hoehe,
      child: OverflowBox(
        minWidth: breite,
        maxWidth: breite,
        alignment: Alignment.center,
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: _kMaxKartenSkala,
          child: child,
        ),
      ),
    );
  }
}

/// Einmalige Einblend-Animation (Fade + leichtes Hochgleiten) beim Erscheinen;
/// mit [delayMs] gestaffelt für einen lebendigen Aufbau des Screens.
class _Appear extends StatefulWidget {
  const _Appear({required this.child, this.delayMs = 0});

  final Widget child;
  final int delayMs;

  @override
  State<_Appear> createState() => _AppearState();
}

class _AppearState extends State<_Appear> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOutCubic,
  );
  bool _gestartet = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_gestartet) return;
    _gestartet = true;
    // „Bewegung reduzieren" heißt nicht „nichts anzeigen": der Inhalt steht
    // dann sofort da, nur ohne Einblenden und Hochgleiten. Gestaffelt baute
    // sich der Screen sonst häppchenweise vor jemandem auf, der Bewegung
    // ausdrücklich abbestellt hat — und wer sie aus Reisekrankheit abstellt,
    // wird von 220 ms Verzögerung nicht verschont.
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
      return;
    }
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (context, child) => Opacity(
        opacity: _t.value,
        child: Transform.translate(
          offset: Offset(0, (1 - _t.value) * 14),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Drückt sein Kind beim Antippen leicht zusammen (taktiles Feedback).
class _PressScale extends StatefulWidget {
  const _PressScale({required this.child, this.eineAnsage = true});

  final Widget child;

  /// Ob das Gedrückte auch **eine** Ansage ist. Für die Kartenreihen ja; die
  /// Kopfkarte setzt es ab, weil in ihr zwei Knöpfe mit zwei Zielen stecken —
  /// das Spiel und der Sockel, der in die Tipprunde führt. Zusammengelegt
  /// bliebe von den beiden Wegen nur einer vorlesbar.
  final bool eineAnsage;

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    // Listener beobachtet nur (verbraucht die Geste nicht) → InkWell-Ripple
    // und onTap des Kindes bleiben erhalten.
    return Listener(
      onPointerDown: (_) => setState(() => _down = true),
      onPointerUp: (_) => setState(() => _down = false),
      onPointerCancel: (_) => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        // Was als Ganzes gedrückt wird, wird auch als Ganzes vorgelesen.
        // Eine Liga-Karte war für die Vorlesehilfe sonst vier Stationen —
        // Marke, Name, Modus, Zustand —, durch die einzeln gewischt wird:
        // bei vier Ligen sechzehn Halte für vier Knöpfe.
        child: widget.eineAnsage
            ? MergeSemantics(child: widget.child)
            : widget.child,
      ),
    );
  }
}

/// Meldung an der Stelle, an der sonst Inhalt stünde.
///
/// Hier stand einmal „Fantasy-Ligen konnten nicht geladen werden:
/// PostgrestException(message: …, code: 500)" — ein Satz, der zwei Dinge
/// vermischte: eine Auskunft für den Nutzer und eine für den Entwickler. Der
/// Nutzer las die Hälfte nicht und erfuhr nicht, was er tun kann; der
/// Beta-Tester brauchte die zweite Hälfte aber. Jetzt drei Ebenen: was ist,
/// was man tun kann, und — leiser — woran es lag.
class _InfoCard extends StatelessWidget {
  const _InfoCard(this.text, {this.hinweis, this.technisch});

  final String text;

  /// Der Weg nach vorn. Ohne ihn ist eine Fehlermeldung eine Sackgasse.
  final String? hinweis;

  /// Der Rohtext des Fehlers — für den Beta-Test, nicht für den Nutzer.
  final String? technisch;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
            if (hinweis != null) ...[
              const SizedBox(height: 4),
              Text(hinweis!, style: TextStyle(color: scheme.onSurfaceVariant)),
            ],
            if (technisch != null) ...[
              const SizedBox(height: 10),
              Text(
                technisch!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// MatchUp-Wortmarke für die Kopfzeile: zweifarbiger Doppel-Chevron
// (links Green, rechts Red) + „Match"/„Up". Nativ nachgebaut nach dem
// Marken-SVG (assets/branding/matchup_logo_primary.svg), weil flutter_svg
// dessen Text-Element nicht rendert.
// ---------------------------------------------------------------------
class _MatchUpTitle extends StatelessWidget {
  const _MatchUpTitle();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const MatchUpChevron(size: 22),
        const SizedBox(width: 8),
        Text.rich(
          TextSpan(
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: MatchUpColors.snow,
            ),
            children: const [
              TextSpan(text: 'Match'),
              TextSpan(
                text: 'Up',
                style: TextStyle(color: MatchUpColors.green),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// Erstellen / Beitreten
// ---------------------------------------------------------------------

/// Fullscreen-Auswahl für den Erstellen-Knopf: zwei große farbige Felder
/// **Fantasy** und **Tippspiel**, darunter klein **Beitreten**. Der Screen gibt
/// nur die Wahl zurück; den jeweiligen Flow startet danach der Aufrufer.
void showCreateOrJoin(BuildContext context, WidgetRef ref) async {
  final choice = await Navigator.of(context).push<String>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const _CreateOrJoinScreen(),
    ),
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case 'fantasy':
      createFantasyLeagueFlow(context, FantasyMode.liga);
    case 'tip':
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const CreateTipRoundScreen()));
    case 'join':
      joinAnyFlow(context, ref);
  }
}

/// Auswahl beim „+": Fantasy-Liga, Tippspiel oder einer bestehenden Runde
/// beitreten. Gibt `'fantasy'`, `'tip'` bzw. `'join'` zurück.
///
/// Der Schirm hatte zwei bildschirmfüllende Bilder mit je einem Wort darauf —
/// hübsch, aber er beantwortete die eine Frage nicht, die hier ansteht:
/// **was ist der Unterschied?** Jede Karte sagt das jetzt in einer Zeile, und
/// die Höhen stehen fest, statt sich über den ganzen Schirm zu ziehen.
class _CreateOrJoinScreen extends StatelessWidget {
  const _CreateOrJoinScreen();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Neu starten'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Schließen',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Text(
              'Was möchtest du spielen?',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'Beides geht mit denselben Freunden — und beides kannst du '
              'mehrfach haben.',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 18),
            _StartKarte(
              farbe: MatchUpColors.green,
              bild: 'assets/images/fantasy_bg.jpg',
              titel: 'Fantasy',
              zeile: 'Spieler draften, Kader managen, Woche für Woche punkten',
              onTap: () => Navigator.of(context).pop('fantasy'),
            ),
            const SizedBox(height: 12),
            _StartKarte(
              farbe: _kTipGold,
              bild: 'assets/images/tippspiel_bg.jpg',
              titel: 'Tippspiel',
              zeile: 'Ergebnisse tippen, Punkte sammeln, Tabelle klettern',
              onTap: () => Navigator.of(context).pop('tip'),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: Divider(
                    color: scheme.outlineVariant.withValues(alpha: 0.7),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'ODER',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                Expanded(
                  child: Divider(
                    color: scheme.outlineVariant.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _BeitretenKarte(onTap: () => Navigator.of(context).pop('join')),
          ],
        ),
      ),
    );
  }
}

/// Eine der beiden Startkarten. Feste Höhe statt `Expanded`: auf einem großen
/// Gerät wuchsen die alten Felder ins Riesenhafte, auf einem kleinen drückten
/// sie den „Beitreten"-Weg aus dem Bild.
class _StartKarte extends StatelessWidget {
  const _StartKarte({
    required this.farbe,
    required this.bild,
    required this.titel,
    required this.zeile,
    required this.onTap,
  });

  final Color farbe;
  final String bild;
  final String titel;
  final String zeile;
  final VoidCallback onTap;

  static const _hoehe = 168.0;
  static final _radius = BorderRadius.circular(20);

  @override
  Widget build(BuildContext context) {
    // Die Karte trägt ein Bild in festem Format und kann nicht beliebig
    // wachsen, ohne den „Beitreten"-Weg wieder aus dem Bild zu drücken —
    // genau das, wogegen die feste Höhe einmal gesetzt wurde. Also
    // derselbe Deckel wie in den Kartenreihen, und innerhalb dessen
    // wächst die Höhe mit: bei 1,3 braucht allein „Fantasy" 44 statt 34
    // Punkte, und die Unterzeile darunter zwei Zeilen statt einer.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: _kMaxKartenSkala,
      child: _PressScale(
        child: SizedBox(
          height: kartenHoehe(context, _hoehe),
          child: Container(
            // Rahmen im Vordergrund → liegt ohne Naht über Bild und Ripple.
            foregroundDecoration: BoxDecoration(
              borderRadius: _radius,
              border: Border.all(
                color: farbe.withValues(alpha: 0.65),
                width: 1.5,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              clipBehavior: Clip.antiAlias,
              borderRadius: _radius,
              child: Ink.image(
                image: AssetImage(bild),
                fit: BoxFit.cover,
                child: InkWell(
                  onTap: onTap,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Senkrechter Verlauf: oben nur ein Farbschleier, damit
                      // das Bild sichtbar bleibt, unten fast deckend. Schräg
                      // gelegt lag die Unterzeile teils auf hellem Rasen und
                      // war schlecht zu lesen.
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              farbe.withValues(alpha: 0.16),
                              MatchUpColors.base.withValues(alpha: 0.55),
                              MatchUpColors.base.withValues(alpha: 0.96),
                            ],
                            stops: const [0.0, 0.45, 1.0],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: farbe,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: MatchUpChevron(
                                size: 18,
                                color: MatchUpColors.base,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              titel,
                              style: const TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: -0.5,
                                height: 1.0,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    zeile,
                                    maxLines: 2,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.82,
                                      ),
                                      fontSize: 13,
                                      height: 1.2,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 20,
                                  color: farbe,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Der dritte Weg: einer bestehenden Runde beitreten. Bewusst ruhiger als die
/// beiden Startkarten — wer einen Code hat, sucht ihn gezielt.
class _BeitretenKarte extends StatelessWidget {
  const _BeitretenKarte({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _PressScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.9),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.vpn_key_outlined,
                  size: 22,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Einer Runde beitreten',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Mit dem Einladungscode von Freunden',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
