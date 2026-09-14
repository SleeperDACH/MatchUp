import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/app/widgets/punktzahl.dart';
import 'package:matchup/core/config/app_config.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/features/auth/providers.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_engine.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_rules.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/features/fantasy/providers.dart';
import 'package:matchup/features/fantasy/ui/matchup_lineups.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'support/schrift.dart';

/// **Zwei Ziele in einer Zeile, mit sichtbarer Grenze.**
///
/// Gewünscht: Ein Tipp auf die Punktebox zeigt die Aufschlüsselung, ein Tipp
/// auf den Rest der Karte führt wie gewohnt ins Spielerprofil.
///
/// Das ist die Sorte Verdrahtung, die ein Golden nicht prüfen kann — ein Bild
/// zeigt, wie es aussah, nicht wohin ein Tipp führt. Deshalb zwei
/// Zusicherungen statt eines Bildes, und beide gegengeprüft: Ohne die Trennung
/// öffnet die Box das Profil mit.

const _roster = RosterConfig(
  gk: 1, def: 4, mid: 4, fwd: 2, bench: 5,
  defMin: 3, defMax: 5, midMin: 2, midMax: 5, fwdMin: 1, fwdMax: 4,
);

final _liga = FantasyLeague(
  id: 'l1',
  name: 'MatchUp! #1',
  mode: FantasyMode.liga,
  season: 2026,
  pickTime: DraftPickTime.h2,
  scoring: const FantasyScoringRules(),
  roster: _roster,
  inviteCode: 'ABC',
  draftStatus: DraftStatus.done,
  createdBy: 'u1',
  maxTeams: 18,
);

FantasyPlayer _p(String id, String name, PlayerPosition pos) => FantasyPlayer(
      id: id,
      name: name,
      position: pos,
      club: 'FC Bayern München',
      nationality: 'de',
      birthDate: DateTime(1998, 5, 4),
    );

List<FantasyPlayer> _elf(String p) => [
      _p('${p}gk', 'Jonas Urbig', PlayerPosition.gk),
      for (var i = 0; i < 4; i++)
        _p('${p}d$i', 'Robin Koch $i', PlayerPosition.def),
      for (var i = 0; i < 4; i++)
        _p('${p}m$i', 'Rani Khedira $i', PlayerPosition.mid),
      for (var i = 0; i < 2; i++)
        _p('${p}f$i', 'Michael Olise $i', PlayerPosition.fwd),
    ];

MatchupSideData _seite(String p, {double je = 12.0}) => MatchupSideData(
      _elf(p),
      const [],
      {for (final x in _elf(p)) x.id: je},
      je * 11,
      {for (final x in _elf(p)) x.id},
    );

/// Ein Torwart mit einem greifbaren Spieltag: 90 Minuten, zu Null, vier
/// Paraden. Genau daraus muss die Aufschlüsselung ihre Zeilen bilden.
const _torwartTag = PlayerMatchStats(
  minutes: 90,
  played: true,
  saves: 4,
  cleanSheet: true,
);

/// Ein Spielplan, dessen Partie **angepfiffen** ist — sonst steht in der Box
/// die Anstoßzeit statt einer Punktzahl, und es gäbe nichts anzutippen.
final _spiele = [
  Fixture(
    id: 'sportmonks:1',
    leagueId: 'bundesliga',
    season: 2026,
    round: 2,
    roundName: 'Spieltag 2',
    kickoff: DateTime.now().subtract(const Duration(hours: 2)),
    home: const TeamRef(
        id: 'fcb', name: 'FC Bayern München', shortName: 'FCB'),
    away: const TeamRef(id: 'bvb', name: 'Borussia Dortmund', shortName: 'BVB'),
    status: FixtureStatus.finished,
    homeScore: 1,
    awayScore: 0,
  ),
];

Widget _rahmen({
  required Map<String, PlayerMatchStats> stats,
  double gastJe = 12.0,
}) =>
    ProviderScope(
      overrides: [
        fantasySeasonFixturesProvider.overrideWith((ref) async => _spiele),
        clubIconsProvider.overrideWith((ref) async => const {}),
        playerPoolProvider.overrideWith((ref) async => _elf('h')),
        currentUserProvider.overrideWith((ref) => User(
              id: 'u1',
              appMetadata: const {},
              userMetadata: const {},
              aud: 'authenticated',
              createdAt: DateTime(2026).toIso8601String(),
            )),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          backgroundColor: MatchUpColors.base,
          body: SingleChildScrollView(
            child: MatchupLineups(
              league: _liga,
              runde: 2,
              home: _seite('h'),
              away: _seite('a', je: gastJe),
              homeId: 'u1',
              awayId: 'u2',
              homeName: 'SFV03',
              awayName: 'Lewin9',
              stats: stats,
            ),
          ),
        ),
      ),
    );

