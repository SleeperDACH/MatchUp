import 'farben.dart';
import 'package:flutter/material.dart';
import '../core/logic/vereins_kuerzel.dart';
import 'widgets/skelett.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/config/app_config.dart';
import '../core/models/models.dart';
import '../core/models/team_fixture.dart';
import '../core/util/club_colors.dart';
import '../core/ui/app_avatar.dart';
import '../features/auth/providers.dart';
import '../features/friends/providers.dart' show incomingRequestsProvider;
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
import '../features/news/ui/news_bild.dart';
import '../features/news/ui/transfers_screen.dart';
import '../features/news/ui/news_list_screen.dart';
import '../features/news/ui/news_tile.dart';
import '../features/tippspiel/models/tip_round.dart';
import '../features/tippspiel/providers.dart';
import '../features/tippspiel/ui/create_tip_round.dart';
import '../features/tippspiel/ui/team_badge.dart';
import 'home_favorit_wahl.dart';
import 'home_favorites.dart';
import 'profile_screen.dart';
import 'widgets/ganze_woerter.dart';
import 'league_screen.dart';
import 'match_detail_screen.dart';
import 'theme.dart';
import 'typografie.dart';
import 'widgets/karte.dart';
import 'widgets/league_logo.dart';
import 'widgets/matchup_chevron.dart';
import 'widgets/pulsing_dot.dart';
import '../features/favorites/logic/next_favorite_fixtures.dart';

