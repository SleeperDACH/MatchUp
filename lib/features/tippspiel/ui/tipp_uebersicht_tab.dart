import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/farben.dart';
import '../../../app/home_tip_status.dart' show kurzeFrist;
import '../../../app/typografie.dart';
import '../../../app/widgets/kapitelmarke.dart';
import '../../../app/widgets/karte.dart';
import '../../../app/widgets/skelett.dart';
import '../../../core/models/models.dart';
import '../../../core/ui/app_avatar.dart';
import '../../auth/providers.dart';
import '../logic/tip_weeks.dart';
import '../logic/tipp_uebersicht.dart';
import '../models/tip_round.dart';
import '../providers.dart';
import 'bonus_tips_screen.dart';
import 'bonus_tips_table_screen.dart';
import 'league_hub_screen.dart';

/// Positionen der Reiter einer Tipprunde — eine Stelle, damit ein
/// Umsortieren nicht still einen Sprung ins falsche Ziel schickt (wie
/// `LigaReiter` bei Fantasy).
abstract final class TippReiter {
  static const uebersicht = 0;
  static const tippen = 1;
  static const tabelle = 2;
  static const duelle = 3;
}

/// **Die Übersicht einer Tipprunde** (09.11.2026, „Richtung B" aus dem
/// Redesign, auf Ansage: „Ich mag B").
///
/// Vorher öffnete die Runde auf der Tabelle, die Tippabgabe lag einen Reiter
/// daneben, und Bonustipps, Regeln und Einladen steckten über drei Orte
/// verteilt (Tabelle, Liga-Reiter, Zahnrad). Jetzt der Aufbau der
/// Fantasy-Übersicht: oben der eine Auftrag (offene Tipps, gold), darunter der
/// eigene Stand als drei Zahlen ohne Kasten, eine Kurztabelle und die Wege der
/// Liga als Zeilen.
class TippUebersichtTab extends ConsumerWidget {
  const TippUebersichtTab({super.key, required this.round});

