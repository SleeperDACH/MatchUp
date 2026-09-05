import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/models/models.dart';
import '../../core/models/team_fixture.dart';
import '../../features/tippspiel/ui/team_badge.dart';
import '../match_detail_screen.dart';
import '../theme.dart';
import 'pulsing_dot.dart';

/// Gemeinsame Darstellung eines Team-Spielplans: Datums-Überschriften und
/// Spiel-Boxen mit Wettbewerbslogo, Spieltag, beiden Wappen und Ergebnis.
///
/// Liegt hier und nicht im Favoriten-Tab, weil die Vereinsseite dieselbe
/// Darstellung benutzt. Zwei Kopien wären beim nächsten Feinschliff sofort
/// wieder auseinandergelaufen.

/// **Der Spielplan beginnt beim nächsten Spiel.**
///
/// Gemeldet an den Favoriten: erst *„es müssen auch die vorherigen Spiele zu
/// sehen sein"*, und danach — als sie oben standen — *„die nächsten Spiele
/// sollen ganz oben angezeigt werden. Dann kann man aber trotzdem noch nach
/// oben wischen, und dort steht dann ‚Vorherige Spiele anzeigen'."*
///
/// Beide Wünsche vertragen sich nur, wenn die Liste **nicht am Anfang
/// beginnt**. Die drei Anläufe davor sind der Grund für diese Bauart:
///
/// | Fassung | warum sie fiel |
/// |---|---|
/// | alles nach Anstoß, Ergebnisse unten | 150 Tage Vorlauf davor — sie waren unauffindbar |
/// | drei Blöcke, „Zuletzt" ganz oben | die Frage „wer kommt jetzt?" stand hinter drei Ergebnissen |
/// | jetzt: der Anker liegt bei den kommenden Spielen | — |
///
/// Der Schirm öffnet bei **Nächste Spiele**; alles Vergangene liegt darüber
/// und wird nur sichtbar, wenn man es holt. Ein `CustomScrollView` mit
/// [center] kann das: Slivers **vor** dem Anker wachsen nach oben, ihr Kind 0
/// liegt direkt über der Trennstelle. Deshalb wird die Liste dort **rückwärts
/// indiziert** — die Reihenfolge im Bild bleibt so von oben nach unten
/// lesbar, das jüngste Ergebnis sitzt unmittelbar über dem nächsten Spiel.
///
/// **Der zweite Grund für den Anker ist das Nachwachsen.** Werden die
/// Ergebnisse aufgeklappt, entstehen sie **oberhalb** der Trennstelle: Die
/// Scroll-Position bleibt, wo sie ist, und unter dem Daumen springt nichts.
/// Eine gewöhnliche Liste müsste dafür ihre Höhe schätzen — dieselbe Rechnerei
/// wie beim Chat, der aus genau diesem Grund `reverse: true` benutzt.
class SpielplanAnsicht extends StatefulWidget {
  const SpielplanAnsicht({
    super.key,
    required this.fixtures,
    this.padding = const EdgeInsets.fromLTRB(12, 8, 12, 96),
    this.onRefresh,
  });

  final List<TeamFixture> fixtures;
  final EdgeInsets padding;

  /// Zum Neuladen nach unten ziehen. Greift am **oberen** Ende der Liste, also
  /// über den Ergebnissen — an der Trennstelle zieht man die Vergangenheit
  /// herunter, und genau das ist hier gewollt.
  final Future<void> Function()? onRefresh;

  @override
  State<SpielplanAnsicht> createState() => _SpielplanAnsichtState();
}

class _SpielplanAnsichtState extends State<SpielplanAnsicht> {
  /// Der Anker, an dem der Schirm aufgeht. Ein `center`-Schlüssel muss an
  /// einem Sliver **in derselben Liste** hängen, sonst wirft der Viewport.
  static const _anker = ValueKey<String>('spielplan-anker');

  bool _vergangeneOffen = false;