/// Startbildschirm. Fantasy ist der Hauptfokus und steht oben; das
/// Tippspiel folgt als zweiter Bereich darunter.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final configured = AppConfig.isSupabaseConfigured;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        // **Kein Seitenmenü mehr** (Design-Ideen Punkt 5, 15.10.2026). Es
        // war die dritte Navigationsebene neben unterer Leiste und
        // Liga-Reitern. Oben links steht jetzt das eigene Profilbild und führt
        // ins Profil; Freunde, Nachrichten und Rechtliches stehen dort.
        leading: (configured && user != null) ? const _ProfilKnopf() : null,
        title: const _MatchUpTitle(),
        // **Nachrichten oben rechts** (18.10.2026), gegenüber dem
        // Profilbild — die Sprechblase mit Zähler kennt man aus jeder App.
        // Die übrigen drei Wege stehen jetzt bei ihrem Abschnitt (Suchen und
        // Neu bei „Meine Ligen", Transfers bei den News), beschriftet.
        actions: [
          if (configured && user != null) const _NachrichtenKnopf(),
          const SizedBox(width: 4),
        ],
        // **Keine Aktionen mehr in der Kopfleiste.** Suchen und Erstellen
        // standen dort als nackte Symbole, Transfers und Nachrichten eine
        // Zeile tiefer als zwei weitere — vier Knöpfe an zwei Orten, keiner
        // mit einem Wort daran. Sie stehen jetzt zusammen und beschriftet
        // unter dem Gruß (`_Schnellzugriff`).
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
              // Die Kopfkarte führt: das nächste Spiel des eigenen Vereins
              // ist der Inhalt, an dem eine Zeit hängt. Sie blendet sich
              // aus, wenn es keinen Favoriten gibt.
              // Ohne Favoriten steht an der Stelle der Kopfkarte die
              // Auswahl — sie verschwindet mit dem ersten gewählten Verein.
              const _Appear(delayMs: 40, child: FavoritWahl()),
              const _Appear(delayMs: 40, child: _NaechstesSpiel()),
              const SizedBox(height: 18),
              // Noch gar keine Liga (Fantasy + Tippspiel beide leer geladen):
              // statt zweier leerer Abschnitte ein großer Einstieg.
              if (_beideLeer(ref)) ...[
                const _Appear(delayMs: 80, child: _NoLeaguesHero()),
                const SizedBox(height: 18),
              ]
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
              // **Getrennt von den eigenen Ligen** (auf Ansage): Die Tippliga
              // gehört allen, nicht einem selbst — eigener kleiner Abschnitt.
              const _Appear(delayMs: 160, child: _FuerAlle()),
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
      // Die Tippliga steht getrennt im Abschnitt „Für alle".
      ?.where((r) => !r.isFantasyLinked && !r.istGlobal)
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
        aktionen: [
          (
            'Suchen',
            'Ligen entdecken',
            () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LeagueSearchScreen()),
            ),
          ),
          (
            'Neu',
            'Liga erstellen oder beitreten',
            () => showCreateOrJoin(context, ref),
          ),
        ],
      ),
      // **Der Fehler ersetzt die Reihe nur, wenn es nichts zu zeigen gibt.**
      // `myFantasyLeaguesProvider` ist ein Realtime-Stream: Reißt die
      // Verbindung ab, meldet er einen Fehler und liefert den letzten Stand
      // trotzdem mit. Auf `hasError` allein zu schauen hieß, die Ligakarten
      // gegen eine Fehlerkarte zu tauschen, obwohl sie vollständig dalagen —
      // derselbe Fehler wie im MatchUp-Tab, gemeldet am 05.09.2026.
      if (leagues.hasError && list == null)
        _InfoCard(
          'Deine Ligen ließen sich nicht laden.',
          hinweis:
              'Zieh den Screen nach unten, um es noch einmal zu '
              'versuchen.',
          technisch: '${leagues.error}',
        )
      else if (list == null)
        SizedBox(
          height: kartenHoehe(context, _kKartenHoehe),
          child: const Skelett(),
        )
      else if (list.isEmpty)
        // Wer noch keine Liga hat, braucht den Einstieg — sonst stünde hier
        // eine leere Überschrift. Als Zeile statt als Karte: so nimmt er ein
        // Sechstel des Platzes und sagt nebenbei, wozu das gut ist.
        _CreateRow(
          text: 'Fantasy-Liga anlegen',
          hint: 'Draften, Kader managen, Saison spielen',
          farbe: context.farben.gruen,
        )
      else
        // Hier hängt **keine** „+"-Karte mehr hinter den Ligen. Sie stand die
        // ganze Saison in der Reihe für etwas, das man ein- oder zweimal im
        // Jahr tut, und war bei vier Ligen die angeschnittene fünfte Karte am
        // rechten Rand — genau die Stelle, an der man eine weitere Liga
        // vermutet. Angelegt wird über das „+" oben rechts; wer noch gar keine
        // Liga hat, sieht statt der Reihe die `_CreateRow`.
        _Bleed(
          hoehe: kartenHoehe(context, _kKartenHoehe),
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
  // Tippspiel: dieselbe Kartenreihe wie die Ligen darüber, nur flacher — es
  // ist der zweite Bereich, nicht der Hauptbereich. Zwischendurch waren es
  // Zeilen (andere Form, mehr Platz für den Namen); zurückgedreht auf
  // ausdrücklichen Wunsch. Was die beiden Reihen unterscheidet, sind jetzt
  // Höhe, Marke und Farbe, nicht die Form.
  // ------------------------------------------------------------------
  List<Widget> _tippspielSection(BuildContext context, WidgetRef ref) {
    final rounds = ref.watch(myRoundsProvider);
    final standalone = _standaloneRounds(ref);
    return [
      abschnittsKopf(context, 'Tippspiel', count: standalone?.length),
      // Dieselbe Regel wie bei den Ligen darüber: erst wenn nichts da ist.
      if (rounds.hasError && standalone == null)
        _InfoCard(
          'Deine Tipprunden ließen sich nicht laden.',
          hinweis:
              'Zieh den Screen nach unten, um es noch einmal zu '
              'versuchen.',
          technisch: '${rounds.error}',
        )
      else if (standalone == null)
        SizedBox(
          height: kartenHoehe(context, _kKartenHoehe),
          child: const Skelett(),
        )
      else if (standalone.isEmpty)
        _CreateRow(
          text: 'Tippspiel anlegen',
          hint: 'Spieltage tippen, Punkte sammeln',
          farbe: context.farben.gold,
        )
      else
        // **Streifen statt Karten** (auf Ansage, 03.09.2026). Die Tipprunden
        // standen zwischendurch schon einmal als Zeilen da und wurden auf
        // Wunsch zu Karten zurückgedreht; der Grund, der damals dagegen
        // sprach, gilt für **gleich gebaute** Reihen: Zwei Kartenreihen
        // untereinander lassen den halben Schirm gleich aussehen. Genau das
        // löst der Streifen — die Ligen bleiben Karten, das Tippspiel wird
        // eine Zeile, und die beiden Bereiche sind auf einen Blick
        // auseinanderzuhalten.
        //
        // **Eine Gruppe statt gestapelter Balken** (18.10.2026): Jeder
        // Streifen trug seine eigene goldene Fläche, zwei Runden ergaben zwei
        // gleich laute Goldbalken. Jetzt eine Fläche mit Haarlinien — dieselbe
        // Zeilengruppe wie „Mein Team"/„Liga" in der Liga-Übersicht. Das Gold
        // bleibt als Identität im Zeichen der Runde.
        // Volle Breite wie „Mein Wochenende" darunter — eingerückt stand die
        // Gruppe schmaler da als ihr Nachbar.
        //
        // **Seit dem 29.10.2026 je Runde ein eigener Kasten** (auf Ansage:
        // „länglich bleiben, aber in die Richtung Fantasy"). Dieselbe Sprache
        // wie die Ligakarten darüber — Hauch aus der Ecke, Wasserzeichen,
        // Name schräg unten links —, aber über die volle Breite und flacher.
        // Was die beiden Bereiche trennt, sind Form und Farbe: Karten in
        // Grün, Streifen in Gold.
        Column(
          children: [
            for (final (i, r) in standalone.indexed) ...[
              if (i > 0) const SizedBox(height: Abstand.s),
              _TipRoundStreifen(round: r),
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

/// Kopf eines Abschnitts — **dieselbe Kapitelmarke wie in der Liga**
/// (18.10.2026, Homescreen-Überarbeitung): Versalien, Zähler, Haarlinie bis
/// zum Rand, rechts optional ein Zusatz (die Spanne bei „Mein Wochenende")
/// oder ein Link. Der farbige Strich davor ist weg: Er sollte den Bereichen
/// einen Takt geben und war auf der Startseite die letzte Stelle, an der ein
/// Abschnittskopf Farbe trug (Regel 3 der Cleaner-Liste). Den Takt gibt jetzt
/// die Linie, die Farbe tragen die Karten darunter.
///
/// Die Versalien stehen nur im Bild — VoiceOver und TalkBack buchstabierten
/// „NEWS" sonst als N-E-W-S; ausgezeichnet als Überschrift, damit sich der
/// Screen abschnittsweise durchspringen lässt.
Widget abschnittsKopf(
  BuildContext context,
  String titel, {
  int? count,
  String? zusatz,
  String? moreLabel,
  VoidCallback? onMore,
  List<(String wort, String ansage, VoidCallback onTap)> aktionen = const [],
}) {
  final scheme = Theme.of(context).colorScheme;
  // **Bei großer Systemschrift ohne Linie.** Titel, Linie und Zusatz passen
  // dann nicht mehr nebeneinander (bei 3,1-facher Schrift liefen „MEINE
  // VEREINE" und das Datum 237 Punkte über den Rand). Die Linie ist Zierde —
  // sie weicht, und beide Texte dürfen umbrechen.
  final gross = MediaQuery.textScalerOf(context).scale(10) > 15;
  final versalien = TextStyle(
    color: scheme.onSurface,
    fontSize: Schrift.label,
    fontWeight: Schrift.ueberschriftGewicht,
    fontStyle: Schrift.ueberschriftStil,
    letterSpacing: 1.2,
  );
  return Padding(
    padding: EdgeInsets.fromLTRB(4, 0, onMore == null ? 4 : 0, 2),
    child: ConstrainedBox(
      // Mindesthöhe der Plattform: Der Kopf ist zugleich die Tastfläche des
      // Links, und alle Köpfe tragen dasselbe Maß.
      constraints: BoxConstraints(minHeight: minTastflaeche(context)),
      child: Row(
        children: [
          Flexible(
            flex: gross ? 3 : 0,
            fit: FlexFit.loose,
            child: Semantics(
              header: true,
              label: count != null && count > 0 ? '$titel, $count' : titel,
              excludeSemantics: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: Text(titel.toUpperCase(), style: versalien)),
                  if (count != null && count > 0) ...[
                    const SizedBox(width: 6),
                    Text(
                      '$count',
                      style: versalien.copyWith(
                        color: scheme.onSurfaceVariant,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (gross)
            const Spacer()
          else
            Expanded(
              child: Container(
                height: 0.8,
                color: scheme.onSurface.withValues(alpha: 0.12),
              ),
            ),
          if (zusatz != null) ...[
            const SizedBox(width: 10),
            Flexible(
              flex: gross ? 2 : 0,
              fit: FlexFit.loose,
              child: Text(
                zusatz,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: Schrift.label,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          // Wege, die zu diesem Abschnitt gehören — als Wort, ohne Pfeil:
          // Sie führen nicht zu „mehr davon", sondern woandershin.
          for (final (wort, ansage, onTap) in aktionen)
            _MehrLink(label: wort, ansage: ansage, pfeil: false, onTap: onTap),
          if (onMore != null) ...[
            const SizedBox(width: 4),
            _MehrLink(label: moreLabel ?? 'Alle', onTap: onMore),
          ],
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
  const _MehrLink({
    required this.label,
    required this.onTap,
    this.ansage,
    this.pfeil = true,
  });

  final String label;
  final VoidCallback onTap;

  /// Vorlese-Ansage; ohne sie „<label> anzeigen".
  final String? ansage;

  /// „›" hinter dem Wort — nur für „mehr davon" (Alle).
  final bool pfeil;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: ansage ?? '$label anzeigen',
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
            pfeil ? '$label ›' : label,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 14,
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: oeffnen,
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              // **Das Stadion bei Flutlicht liegt hinter der Karte.**
              // **Im hellen Modus dasselbe Bild unter einem weißen Schleier**
              // (29.10.2026, auf Ansage: „soll weiterhin zu sehen sein, nur
              // heller"). Ohne Schleier stünde dunkle Schrift auf einem fast
              // schwarzen Foto; mit ihm bleiben Rasen und Linien als helles
              // Relief, und die Vereinsfarben scheinen leicht durch.
              image: dark
                  ? const DecorationImage(
                      image: AssetImage('assets/images/spiel_bg.jpg'),
                      fit: BoxFit.cover,
                      // **Der untere Rand des Bildes.** In der Mitte ist das
                      // Foto fast schwarz (dunkle Ränge) — dort wäre es
                      // dasselbe wie keins. Unten liegt der beleuchtete Rasen
                      // mit Mittelkreis und Linien, und der ist zu erkennen,
                      // ohne dass er die Karte laut macht.
                      alignment: Alignment.bottomCenter,
                    )
                  // Hell: dieselben Feldlinien als scharfe schwarze Zeichnung
                  // (`spiel_linien.png`, siehe CLAUDE.md „Heller Modus").
                  : const DecorationImage(
                      image: AssetImage('assets/images/spiel_linien.png'),
                      fit: BoxFit.cover,
                      alignment: Alignment.bottomCenter,
                    ),
              // **Die Farben der beiden Vereine**, von links und rechts
              // hereingezogen — aber nur als Andeutung an den Rändern. Seit
              // der Hof hinter den Wappen weg ist, ist das die einzige Stelle,
              // an der sie vorkommen. Über die ganze Karte gezogen war sie
              // falsch: Bayern gegen Stuttgart sind zwei rote Vereine, das
              // ergab eine durchgehend rote Fläche, auf der weder die beiden
              // Seiten auseinanderzuhalten waren noch der goldene Sockel
              // sauber lag. So gehört die Farbe zum Verein, nicht zur Karte.
              // Die Mitte bleibt in jedem Fall neutral — dort steht die
              // Uhrzeit, und die soll nicht auf Farbe liegen.
              //
              // **Über dem Bild deckt sie nicht mehr voll**, sonst wäre das
              // Bild umsonst: an den Rändern 60 %, in der Mitte 30 % — dort
              // steht die Anstoßzeit, und die braucht ruhigen Grund. Das Bild
              // ist ohnehin fast schwarz; mehr Schleier hieße, es gar nicht
              // erst einzubauen.
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  _heroGrund(
                    scheme,
                    dark,
                    tonHeim,
                  ).withValues(alpha: dark ? 0.60 : 1),
                  _heroGrund(
                    scheme,
                    dark,
                    null,
                  ).withValues(alpha: dark ? 0.30 : 1),
                  _heroGrund(
                    scheme,
                    dark,
                    null,
                  ).withValues(alpha: dark ? 0.30 : 1),
                  _heroGrund(
                    scheme,
                    dark,
                    tonAusw,
                  ).withValues(alpha: dark ? 0.60 : 1),
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
                              _Marke(
                                text: 'LIVE',
                                farbe: context.farben.rot,
                                pulsiert: true,
                              )
                            else if (_istHeute(anstoss))
                              _Marke(text: 'HEUTE', farbe: context.farben.gold),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                        child: Row(
                          children: [
                            Expanded(child: _HeroVerein(team: fixture.home)),
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
                                          ? context.farben.rot
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
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(child: _HeroVerein(team: fixture.away)),
                          ],
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

/// Ein Verein der Kopfkarte: Wappen über ausgeschriebenem Namen — und hinter
/// dem Wappen ein weicher Hof in der Trikotfarbe.
///
/// Der Hof ist die Stelle, an der die Vereinsfarbe wirklich hingehört: Er
/// klebt am Verein, nicht an der Karte. Wappen sind klein, vielfarbig und im
/// Test wie bei fehlendem Netz gar nicht da; der Hof trägt die Farbe auch
/// dann. Unbekannte Vereine bekommen keinen — siehe [vereinsTon].
class _HeroVerein extends StatelessWidget {
  const _HeroVerein({required this.team});

  final TeamRef team;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      // **Das Wappen groß und ohne Hof.** Hinter ihm lag ein radialer
      // Schimmer in der Vereinsfarbe; er stammt aus der Zeit, als die Karte
      // eine graue Fläche war und Farbe brauchte. Seit das Stadion dahinter
      // liegt, ist er ein zweiter Lichtkreis auf einem Bild, das schon eins
      // hat — und er nahm dem Wappen die Fläche, die es jetzt bekommt
      // (56 statt 44 Punkte). Die Vereinsfarbe bleibt an den Kartenrändern.
      TeamBadge(team: team, size: 56),
      const SizedBox(height: 3),
      Text(
        // **Ein Wort je Verein** (auf Ansage, 16.10.2026): „Gladbach",
        // „Hamburg", „Schalke" — nicht „Borussia Mönchengladbach". Zwei
        // Zeilen bleiben erlaubt für den seltenen langen Namen.
        vereinsKurzname(team.name),
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

/// Grund der Kopfkarte an einer Stelle: der Seitengrund, leicht angehoben,
/// und — wo ein Verein steht — mit dessen Farbe unterlegt.
Color _heroGrund(ColorScheme scheme, bool dark, Color? verein) {
  final grund = Color.alphaBlend(
    scheme.surfaceContainerHighest.withValues(alpha: dark ? 0.55 : 0.75),
    scheme.surface,
  );
  if (verein == null) return grund;
  return Color.alphaBlend(verein.withValues(alpha: dark ? 0.16 : 0.18), grund);
}

/// Fällt der Anstoß auf den heutigen Tag?
bool _istHeute(DateTime zeit) {
  final jetzt = DateTime.now();
  return zeit.year == jetzt.year &&
      zeit.month == jetzt.month &&
      zeit.day == jetzt.day;
}

/// **Mein Wochenende** — alle Partien der favorisierten Vereine von Freitag
/// bis Montag 15:00, zwischen den eigenen Ligen und den News. Es ist die
/// einzige Stelle auf dem Screen, an der es um Fußball statt um die eigenen
/// Runden geht; deshalb steht sie hinter den Ligen und vor den News.
///
/// Vorher stand hier der **Tag** des nächsten Spiels mit allen Partien darauf.
/// Das war nach dem Abpfiff sofort vorbei: Sonntagabend sprang der Abschnitt
/// auf den nächsten Spieltag, und das Wochenende, über das man gerade redet,
/// war weg. Jetzt bleibt es bis Montag 15:00 stehen — mit Ergebnissen.
///
/// **Vollständig, die Partie der Kopfkarte eingeschlossen.** Sie hier
/// wegzulassen, weil sie oben schon steht, nahm der Liste genau das Spiel, um
/// das es an dem Wochenende geht.
class _FavoritenSpiele extends ConsumerWidget {
  const _FavoritenSpiele();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alle = ref.watch(favoritenSpieleProvider).valueOrNull;
    // **Hier steht das ganze Wochenende, auch das Spiel der Kopfkarte.**
    // Vorher fiel der erste Eintrag heraus, weil er oben schon steht. Das war
    // falsch verstanden: Der Abschnitt soll den Spielplan des Wochenendes
    // zeigen, und dazu gehört die Partie, um die es oben geht. Die Kopfkarte
    // hebt eine davon heraus, sie nimmt sie nicht weg.
    //
    // **Nach Anstoß sortiert.** Der Provider stellt für die Kopfkarte das
    // Spiel des obersten Favoriten nach vorn (`favoritenSpielZuerst`); für
    // eine Liste, die den Verlauf des Wochenendes liest, ist das die falsche
    // Ordnung. Also hier wieder chronologisch.
    //
    // Ohne Favoriten oder solange nichts geladen ist, fällt der Abschnitt weg
    // — eine leere Überschrift wäre schlechter als gar keine.
    if (alle == null || alle.isEmpty) return const SizedBox.shrink();
    final spiele = [...alle]..sort((a, b) => a.kickoff.compareTo(b.kickoff));
    final scheme = Theme.of(context).colorScheme;
    // **Der Zusatz nennt die Spanne, nicht den Tag.** Der Abschnitt läuft über
    // vier Tage; ein einzelnes Datum darüber wäre für drei davon falsch.
    // Englische Woche (Pokal & Co. unter der Woche): eigener Titel, und die
    // Spanne beginnt am ersten Spieltag statt am Montag des Fensters.
    final woche = favoritenFenster(fixtures: spiele, jetzt: DateTime.now());
    final ab = woche.englisch ? spiele.first.kickoff.toLocal() : woche.von;
    // **Der Montag gehört dazu.** `bis` ist Montag 15:00, das Datum davon ist
    // der Montag selbst — einen Tag abzuziehen ließ die Spanne am Sonntag
    // enden und verschwieg genau den Tag, um den es ging.
    final spanne =
        '${DateFormat('d.', 'de_DE').format(ab)} – '
        '${DateFormat('d. MMM', 'de_DE').format(woche.englisch ? spiele.last.kickoff.toLocal() : woche.bis)}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          abschnittsKopf(
            context,
            woche.englisch ? 'Englische Woche' : 'Mein Wochenende',
            zusatz: spanne,
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
    final lokal = fixture.kickoff.toLocal();
    final anstoss = DateFormat('HH:mm', 'de_DE').format(lokal);
    // **Der Wochentag gehört dazu, seit der Abschnitt vier Tage umfasst.**
    // Ein alleinstehendes „15:30" beantwortet über ein Wochenende hinweg
    // nicht, welchen Tag es meint.
    final tag = DateFormat('E', 'de_DE').format(lokal);
    final laeuft = fixture.status == FixtureStatus.live;
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
      label: fixture.hasScore
          ? '${fixture.home.name} gegen ${fixture.away.name}, '
                '$tag, ${fixture.homeScore} zu ${fixture.awayScore}, '
                '${fixture.leagueName}'
          : '${fixture.home.name} gegen ${fixture.away.name}, '
                '$tag $anstoss Uhr, ${fixture.leagueName}',
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
                    vereinsKurzname(fixture.home.name),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.1,
                    ),
                  ),
                ),
                // Mittig zwischen beiden Mannschaften: der Tag über der
                // Zeit — und sobald gespielt wird, das Ergebnis an ihrer
                // Stelle. Rot heißt in dieser App „läuft gerade".
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        tag,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                          fontSize: Schrift.label,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                        ),
                      ),
                      Text(
                        fixture.hasScore
                            ? '${fixture.homeScore}:${fixture.awayScore}'
                            : anstoss,
                        style: TextStyle(
                          color: laeuft
                              ? context.farben.rot
                              : scheme.onSurfaceVariant,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Text(
                    vereinsKurzname(fixture.away.name),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 14,
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

  /// **Fünf Meldungen, untereinander.** Die Leiste lief vorher quer, und was
  /// rechts außerhalb lag, sah niemand — auf einem Schirm, den man ohnehin
  /// nach unten liest, war das eine zweite Leserichtung für nichts.
  static const _maxTransfers = 5;

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
    final transfers = ref.watch(newsProvider(homeNewsThema));
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
              // Die echten Wechsel der Bundesliga gehören zu den News, nicht
              // in eine Symbolreihe über dem Schirm.
              aktionen: [
                (
                  'Transfers',
                  'Transfers anzeigen',
                  () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TransfersScreen()),
                  ),
                ),
              ],
              onMore: () => _openList(context),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
              child: Column(
                children: [
                  for (final n in shown) ...[
                    _NewsCard(item: n),
                    const SizedBox(height: 10),
                  ],
                  _MehrNews(onTap: () => _openList(context)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Eine Schlagzeile als Zeile mit Titelbild.
///
/// **Das Bild kommt aus dem Feed, nicht aus dem Artikel.** Nur die Sportschau
/// liefert eines je Meldung (gemessen 03.09.2026); wo keins dabei ist, steht
/// eine Ersatzfläche mit Zeitungssymbol — eine leere Lücke sähe aus wie ein
/// Ladefehler.
class _NewsCard extends StatelessWidget {
  const _NewsCard({required this.item});

  final NewsItem item;

  /// Das Seitenverhältnis der Quelle: Die Sportschau liefert ihre Bilder als
  /// „16x9-big" — anders beschnitten fehlte oben oder unten der halbe Kopf.
  static const _format = 16 / 9;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final meta = [
      if (item.source != null) item.source!,
      if (item.publishedAt != null) relativeNewsTime(item.publishedAt!),
    ].join(' · ');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => openNews(context, item.url),
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.7),
            ),
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // **Das Bild über die volle Breite**, mit dem Rand der Karte
              // ringsum: Es ist der Grund, warum man hier stehen bleibt, und
              // als 116 Punkte breite Kachel war es eine Briefmarke.
              AspectRatio(
                aspectRatio: _format,
                child: NewsBild(url: item.imageUrl, radius: 10),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 0, 2, 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        height: 1.18,
                        fontSize: Schrift.titel,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Icon(
                          Icons.newspaper_outlined,
                          size: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: Schrift.label,
                            ),
                          ),
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
    );
  }
}

/// Der Weg in die volle Liste, unter den fünf Meldungen.
class _MehrNews extends StatelessWidget {
  const _MehrNews({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Alle News',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: Schrift.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
            ],
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
              child: FilledButton(
                child: const Text(
                  'Liga erstellen',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
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
              child: OutlinedButton(
                child: const Text(
                  'Liga suchen',
                  style: TextStyle(fontSize: 17),
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
                  child: Icon(Icons.add, size: 20, color: farbe),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        text,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        hint,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 11,
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

/// Höhe der Karten im Querlauf — für Ligen **und** Tipprunden, denn seit
/// beide ihren Sockel verloren haben, tragen sie dasselbe: Marke, Name,
/// Untertitel. Auch der Ladeplatz rechnet damit, damit die Reihe beim
/// Nachladen nicht springt. Grundmaß bei Standardschrift; auf dem Gerät durch
/// [kartenHoehe] geschickt.
///
/// Wer hier kürzt, prüft es mit einem Namen mit Unterlängen — zu wenig Höhe
/// meldet sich **nicht** als Überlauf, sondern staucht still den `Flexible`
/// um den Namen und schneidet ihn ab. Aus „Tipptest" wurde auf dem Gerät
/// lesbar „Tinntest". Gehalten wird das von der Messung in
/// `test/home_vorschau_test.dart`.
///
/// **116 statt 108 seit dem Wechsel auf Rajdhani** (02.09.2026): Die Schrift
/// baute höher als Barlow Condensed; bei 108 meldete die Karte einen Überlauf
/// von 3,8 Punkten. Mit Inter (seit 14.10.2026) passt es weiterhin.
///
/// **92 seit dem 20.10.2026** (auf Ansage: „die Boxen ein bisschen
/// flacher"). Ohne Sockel und Logo-Kästchen tragen sie nur noch den Namen
/// auf zwei Zeilen (2 × 17 × 1,2 ≈ 41) plus Polster und die 26er-Marke
/// einer Liga mit eigenem Logo.
const double _kKartenHoehe = 92;

/// Marken-Gold des Tippspiels (Fallback, wenn die Runde kein Logo hat).
/// Tippspiel-Gold als **Fläche** (Marke der Tipprunde, Bildkarte). Als Schrift
/// und Zeichen gilt `context.farben.gold` — auf Weiß wäre dieses hier unlesbar.
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
BoxDecoration _kartenFlaeche(BuildContext context, Color farbe) {
  final scheme = Theme.of(context).colorScheme;
  final dark = Theme.of(context).brightness == Brightness.dark;
  final grund = Color.alphaBlend(
    scheme.surfaceContainerHighest.withValues(alpha: 0.45),
    scheme.surface,
  );
  // **Im hellen Modus ohne Grau darunter** (29.10.2026, auf Ansage: „die
  // verschwommenen Farben sehen bei Hell nicht gut aus"). Das Markengrün über
  // einer grauen Fläche ergab ein trübes Pastell, das wie verwischt aussah.
  // Hell mischt die Farbe deshalb in reines Weiß und läuft nicht ins Graue
  // aus, sondern in einen leichten Rest derselben Farbe — die Karte bleibt
  // farbig, aber klar.
  if (!dark) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.alphaBlend(farbe.withValues(alpha: 0.20), Colors.white),
          Color.alphaBlend(farbe.withValues(alpha: 0.06), Colors.white),
        ],
      ),
      border: Border.all(color: Theme.of(context).dividerColor, width: 0.8),
    );
  }
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
    // **Die Kante trägt keine Farbe mehr.** Der Hauch aus der Ecke sagt, zu
    // welchem Bereich die Karte gehört; eine zusätzlich getönte Linie war
    // dieselbe Auskunft ein zweites Mal, leiser und trotzdem uneinheitlich.
    border: Border.all(color: Theme.of(context).dividerColor, width: 0.8),
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

/// Eine Fantasy-Liga als schmale Karte: Markenfarbe, eigener Zustand.
///
/// Die Farbe kam einmal deterministisch aus der Liga-ID und danach aus der
/// Palette des Modus (Redraft kühl, Dynasty warm). Beides ist Geschichte:
/// Seit dem Wegfall von Dynasty (27.09.2026) gibt es nur noch das Markengrün
/// (`leagueColor`). Unterschieden werden zwei Ligen über Name, Zustand und
/// ein eigenes Logo, dessen Farbe die hier sticht.
class _FantasyLeagueCard extends ConsumerWidget {
  const _FantasyLeagueCard({required this.league});

  final FantasyLeague league;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myId = ref.watch(currentUserProvider)?.id;
    final farbe = parseColor(league.logoColor) ?? leagueColor(league.mode);

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
        height: kartenHoehe(context, _kKartenHoehe),
        child: Material(
          color: Colors.transparent,
          // Schneidet das Wasserzeichen an der Kartenkante ab.
          clipBehavior: Clip.antiAlias,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => FantasyLeagueScreen(league: league),
              ),
            ),
            child: Ink(
              decoration: _kartenFlaeche(context, farbe),
              child: Stack(
                children: [
                  // **Kein Logo-Kästchen** (19.10.2026, auf Ansage): Das
                  // MatchUp-Zeichen läuft leise in der Ligafarbe aus der
                  // Ecke, angeschnitten vom Rand — Identität ohne Kasten.
                  // Eine Liga mit eigenem Logo zeigt es oben links als Kreis.
                  if (!_LeagueMark.hatEigenes(league))
                    Positioned(
                      right: -12,
                      top: -10,
                      // Auf Hell kräftiger: 16 % Grün auf Weiß war ein
                      // blasser Fleck ohne Kontur.
                      child: MatchUpChevron(
                        size: 64,
                        color: farbe.withValues(
                          alpha: context.istHell ? 0.38 : 0.16,
                        ),
                      ),
                    ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(11, 10, 8, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  if (_LeagueMark.hatEigenes(league))
                                    _LeagueMark(
                                      league: league,
                                      farbe: farbe,
                                      size: 26,
                                    ),
                                  const Spacer(),
                                  if (pending > 0) _CountBadge(count: pending),
                                ],
                              ),
                              // **Unten links, fest** — ohne Kästchen darüber
                              // rutschte der Name sonst nach oben.
                              Expanded(
                                child: Align(
                                  alignment: Alignment.bottomLeft,
                                  // **Nie mitten im Wort** — ein Wort, das
                                  // nicht passt, schrumpft (`GanzeWoerter`).
                                  child: GanzeWoerter(
                                    league.name,
                                    style: const TextStyle(
                                      fontSize: Schrift.titel,
                                      fontWeight: Schrift.ueberschriftGewicht,
                                      fontStyle: Schrift.ueberschriftStil,
                                      letterSpacing: -0.2,
                                      // 1.05 schnitt die Unterlängen ab
                                      // („Tinntest").
                                      height: 1.2,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 9),
                            ],
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
      ),
    );
  }
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

  /// Eigenes Logo oder Emoji gesetzt?
  static bool hatEigenes(FantasyLeague l) =>
      (l.logoUrl != null && l.logoUrl!.isNotEmpty) ||
      (l.logoEmoji != null && l.logoEmoji!.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    if (hatEigenes(league)) {
      // Rund statt eckig — kein Kästchen auf der Karte.
      return AppAvatar(
        imageUrl: league.logoUrl,
        emoji: league.logoEmoji,
        colorHex: league.logoColor,
        fallbackIcon: Icons.shield_outlined,
        size: size,
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
/// Eine Tipprunde als Karte — dieselbe Form wie eine Liga-Karte, nur flacher.
///
/// Zwischendurch war das hier eine Zeile: andere Form für den zweiten
/// Bereich, und der Name bekam die volle Breite statt der knapp hundert
/// Punkte einer Karte. Zurückgedreht auf ausdrücklichen Wunsch — der Screen
/// hat damit zwei gleich gebaute Reihen untereinander, und was sie trennt,
/// sind Höhe, Marke und Farbe. Der Preis steht in [_kKartenHoehe]: Der Name
/// muss auf zwei Zeilen passen, und „Bundesliga +1" schrumpft, statt zu
/// kappen.
/// **Eine Tipprunde als länglicher Kasten über die volle Breite** — in der
/// Sprache der Fantasy-Ligakarten (29.10.2026, auf Ansage): Hauch aus der
/// Ecke (`_kartenFlaeche`), das MatchUp-Zeichen als Wasserzeichen rechts, der
/// Name schräg unten links — sonst nichts (der Wettbewerb stand einen Tag
/// lang klein darüber und ist auf Ansage wieder raus). Eine Runde mit
/// eigenem Logo zeigt es links als Kreis statt des Wasserzeichens. Der Pfeil
/// am Ende ist entfallen — die Ligakarten tragen auch keinen; dass man
/// draufdrücken kann, sagt die Form.
class _TipRoundStreifen extends ConsumerWidget {
  const _TipRoundStreifen({required this.round});

  final TipRound round;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final farbe = parseColor(round.logoColor) ?? _kTipGold;

    final myId = ref.watch(currentUserProvider)?.id;
    final showBadge =
        round.isPublic && round.isInviteOnly && myId == round.createdBy;
    final pending = showBadge
        ? (ref.watch(tipJoinRequestsProvider(round.id)).valueOrNull?.length ??
              0)
        : 0;

    final eigenesLogo =
        (round.logoUrl != null && round.logoUrl!.isNotEmpty) ||
        (round.logoEmoji != null && round.logoEmoji!.isNotEmpty);

    return _PressScale(
      child: SizedBox(
        height: kartenHoehe(context, _kStreifenHoehe),
        child: Material(
          color: Colors.transparent,
          // Schneidet das Wasserzeichen an der Kante ab.
          clipBehavior: Clip.antiAlias,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: () {
              activateRound(ref, round);
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => LeagueScreen(round: round)),
              );
            },
            child: Ink(
              decoration: _kartenFlaeche(context, farbe),
              child: Stack(
                children: [
                  // Das MatchUp-Zeichen in Gold läuft rechts aus der Kante —
                  // wie bei den Ligakarten, nur liegend statt in der Ecke.
                  if (!eigenesLogo)
                    Positioned(
                      right: -10,
                      top: -12,
                      child: MatchUpChevron(
                        size: 72,
                        color: farbe.withValues(
                          alpha: context.istHell ? 0.42 : 0.16,
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      // Ohne Wettbewerb darüber steht der Name mittig —
                      // unten links ließ er eine leere Zeile über sich.
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (eigenesLogo) ...[
                          _RoundMark(round: round, farbe: farbe, size: 34),
                          const SizedBox(width: 11),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                round.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: Schrift.gross,
                                  fontWeight: Schrift.ueberschriftGewicht,
                                  fontStyle: Schrift.ueberschriftStil,
                                  letterSpacing: -0.3,
                                  // 1.05 schnitt die Unterlängen ab — siehe
                                  // „Tinntest". Rundennamen kommen aus freier
                                  // Eingabe, da steht irgendwann ein „g".
                                  height: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (pending > 0) ...[
                          const SizedBox(width: 8),
                          _CountBadge(count: pending),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Höhe des Tipprunden-Streifens: deutlich flacher als die Ligakarten (92).
/// Seit der Wettbewerb nicht mehr darübersteht, trägt der Streifen nur noch
/// den Namen — bei 76 stand über ihm eine leere Zeile (auf Ansage: 58).
const double _kStreifenHoehe = 58;

/// **Abschnitt „Für alle": die MatchUp Tippliga** — das Tippspiel für alle,
/// nur 1. Bundesliga (Migration 0150).
///
/// Eine schmale Zeile unter den eigenen Tippspielen, **getrennt** davon und
/// bewusst klein (auf Ansage, 29.10.2026: erst stand sie als großer Streifen
/// ganz oben im Tippspiel-Abschnitt und sah aus wie eine der eigenen Runden).
/// Nicht dabei: „27 dabei" und ein kleiner Knopf „Mitspielen", der beitritt
/// und die Runde öffnet — Beitritt per Knopf statt automatisch, damit in der
/// Tabelle nur steht, wer tippt. Dabei: die Zeile öffnet die Runde. Gibt es
/// keine Tippliga (lokaler Modus, Fehler), fehlt der ganze Abschnitt.
/// Die Farbe der Tippliga: das Marken-Rot (auf Ansage „eher rötlich statt
/// gelb") — Gelb gehört den eigenen Tipprunden, Grün den Ligen.
const Color _kTippligaRot = MatchUpColors.red;

class _FuerAlle extends ConsumerStatefulWidget {
  const _FuerAlle();

  @override
  ConsumerState<_FuerAlle> createState() => _FuerAlleState();
}

class _FuerAlleState extends ConsumerState<_FuerAlle> {
  bool _laeuft = false;

  Future<void> _oeffnen(TipRound runde) async {
    activateRound(ref, runde);
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LeagueScreen(round: runde)),
    );
  }

  Future<void> _mitspielen() async {
    setState(() => _laeuft = true);
    try {
      final runde =
          await ref.read(tipRoundRepositoryProvider).tippligaBeitreten();
      ref.invalidate(myRoundsProvider);
      if (!mounted) return;
      await _oeffnen(runde);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Beitreten hat nicht geklappt: $e')),
      );
    } finally {
      if (mounted) setState(() => _laeuft = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final liga = ref.watch(tippligaProvider).valueOrNull;
    if (liga == null) return const SizedBox.shrink();
    final runde = liga.mitglied
        ? ref
              .watch(myRoundsProvider)
              .valueOrNull
              ?.where((r) => r.id == liga.id)
              .firstOrNull
        : null;
    final scheme = Theme.of(context).colorScheme;

    final zeile = Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: _kTippligaRot,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: const MatchUpChevron(size: 14, color: Colors.white),
        ),
        const SizedBox(width: 10),
        // Name oben, Mitspieler klein darunter: In einer Zeile nebeneinander
        // schnitt der Knopf „Mitspielen" die Zahl ab („27 d…").
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Versalien und kursiv wie jede Überschrift der App (auf
              // Ansage) — der Name ist hier der Titel der Zeile.
              Text(
                liga.name.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: Schrift.text,
                  fontWeight: Schrift.ueberschriftGewicht,
                  fontStyle: Schrift.ueberschriftStil,
                  letterSpacing: 0.3,
                ),
              ),
              Text(
                '${liga.mitspieler} dabei',
                maxLines: 1,
                style: TextStyle(
                  fontSize: Schrift.label,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (runde != null)
          Icon(Icons.chevron_right, size: 20, color: scheme.onSurfaceVariant)
        else
          FilledButton(
            onPressed: _laeuft ? null : _mitspielen,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              tapTargetSize: MaterialTapTargetSize.padded,
              shape: const StadiumBorder(),
              textStyle: const TextStyle(
                fontFamily: Schrift.familie,
                fontSize: Schrift.label + 1,
                fontWeight: FontWeight.w800,
              ),
            ),
            child: Text(_laeuft ? '…' : 'Mitspielen'),
          ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        abschnittsKopf(context, 'Für alle'),
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: runde != null
                ? () => _oeffnen(runde)
                : (_laeuft ? null : _mitspielen),
            // Derselbe Hauch aus der Ecke wie bei Ligen und Tipprunden, in
            // Rot: eigene Farbe für das, was allen gehört.
            child: Ink(
              decoration: _kartenFlaeche(context, _kTippligaRot),
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: zeile,
            ),
          ),
        ),
        const SizedBox(height: 18),
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
            fontSize: 11,
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
  const _PressScale({required this.child});

  final Widget child;

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
        child: MergeSemantics(child: widget.child),
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
        // **Versalien und kursiv** (auf Ansage, 14.10.2026). Kursiv aus einer
        // echten Schnittdatei (`Inter-ExtraBoldItalic.ttf`), nicht schräg
        // gerechnet — ohne sie stellt Flutter die Buchstaben künstlich schief,
        // und das sieht an einer Wortmarke verzogen aus. Versalien laufen
        // breiter, deshalb leicht gesperrt statt eng wie vorher.
        Text.rich(
          TextSpan(
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              fontStyle: FontStyle.italic,
              letterSpacing: 0.4,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            children: [
              const TextSpan(text: 'MATCH'),
              TextSpan(
                text: 'UP',
                style: TextStyle(color: context.farben.gruen),
              ),
            ],
          ),
          semanticsLabel: 'MatchUp',
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

/// Auswahl beim „Neu": Fantasy-Liga, Tippspiel oder einer bestehenden Runde
/// beitreten. Gibt `'fantasy'`, `'tip'` bzw. `'join'` zurück.
///
/// **Zwei große Bilder, ein Wort darauf** (18.10.2026, auf Ansage: „viel
/// weniger Schrift … die Untertitel können komplett raus … die Buttons ein
/// bisschen größer, damit der Screen mehr aufgefüllt ist"). Überschrift,
/// Erklärsatz, Untertitel und das „ODER" sind weg; die beiden Karten teilen
/// sich die Höhe des Schirms, darunter steht der Beitreten-Weg in einer
/// Zeile. Die Namen stehen in Versalien und schräg wie die Wortmarke.
///
/// Davor stand an derselben Stelle der Satz „Jede Karte sagt den Unterschied
/// in einer Zeile" — die Bilder (Spieler gegen Tippschein) tragen das, und
/// die Zeile las niemand.
class _CreateOrJoinScreen extends StatelessWidget {
  const _CreateOrJoinScreen();

  @override
  Widget build(BuildContext context) {
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
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _StartKarte(
                  farbe: MatchUpColors.green,
                  bild: 'assets/images/fantasy_bg.jpg',
                  titel: 'Fantasy',
                  onTap: () => Navigator.of(context).pop('fantasy'),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _StartKarte(
                  farbe: _kTipGold,
                  bild: 'assets/images/tippspiel_bg.jpg',
                  titel: 'Tippspiel',
                  onTap: () => Navigator.of(context).pop('tip'),
                ),
              ),
              const SizedBox(height: 12),
              _BeitretenKarte(onTap: () => Navigator.of(context).pop('join')),
            ],
          ),
        ),
      ),
    );
  }
}

/// Eine der beiden Startkarten: Bild, Marke, ein Wort. Die Höhe kommt vom
/// Schirm (je die Hälfte), nicht mehr fest aus der Karte — ohne Untertitel
/// trägt sie auch auf einem kleinen Gerät, und auf einem großen füllt sie.
class _StartKarte extends StatelessWidget {
  const _StartKarte({
    required this.farbe,
    required this.bild,
    required this.titel,
    required this.onTap,
  });

  final Color farbe;
  final String bild;
  final String titel;
  final VoidCallback onTap;

  static final _radius = BorderRadius.circular(22);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$titel erstellen',
      excludeSemantics: true,
      child: _PressScale(
        child: Container(
          // Die Kante ist die Haarlinie wie bei jeder Karte; die Farbe trägt
          // die Marke und der Schleier über dem Bild.
          foregroundDecoration: BoxDecoration(
            borderRadius: _radius,
            border: Border.all(color: Theme.of(context).dividerColor),
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
                    // Oben ein Farbschleier, damit das Bild sichtbar bleibt,
                    // unten fast deckend, wo das Wort steht.
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            farbe.withValues(alpha: 0.18),
                            MatchUpColors.base.withValues(alpha: 0.5),
                            MatchUpColors.base.withValues(alpha: 0.94),
                          ],
                          stops: const [0.0, 0.5, 1.0],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: farbe,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: MatchUpChevron(
                              size: 22,
                              color: MatchUpColors.base,
                            ),
                          ),
                          const Spacer(),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              // Schrumpfen statt kappen — bei großer
                              // Systemschrift passt „TIPPSPIEL" sonst nicht.
                              Expanded(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    titel.toUpperCase(),
                                    maxLines: 1,
                                    style: const TextStyle(
                                      fontSize: 40,
                                      fontWeight: Schrift.ueberschriftGewicht,
                                      fontStyle: Schrift.ueberschriftStil,
                                      color: Colors.white,
                                      letterSpacing: 0.4,
                                      height: 1.0,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Icon(Icons.arrow_forward, size: 28, color: farbe),
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
    );
  }
}

/// Der dritte Weg: einer bestehenden Runde beitreten. Bewusst ruhiger als die
/// beiden Startkarten — wer einen Code hat, sucht ihn gezielt. Eine Zeile,
/// kein Untertitel.
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
            constraints: const BoxConstraints(minHeight: 60),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: kartenDeko(context),
            child: Row(
              children: [
                Icon(
                  Icons.vpn_key_outlined,
                  size: 22,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    'Mit Code beitreten',
                    style: TextStyle(
                      fontSize: Schrift.titel,
                      fontWeight: Schrift.ueberschriftGewicht,
                      fontStyle: Schrift.ueberschriftStil,
                    ),
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

/// Das eigene Profilbild oben links — der Weg ins Profil.
///
/// Ein roter Punkt sagt, dass dort etwas wartet (Freundschaftsanfragen). Die
/// ungelesenen Nachrichten zählt schon der Knopf in der Grußzeile; zwei
/// Zähler für dieselbe Sache wären einer zu viel.
class _ProfilKnopf extends ConsumerWidget {
  const _ProfilKnopf();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final name = ref.watch(currentUsernameProvider).valueOrNull;
    final anfragen = ref.watch(incomingRequestsProvider).length;
    return IconButton(
      tooltip: anfragen > 0 ? 'Profil, $anfragen Anfragen' : 'Profil',
      onPressed: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          AppAvatar(
            imageUrl: profile?.avatarUrl,
            emoji: profile?.avatarEmoji,
            colorHex: profile?.avatarColor,
            fallbackText: name,
            size: 30,
          ),
          if (anfragen > 0)
            Positioned(
              right: -1,
              top: -1,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: scheme.error,
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.surface, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Nachrichten oben rechts in der Kopfleiste — das Gegenstück zum Profilbild.
///
/// Die Sprechblase ist eines der wenigen Symbole, die man ohne Wort erkennt;
/// das Wort steht im `tooltip` und in der Ansage. Der rote Zähler sagt, wie
/// viele Nachrichten warten — sonst trägt der Knopf keine Farbe.
class _NachrichtenKnopf extends ConsumerWidget {
  const _NachrichtenKnopf();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ungelesen = ref.watch(unreadDmCountProvider);
    return IconButton(
      tooltip: ungelesen > 0
          ? 'Nachrichten, $ungelesen ungelesen'
          : 'Nachrichten',
      onPressed: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const ConversationsScreen())),
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.forum_outlined, size: 24),
          if (ungelesen > 0)
            Positioned(
              right: -11,
              top: -8,
              child: _CountBadge(count: ungelesen),
            ),
        ],
      ),
    );
  }
}