  final TipRound round;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Globales Tippspiel: nur der Ausschnitt vom Server (0169), nicht alle
    // Tipps aller Mitspieler.
    final ausschnittAsync = round.istGlobal
        ? ref.watch(globalerAusschnittProvider((roundId: round.id, vor: null)))
        : null;
    final ausschnitt = ausschnittAsync?.valueOrNull;
    final membersAsync = round.istGlobal
        ? ausschnittAsync!.whenData((a) => a.members)
        : ref.watch(roundMembersProvider(round.id));
    final tipsAsync = round.istGlobal
        ? ausschnittAsync!.whenData((a) => a.tips)
        : ref.watch(allRoundTipsProvider(round.id));
    final seasonAsyncs = [
      for (final id in round.competitions)
        ref.watch(leagueSeasonFixturesProvider(id)),
    ];
    final members = membersAsync.valueOrNull;
    final tips = tipsAsync.valueOrNull;
    if (members == null ||
        tips == null ||
        seasonAsyncs.any((a) => a.valueOrNull == null)) {
      final fehler =
          membersAsync.error ??
          tipsAsync.error ??
          seasonAsyncs.map((a) => a.error).nonNulls.firstOrNull;
      if (fehler != null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Übersicht konnte nicht geladen werden.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () {
                    ref.invalidate(roundMembersProvider(round.id));
                    ref.invalidate(allRoundTipsProvider(round.id));
                    ref.invalidate(globalerAusschnittProvider);
                  },
                  child: const Text('Erneut laden'),
                ),
              ],
            ),
          ),
        );
      }
      return const Skelett();
    }

    final daten = TippUebersicht.berechnen(
      members: members,
      tips: tips,
      seasonFixtures: [
        for (final a in seasonAsyncs) ...(a.valueOrNull ?? const <Fixture>[]),
      ],
      rules: round.scoring,
      myId: ref.watch(currentUserProvider)?.id,
      jetzt: DateTime.now(),
      frozenOdds: ref.watch(frozenOddsProvider).valueOrNull ?? const {},
      raenge: ausschnitt == null
          ? null
          : {for (final z in ausschnitt.zeilen) z.userId: z.platz},
      mitgliederGesamt: ausschnitt?.mitglieder,
    );

    void go(Widget screen) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    void reiter(int i) => DefaultTabController.of(context).animateTo(i);

    final linked = round.isFantasyLinked || round.istGlobal;
    final chatNeu = !linked && ref.watch(unreadChatProvider(round.id));

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(roundMembersProvider(round.id));
        ref.invalidate(allRoundTipsProvider(round.id));
        ref.invalidate(globalerAusschnittProvider);
        for (final id in round.competitions) {
          ref.invalidate(leagueSeasonFixturesProvider(id));
        }
      },
      child: ListView(
        padding: const EdgeInsets.only(top: 14, bottom: 24),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (daten.rang != null || daten.anstehend > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _Anzeigetafel(
                daten: daten,
                onTippen: () => reiter(TippReiter.tippen),
              ),
            ),
          if (daten.spieltag.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Kapitelmarke(
                spieltagTitel(daten.spieltagWoche!),
                info: const (
                  'Spieltag',
                  'Die Punkte aller Teilnehmer aus den Spielen dieser '
                      'Woche, laufende Spiele eingerechnet. 24 Stunden vor '
                      'dem ersten Spiel des nächsten Spieltags beginnt die '
                      'Anzeige wieder bei null.',
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _SpieltagBalken(plaetze: daten.spieltag),
            ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Kapitelmarke('Tabelle'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _Podest(
              plaetze: daten.kurztabelle,
              onTap: () => reiter(TippReiter.tabelle),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Kapitelmarke('Liga'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _LigaKacheln(
              kacheln: [
                if (round.scoring.bonusTips.isNotEmpty) ...[
                  _Kachel(
                    label: 'Bonustipps',
                    icon: Icons.emoji_events_outlined,
                    farbe: context.farben.gold,
                    onTap: () => go(BonusTipsScreen(round: round)),
                  ),
                  _Kachel(
                    label: 'Prognosen',
                    icon: Icons.leaderboard_outlined,
                    onTap: () => go(BonusTipsTableScreen(round: round)),
                  ),
                ],
                _Kachel(
                  label: 'Regeln',
                  icon: Icons.rule_outlined,
                  onTap: () => showTipRoundRules(
                    context,
                    round.scoring,
                    ref.read(selectedLeagueProvider),
                  ),
                ),
                if (!linked)
                  _Kachel(
                    label: 'Liga-Chat',
                    icon: Icons.forum_outlined,
                    neu: chatNeu,
                    onTap: () => go(TipRundenChat(round: round)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// **Die Anzeigetafel** (27.11.2026, Redesign „A + B" auf Ansage: „alles
/// eine Farbe, so grau … wenig Abwechslung"). Oben der eigene Stand wie auf
/// einer Stadiontafel — Platz in Gold, Spieltagspunkte in Grün —, darunter
/// der eine Auftrag: offene Tipps mit Fortschrittsring und goldenem Knopf.
/// Löst die „Als nächstes"-Karte und die drei Zahlen ohne Kasten ab.
class _Anzeigetafel extends StatelessWidget {
  const _Anzeigetafel({required this.daten, required this.onTippen});

  final TippUebersicht daten;
  final VoidCallback onTippen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final farben = context.farben;
    final linie = scheme.outlineVariant;
    final woche = daten.wochePunkte;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: kartenDeko(context, radius: 20),
      child: Column(
        children: [
          if (daten.rang != null)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                    Colors.transparent,
                  ],
                ),
              ),
              child: IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(
                      child: _TafelZahl(
                        titel: 'PLATZ',
                        wert: '${daten.rang}',
                        zusatz: '/${daten.mitglieder}',
                        farbe: farben.gold,
                      ),
                    ),
                    VerticalDivider(width: 1, thickness: 1, color: linie),
                    Expanded(
                      child: _TafelZahl(
                        titel: 'PUNKTE',
                        wert: '${daten.punkte}',
                      ),
                    ),
                    VerticalDivider(width: 1, thickness: 1, color: linie),
                    Expanded(
                      child: _TafelZahl(
                        titel: 'SPIELTAG',
                        wert: woche > 0 ? '+$woche' : '$woche',
                        farbe: woche > 0 ? farben.gruen : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (daten.rang != null && daten.anstehend > 0)
            Divider(height: 1, thickness: 1, color: linie),
          if (daten.anstehend > 0) _TippZeile(daten: daten, onTippen: onTippen),
        ],
      ),
    );
  }
}

class _TafelZahl extends StatelessWidget {
  const _TafelZahl({
    required this.titel,
    required this.wert,
    this.zusatz,
    this.farbe,
  });

  final String titel;
  final String wert;
  final String? zusatz;
  final Color? farbe;

  @override
  Widget build(BuildContext context) {
    final grau = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 12),
      child: Column(
        children: [
          Text(
            titel,
            style: TextStyle(
              fontSize: Schrift.label,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
              color: grau,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text.rich(
              TextSpan(
                text: wert,
                children: [
                  if (zusatz != null)
                    TextSpan(
                      text: zusatz,
                      style: TextStyle(
                        fontSize: Schrift.titel,
                        fontWeight: FontWeight.w700,
                        color: grau,
                      ),
                    ),
                ],
              ),
              style: TextStyle(
                fontSize: Schrift.anzeige,
                fontWeight: FontWeight.w900,
                height: 1.1,
                color: farbe,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Untere Zeile der Tafel: offene Tipps mit Ring. Gold, solange etwas zu tun
/// ist; ist alles getippt, grau mit leisem Knopf.
class _TippZeile extends StatelessWidget {
  const _TippZeile({required this.daten, required this.onTippen});

  final TippUebersicht daten;
  final VoidCallback onTippen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final gold = context.farben.gold;
    final offen = daten.offen;
    final getippt = daten.anstehend - offen;
    final fertig = offen == 0;
    final titel = fertig
        ? 'Alles getippt'
        : (offen == 1 ? '1 Tipp offen' : '$offen Tipps offen');
    final unter = fertig
        ? (daten.anstehend == 1
              ? 'Ein Spiel steht diese Woche noch an'
              : '${daten.anstehend} Spiele stehen diese Woche noch an')
        // Frist zuerst: Sie ist die Auskunft, den Fortschritt zeigt der Ring.
        : '${kurzeFrist(daten.frist!, DateTime.now())} · '
              '$getippt von ${daten.anstehend}';
    final farbe = fertig ? scheme.onSurfaceVariant : gold;
    return Material(
      color: fertig ? Colors.transparent : gold.withValues(alpha: 0.08),
      child: InkWell(
        onTap: onTippen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              SizedBox(
                width: 34,
                height: 34,
                child: CircularProgressIndicator(
                  value: daten.anstehend == 0 ? 1 : getippt / daten.anstehend,
                  strokeWidth: 4,
                  strokeCap: StrokeCap.round,
                  backgroundColor: scheme.onSurface.withValues(alpha: 0.1),
                  color: farbe,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: Schrift.text,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      unter,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: Schrift.label,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 38,
                child: fertig
                    ? OutlinedButton(
                        onPressed: onTippen,
                        child: const Text('Ansehen'),
                      )
                    : FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: gold,
                          foregroundColor: context.istHell
                              ? Colors.white
                              : Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          textStyle: const TextStyle(
                            fontFamily: Schrift.familie,
                            fontSize: Schrift.text,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        onPressed: onTippen,
                        child: const Text('Jetzt tippen'),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// **Der Spieltag als Balken** (27.11.2026): je Teilnehmer ein Balken im
/// Verhältnis zum Besten. Gold der Führende, Grün man selbst, sonst Grau —
/// so liest man das Rennen, ohne Zahlen zu vergleichen. Kein Kasten: man
/// kann ihn nicht antippen.
class _SpieltagBalken extends StatelessWidget {
  const _SpieltagBalken({required this.plaetze});

  final List<UebersichtPlatz> plaetze;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final farben = context.farben;
    final hoechst = plaetze.fold<int>(0, (m, p) => p.punkte > m ? p.punkte : m);
    return Column(
      children: [
        for (final p in plaetze)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 104,
                  child: Text(
                    p.ich ? 'Du' : p.mitglied.display,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: Schrift.text,
                      fontWeight: p.ich ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    height: 14,
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: FractionallySizedBox(
                      widthFactor: hoechst == 0 ? 0 : p.punkte / hoechst,
                      child: Container(
                        decoration: BoxDecoration(
                          color: p.ich
                              ? farben.gruen
                              : (p.rang == 1 && p.punkte > 0
                                    ? farben.gold
                                    : scheme.onSurface.withValues(alpha: 0.28)),
                          borderRadius: BorderRadius.circular(7),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 34,
                  child: Text(
                    '${p.punkte}',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: Schrift.text,
                      fontWeight: FontWeight.w800,
                      color: p.punkte == 0 ? scheme.onSurfaceVariant : null,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// **Die Tabelle als Podest** (27.11.2026): die ersten drei mit Bild auf
/// Stufen (2 · 1 · 3), Gold, Silber, Bronze. Steht man selbst nicht darauf,
/// folgt darunter die eigene Zeile. Die ganze Fläche führt in die Tabelle.
class _Podest extends StatelessWidget {
  const _Podest({required this.plaetze, required this.onTap});

  final List<UebersichtPlatz> plaetze;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Die Kurztabelle ist „die ersten drei, dahinter ich, falls nicht dabei".
    final oben = plaetze.take(3).toList();
    final ich = plaetze.length > 3 ? plaetze[3] : null;
    // Reihenfolge auf dem Podest: 2 · 1 · 3.
    final stufen = <(UebersichtPlatz, int)>[
      if (oben.length > 1) (oben[1], 1),
      if (oben.isNotEmpty) (oben[0], 0),
      if (oben.length > 2) (oben[2], 2),
    ];
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final (p, i) in stufen)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _Stufe(platz: p, stufe: i),
                    ),
                  ),
              ],
            ),
            if (ich != null)
              Container(
                margin: const EdgeInsets.only(top: 8),
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: kartenDeko(context, radius: 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 30,
                      child: Text(
                        '${ich.rang}.',
                        style: const TextStyle(
                          fontSize: Schrift.text,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        ich.mitglied.display,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: Schrift.text,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      '${ich.punkte} Pkt.',
                      style: TextStyle(
                        fontSize: Schrift.text,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            SizedBox(
              height: 40,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Ganze Tabelle',
                    style: TextStyle(
                      fontSize: Schrift.text,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: scheme.onSurfaceVariant,
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

class _Stufe extends StatelessWidget {
  const _Stufe({required this.platz, required this.stufe});

  final UebersichtPlatz platz;

  /// 0 = höchste Stufe (Platz 1 der Kurztabelle), 1 und 2 darunter.
  final int stufe;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final farben = context.farben;
    final medaille = switch (platz.rang) {
      1 => farben.gold,
      2 => farben.silber,
      3 => farben.bronze,
      _ => scheme.onSurfaceVariant,
    };
    final bild = const [52.0, 44.0, 40.0][stufe];
    final hoehe = const [96.0, 74.0, 58.0][stufe];
    final m = platz.mitglied;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: platz.ich ? farben.gruen : medaille,
              width: 2,
            ),
          ),
          child: AppAvatar(
            imageUrl: m.avatarUrl,
            emoji: m.avatarEmoji,
            colorHex: m.avatarColor,
            fallbackText: m.display,
            seed: m.userId,
            size: bild,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          platz.ich ? 'Du' : m.display,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: Schrift.text,
            fontWeight: platz.ich ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: hoehe,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(12),
              bottom: Radius.circular(4),
            ),
            border: Border.all(color: scheme.outlineVariant),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                medaille.withValues(alpha: stufe == 0 ? 0.28 : 0.16),
                Theme.of(context).cardColor,
              ],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${platz.rang}',
                style: TextStyle(
                  fontSize: Schrift.gross,
                  fontWeight: FontWeight.w900,
                  color: medaille,
                ),
              ),
              Text(
                '${platz.punkte} Pkt.',
                style: TextStyle(
                  fontSize: Schrift.label,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Ein Weg der Liga als Kachel.
class _Kachel {
  const _Kachel({
    required this.label,
    required this.icon,
    required this.onTap,
    this.farbe,
    this.neu = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color? farbe;
  final bool neu;
}

/// **Die Wege der Liga als Kacheln** (27.11.2026): drei je Reihe, Symbol
/// oben, Wort unten — statt einer weiteren Zeilenliste unter zwei Listen.
class _LigaKacheln extends StatelessWidget {
  const _LigaKacheln({required this.kacheln});

  final List<_Kachel> kacheln;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const proReihe = 3;
    final reihen = <List<_Kachel?>>[];
    for (var i = 0; i < kacheln.length; i += proReihe) {
      final r = <_Kachel?>[...kacheln.skip(i).take(proReihe)];
      while (r.length < proReihe) {
        r.add(null);
      }
      reihen.add(r);
    }
    return Column(
      children: [
        for (final (ri, r) in reihen.indexed)
          Padding(
            padding: EdgeInsets.only(top: ri == 0 ? 0 : 8),
            child: Row(
              children: [
                for (final (i, k) in r.indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: k == null
                        ? const SizedBox()
                        : AspectRatio(
                            aspectRatio: 1.15,
                            child: Material(
                              color: Colors.transparent,
                              child: Ink(
                                decoration: kartenDeko(context),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: k.onTap,
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              k.icon,
                                              size: 26,
                                              color:
                                                  k.farbe ??
                                                  scheme.onSurfaceVariant,
                                            ),
                                            const Spacer(),
                                            if (k.neu)
                                              Container(
                                                width: 8,
                                                height: 8,
                                                decoration: BoxDecoration(
                                                  color: context.farben.rot,
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                          ],
                                        ),
                                        FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            k.label,
                                            style: const TextStyle(
                                              fontSize: Schrift.text,
                                              fontWeight: FontWeight.w800,
                                            ),
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
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// Kapitelmarke des Spieltags mit seinen Tagen, z. B. „Spieltag · 27.–30.11."
/// — damit man sieht, welches Wochenende gerade zählt.
String spieltagTitel(TipWeek w) {
  final von = w.fixtures.first.kickoff.toLocal();
  final bis = w.fixtures.last.kickoff.toLocal();
  final tag = DateFormat('d.M.', 'de_DE');
  if (von.year == bis.year && von.month == bis.month && von.day == bis.day) {
    return 'Spieltag · ${tag.format(von)}';
  }
  final links = von.month == bis.month ? '${von.day}.' : tag.format(von);
  return 'Spieltag · $links–${tag.format(bis)}';
}