  @override
  Widget build(BuildContext context) {
    final kommend = [
      for (final f in widget.fixtures)
        if (f.status != FixtureStatus.finished) f
    ]..sort((a, b) => a.kickoff.compareTo(b.kickoff));
    // **Aufsteigend, nicht absteigend.** Die Ergebnisse stehen über der
    // Trennstelle und lesen sich von oben nach unten wie der Rest der App:
    // das älteste ganz oben, das zuletzt passierte unmittelbar über dem
    // nächsten Spiel.
    final vergangen = [
      for (final f in widget.fixtures)
        if (f.status == FixtureStatus.finished) f
    ]..sort((a, b) => a.kickoff.compareTo(b.kickoff));

    // Steht nichts mehr an, gibt es nichts zu verstecken: Dann ist die
    // Vergangenheit der ganze Inhalt, und ein Knopf davor wäre eine Hürde vor
    // dem einzigen, was da ist.
    final offen = _vergangeneOffen || kommend.isEmpty;

    final oben = <Widget>[];
    if (vergangen.isNotEmpty) {
      if (offen) {
        oben.add(const FixtureSectionLabel('Vorherige Spiele'));
        oben.addAll(fixturesWithDateHeaders(vergangen));
      } else {
        oben.add(
          _VorherigeSpieleKnopf(
            anzahl: vergangen.length,
            onTap: () => setState(() => _vergangeneOffen = true),
          ),
        );
      }
    }

    final seiten = EdgeInsets.only(
      left: widget.padding.left,
      right: widget.padding.right,
    );

    final liste = CustomScrollView(
      center: _anker,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: seiten.copyWith(top: widget.padding.top),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              // Rückwärts: Kind 0 liegt direkt über dem Anker, deshalb steht
              // hier das **letzte** Element der Bildreihenfolge.
              (_, i) => oben[oben.length - 1 - i],
              childCount: oben.length,
            ),
          ),
        ),
        SliverToBoxAdapter(
          key: _anker,
          child: kommend.isEmpty
              ? const SizedBox.shrink()
              : Padding(
                  padding: seiten,
                  child: const FixtureSectionLabel('Nächste Spiele'),
                ),
        ),
        SliverPadding(
          padding: seiten.copyWith(bottom: widget.padding.bottom),
          sliver: SliverList.list(children: fixturesWithDateHeaders(kommend)),
        ),
      ],
    );

    final onRefresh = widget.onRefresh;
    if (onRefresh == null) return liste;
    return RefreshIndicator(onRefresh: onRefresh, child: liste);
  }
}

/// Der Griff in die Vergangenheit — die einzige Zeile über der Trennstelle,
/// solange nichts aufgeklappt ist.
///
/// Der Pfeil zeigt nach oben, weil dort steht, was er holt. Die Zahl daneben
/// sagt, wie viel kommt: „anzeigen" allein verrät nicht, ob man drei Zeilen
/// bekommt oder eine halbe Saison.
class _VorherigeSpieleKnopf extends StatelessWidget {
  const _VorherigeSpieleKnopf({required this.anzahl, required this.onTap});

  final int anzahl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.keyboard_arrow_up,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                'Vorherige Spiele anzeigen',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$anzahl',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Spiele als Liste, **je Anstoßzeit ein Kopf**.
///
/// Vorher bekam **jedes** Spiel seinen eigenen Kopf: Die Schleife rechnete
/// zwar `lastDay` mit, benutzte es aber nirgends, und beide Zweige des `if`
/// taten dasselbe. In einer Vereinsliste fiel das nicht auf — dort steht je
/// Datum ohnehin nur eine Partie. Auf dem Spieltag der Liga-Übersicht standen
/// damit neun Köpfe über neun Spielen, fünfmal davon derselbe: „Sa, 6. Sept,
/// Bundesliga, 2. Spieltag". Gemeldet als *„Das ist anstrengend, wenn du immer
/// das Datum dazwischen hast."*
///
/// Jetzt zählt die **Anstoßzeit auf die Minute**: Alle Spiele, die zugleich
/// beginnen, stehen unter einem Kopf. Dieselbe Entscheidung wie im Live-Tab
/// und im Tippspiel — und die Uhrzeit wandert damit aus der Zeile in den Kopf,
/// wo sie einmal statt fünfmal steht.
///
/// Für eine Vereins- oder Favoritenliste ändert sich dadurch nichts: Dort
/// trägt jede Partie ihren eigenen Anstoß, also bekommt jede weiterhin ihren
/// eigenen Kopf.
List<Widget> fixturesWithDateHeaders(List<TeamFixture> list) {
  final out = <Widget>[];
  DateTime? letzterAnstoss;
  for (var i = 0; i < list.length; i++) {
    final f = list[i];
    final lt = f.kickoff.toLocal();
    final anstoss = DateTime(lt.year, lt.month, lt.day, lt.hour, lt.minute);
    final neuerBlock = letzterAnstoss == null || letzterAnstoss != anstoss;
    if (i > 0) out.add(const _Trennlinie());
    if (neuerBlock) {
      out.add(FixtureDateHeader(date: anstoss, fixture: f, mitZeit: true));
      letzterAnstoss = anstoss;
    }
    out.add(TeamFixtureCard(fixture: f, zeitImKopf: true));
  }
  return out;
}

/// Haarlinie zwischen zwei Spielen — die Liste kommt ohne Kästen aus.
class _Trennlinie extends StatelessWidget {
  const _Trennlinie();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Container(
      height: 0.8,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.07),
    ),
  );
}