/// Die Punktebox eines Spielers — gefunden über ihre Vorlese-Beschriftung.
///
/// Nicht über `find.bySemanticsLabel`: Das liest den Semantik-Baum, den ein
/// Widget-Test nur auf Anforderung aufbaut, und die Box liegt darin neben der
/// Zahl statt über ihr. Über das `Semantics`-Widget selbst ist es eindeutig —
/// und prüft nebenbei mit, dass der Knopf für die Vorlesehilfe einen Namen
/// hat statt „Schaltfläche" zu heißen.
Finder _punkteBox(String spieler) => find.byWidgetPredicate(
      (w) =>
          w is Semantics &&
          w.properties.label == '$spieler: Punkte aufschlüsseln',
    );

void main() {
  setUpAll(ladeSchrift);

  setUp(() {
    // Ohne das hält sich das Profil für serverlos und zeigt statt allem eine
    // Hinweiskarte — es ginge dann trotzdem auf, aber ohne seine Reiter.
    AppConfig.supabaseInitialized = true;
  });
  tearDown(() => AppConfig.supabaseInitialized = false);

  testWidgets('die Punktebox öffnet die Aufschlüsselung', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 1200 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_rahmen(stats: {'hgk': _torwartTag}));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    // Der Torwart der Heimseite steht ganz oben; seine Box trägt die 12.
    await tester.tap(_punkteBox('Jonas Urbig'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    // Die Zeilen kommen aus derselben Funktion, die auch wertet.
    expect(find.text('Jonas Urbig · 2. Spieltag'), findsOneWidget);
    expect(find.text('Parade'), findsOneWidget);
    expect(find.text('Zu Null'), findsOneWidget);
    // Und **nicht** das Profil: Der Tipp darf nicht nach außen durchschlagen.
    expect(find.text('Aufstellung'), findsNothing);
  });

  testWidgets('der Rest der Karte führt weiter ins Profil', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 1200 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_rahmen(stats: {'hgk': _torwartTag}));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    await tester.tap(find.text('Urbig').first);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    // Das Profil erkennt man an seinen Reitern, nicht am Namen — der steht
    // auch in der Zeile darunter.
    expect(find.text('Leistung'), findsOneWidget);
    expect(find.text('Aufstellung'), findsOneWidget);
  });

  testWidgets('Vorschau: Positionsstand im Kopf statt Duell je Zeile',
      (tester) async {
    // **Der Vergleich, den es wirklich gibt.** Die Paarung je Zeile entsteht
    // über den Index innerhalb der Position und ist keine Rangfolge — bei
    // verschiedenen Formationen wird obendrein willkürlich gepaart. Die Summe
    // je Block gilt unabhängig von der Anzahl.
    tester.view.physicalSize = const Size(402 * 3, 1200 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
        _rahmen(stats: {'hgk': _torwartTag}, gastJe: 5.0));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    // Vier Blöcke, vier Stände: Tor 12:5, Abwehr 48:20, Mittelfeld 48:20,
    // Sturm 24:10.
    expect(find.text('48'), findsNWidgets(2));
    expect(find.text('20'), findsNWidgets(2));

    // **Den `Scaffold` aufnehmen, nicht den Teilbaum.** `MatchupLineups`
    // malt keinen Grund; direkt aufgenommen wäre das Bild weiß, und man
    // beurteilte einen Schirm, den es so nicht gibt.
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/matchup_positionsstand.png'),
    );
  });

  testWidgets('Minuspunkte stehen rot da', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 1200 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    // Ein Verteidiger mit drei Gegentoren und Gelb landet im Minus — das ist
    // kein Randfall, sondern ein gewöhnlicher Samstag.
    await tester.pumpWidget(_rahmen(stats: {'hgk': _torwartTag}, gastJe: -8.5));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    final rot = Theme.of(tester.element(find.byType(MatchupLineups)))
        .colorScheme
        .error;

    // **Nur die Spielerzahlen.** Der Stand im Blockkopf ist eine
    // Mannschaftssumme und trägt seine Farbe für „führt", nicht für „minus" —
    // ein Text-Filter über den ganzen Baum träfe ihn mit.
    final inPunktzahl =
        find.descendant(of: find.byType(Punktzahl), matching: find.byType(Text));
    final minus = tester
        .widgetList<Text>(inPunktzahl)
        .where((t) => (t.data ?? '').startsWith('-8'));
    expect(minus, isNotEmpty, reason: 'die Minuszahlen müssen im Bild stehen');
    for (final t in minus) {
      expect(t.style?.color, rot);
    }

    // **Die positiven bleiben neutral.** Eine Farbe, die alle Zahlen trifft,
    // hebt nichts hervor — derselbe Fehler wie die rote Wäsche im Live-Tab.
    final plus =
        tester.widgetList<Text>(inPunktzahl).where((t) => t.data == '12');
    expect(plus, isNotEmpty);
    for (final t in plus) {
      expect(t.style?.color, isNot(rot));
    }
  });

  testWidgets('ohne Statistik bleibt die Box eine Anzeige', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 1200 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    // Kein Eintrag für den Torwart: Es gibt nichts aufzuschlüsseln, und ein
    // leeres Blatt wäre schlechter als kein Blatt.
    await tester.pumpWidget(_rahmen(stats: const {}));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    expect(_punkteBox('Jonas Urbig'), findsNothing);
  });
}