/// Zeile über einem Spiel: Datum, Wettbewerb, Spieltag — alles, was **nicht**
/// die Partie ist, an einem Ort.
class FixtureDateHeader extends StatelessWidget {
  const FixtureDateHeader({
    super.key,
    required this.date,
    this.fixture,
    this.mitZeit = false,
  });

  final DateTime date;

  /// Liefert Wettbewerb und Spieltag. Ohne Spiel bleibt es beim Datum.
  final TeamFixture? fixture;

  /// Setzt die **Anstoßzeit** neben das Datum. Sie steht dann nicht mehr in
  /// jeder Zeile darunter — bei fünf Samstagsspielen war das fünfmal
  /// dieselbe Zahl, die die Zeilen nicht unterscheidet.
  final bool mitZeit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = DateFormat('E, d. MMM', 'de_DE').format(date);
    final f = fixture;
    final zusatz = f == null
        ? null
        : [f.leagueName, ?matchdayLabel(f)].join(', ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            label[0].toUpperCase() + label.substring(1),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          if (mitZeit) ...[
            const SizedBox(width: 7),
            Text(
              DateFormat('HH:mm').format(date),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
          if (zusatz != null) ...[
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                '· $zusatz',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}


class FixtureSectionLabel extends StatelessWidget {
  const FixtureSectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Dieselbe Kapitelmarke wie im Live-Tab: Wort, dann eine Haarlinie bis an
    // den Rand. Zwei Schirme, die dieselbe Liste zeigen, sollen sie auch
    // gleich gliedern.
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 2),
      child: Row(
        children: [
          Text(
            text.toUpperCase(),
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 0.8,
              color: scheme.onSurface.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }
}


/// Spieltag- bzw. Pokalrunden-Bezeichnung eines Team-Spiels (null = unbekannt).
String? matchdayLabel(TeamFixture f) {
  if (f.round <= 0) return null;
  final isCup = f.leagueName.toLowerCase().contains('pokal');
  if (isCup) {
    return switch (f.round) {
      1 => '1. Runde',
      2 => '2. Runde',
      3 => 'Achtelfinale',
      4 => 'Viertelfinale',
      5 => 'Halbfinale',
      6 => 'Finale',
      _ => 'Runde ${f.round}',
    };
  }
  return '${f.round}. Spieltag';
}


/// Ein Spiel des Team-Spielplans als **Zeile**, nicht als Karte.
///
/// Wappen an den Außenkanten, die Namen direkt daneben, Uhrzeit oder Ergebnis
/// in der Mitte — dieselbe Anordnung wie im Live-Tab. Vorher war es genau
/// andersherum (Wappen innen, Namen außen) und dazu eine gerahmte Box mit
/// eigener Kopfzeile für Wettbewerb und Spieltag; zwei Schirme, die dieselbe
/// Liste zeigen, fluchteten dadurch nicht miteinander. Was nicht die Partie
/// ist, steht jetzt in der Zeile darüber ([FixtureDateHeader]).
class TeamFixtureCard extends StatelessWidget {
  const TeamFixtureCard({
    super.key,
    required this.fixture,
    this.zeitImKopf = false,
  });

  /// Steht der Anstoß schon im Kopf des Blocks, trägt die Zeile ihn nicht noch
  /// einmal. Statt der Zahl hält ein gedämpfter Strich die Spalte besetzt —
  /// er ist in dieser App ohnehin das Zeichen für „hat noch nicht gespielt",
  /// und ohne ihn liefen die Namen beider Mannschaften an die Ränder
  /// auseinander.
  final bool zeitImKopf;
  final TeamFixture fixture;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final f = fixture;
    final live = f.status == FixtureStatus.live;
    final finished = f.status == FixtureStatus.finished;

    return Material(
      color: live
          ? MatchUpColors.red.withValues(alpha: 0.07)
          : Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => MatchDetailScreen(fixtureId: f.id)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Row(
            children: [
              TeamBadge(team: f.home, size: 22),
              const SizedBox(width: 9),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    f.home.name,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 58,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (f.hasScore)
                      Text(
                        '${f.homeScore}:${f.awayScore}',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: live
                              ? MatchUpColors.red
                              : scheme.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      )
                    else if (zeitImKopf)
                      Text(
                        '–',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface.withValues(alpha: 0.28),
                        ),
                      )
                    else
                      Text(
                        DateFormat('HH:mm').format(f.kickoff.toLocal()),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    if (finished)
                      Text(
                        'beendet',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    f.away.name,
                    maxLines: 1,
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              TeamBadge(team: f.away, size: 22),
              SizedBox(
                width: 13,
                child: live
                    ? const Align(
                        alignment: Alignment.centerRight,
                        child: PulsingDot(size: 7),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

