import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/farben.dart';
import '../../../app/home_tip_status.dart' show kurzeFrist;
import '../../../app/typografie.dart';
import '../../../app/widgets/kapitelmarke.dart';
import '../../../app/widgets/karte.dart';
import '../../../app/widgets/liga_zeilen.dart';
import '../../../app/widgets/skelett.dart';
import '../../../core/models/models.dart';
import '../../auth/providers.dart';
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
    final membersAsync = ref.watch(roundMembersProvider(round.id));
    final tipsAsync = ref.watch(allRoundTipsProvider(round.id));
    final seasonAsyncs = [
      for (final id in round.competitions)
        ref.watch(leagueSeasonFixturesProvider(id)),
    ];
    final members = membersAsync.valueOrNull;
    final tips = tipsAsync.valueOrNull;
    if (members == null ||
        tips == null ||
        seasonAsyncs.any((a) => a.valueOrNull == null)) {
      final fehler = membersAsync.error ??
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
        for (final id in round.competitions) {
          ref.invalidate(leagueSeasonFixturesProvider(id));
        }
      },
      child: ListView(
        padding: const EdgeInsets.only(top: 14, bottom: 24),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (daten.anstehend > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: _AlsNaechstes(
                daten: daten,
                onTippen: () => reiter(TippReiter.tippen),
              ),
            ),
          if (daten.rang != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
              child: _Stand(daten: daten),
            ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Kapitelmarke('Tabelle'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: _Kurztabelle(
              plaetze: daten.kurztabelle,
              onTap: () => reiter(TippReiter.tabelle),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Kapitelmarke('Liga'),
          ),
          Zeilengruppe([
            if (round.scoring.bonusTips.isNotEmpty) ...[
              LigaZeile(
                label: 'Bonustipps',
                icon: Icons.emoji_events_outlined,
                hinweis: 'Saison-Prognosen',
                onTap: () => go(BonusTipsScreen(round: round)),
              ),
              LigaZeile(
                label: 'Bonustipp-Tabelle',
                icon: Icons.leaderboard_outlined,
                hinweis: 'Die Prognosen aller Mitglieder',
                onTap: () => go(BonusTipsTableScreen(round: round)),
              ),
            ],
            LigaZeile(
              label: 'Regeln & Punkte',
              icon: Icons.rule_outlined,
              hinweis: 'Wie viele Punkte welcher Tipp bringt',
              onTap: () => showTipRoundRules(
                context,
                round.scoring,
                ref.read(selectedLeagueProvider),
              ),
            ),
            if (!linked)
              LigaZeile(
                label: 'Liga-Chat',
                icon: Icons.forum_outlined,
                hinweis: chatNeu ? 'Neue Nachrichten' : null,
                onTap: () => go(TipRundenChat(round: round)),
              ),
          ]),
        ],
      ),
    );
  }
}

/// Der eine Auftrag: offene Tipps der Woche. Gold, weil etwas zu tun ist —
/// ist alles getippt, bleibt die Karte, aber ohne Gold und mit leiserem Knopf.
class _AlsNaechstes extends StatelessWidget {
  const _AlsNaechstes({required this.daten, required this.onTippen});

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
        : kurzeFrist(daten.frist!, DateTime.now());

    // Kompakt (10.11.2026, auf Ansage: „ein bisschen kleiner"): Titel und
    // Knopf in einer Zeile, darunter Fortschritt und Frist in einer Zeile.
    // Vorher gut 200 Punkte hoch mit Knopf über die volle Breite.
    return Container(
      decoration: kartenDeko(context, hauch: fertig ? null : gold, radius: 16),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ALS NÄCHSTES',
                      style: TextStyle(
                        fontSize: Schrift.label,
                        fontWeight: Schrift.ueberschriftGewicht,
                        fontStyle: Schrift.ueberschriftStil,
                        letterSpacing: 1,
                        color: fertig ? scheme.onSurfaceVariant : gold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      titel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: Schrift.titel,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 40,
                child: fertig
                    ? OutlinedButton(
                        onPressed: onTippen,
                        child: const Text('Ansehen'),
                      )
                    : FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: gold,
                          foregroundColor:
                              context.istHell ? Colors.white : Colors.black,
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
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: daten.anstehend == 0 ? 1 : getippt / daten.anstehend,
              minHeight: 3,
              backgroundColor: scheme.onSurface.withValues(alpha: 0.1),
              color: fertig ? scheme.onSurfaceVariant : gold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            fertig ? unter : '$getippt von ${daten.anstehend} getippt · $unter',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: Schrift.label,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Der eigene Stand als drei Zahlen — ohne Kasten, weil man ihn nicht
/// antippen kann (Regel „Karten nur für Tipp-Ziele").
class _Stand extends StatelessWidget {
  const _Stand({required this.daten});

  final TippUebersicht daten;

  @override
  Widget build(BuildContext context) {
    final woche = daten.wochePunkte;
    return Row(
      children: [
        Expanded(
          child: _Zahl(
            wert: '${daten.rang}.',
            text: 'von ${daten.mitglieder}',
          ),
        ),
        Expanded(child: _Zahl(wert: '${daten.punkte}', text: 'Punkte')),
        Expanded(
          child: _Zahl(
            wert: woche > 0 ? '+$woche' : '$woche',
            text: 'diese Woche',
            farbe: woche > 0 ? context.farben.gruen : null,
          ),
        ),
      ],
    );
  }
}

class _Zahl extends StatelessWidget {
  const _Zahl({required this.wert, required this.text, this.farbe});

  final String wert;
  final String text;
  final Color? farbe;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          wert,
          style: TextStyle(
            fontSize: Schrift.gross,
            fontWeight: FontWeight.w900,
            color: farbe,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          text,
          style: TextStyle(
            fontSize: Schrift.label,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Die ersten drei und man selbst. Die ganze Karte führt in den
/// Tabellen-Reiter — dort steht alles, hier nur, wo man steht.
class _Kurztabelle extends StatelessWidget {
  const _Kurztabelle({required this.plaetze, required this.onTap});

  final List<UebersichtPlatz> plaetze;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final linie = Divider(
      height: 1,
      color: scheme.onSurface.withValues(alpha: 0.07),
    );
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: kartenDeko(context),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Column(
            children: [
              for (final (i, p) in plaetze.indexed) ...[
                if (i > 0) linie,
                Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  color: p.ich
                      ? scheme.onSurface.withValues(alpha: 0.05)
                      : null,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 26,
                        child: Text(
                          '${p.rang}',
                          style: TextStyle(
                            fontSize: Schrift.text,
                            fontWeight: FontWeight.w700,
                            color: p.rang == 1
                                ? context.farben.gold
                                : scheme.onSurfaceVariant,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          p.mitglied.display,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: Schrift.text,
                            fontWeight:
                                p.ich ? FontWeight.w800 : FontWeight.w500,
                          ),
                        ),
                      ),
                      Text(
                        '${p.punkte}',
                        style: const TextStyle(
                          fontSize: Schrift.text,
                          fontWeight: FontWeight.w800,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              linie,
              SizedBox(
                height: 42,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Ganze Tabelle',
                          style: TextStyle(
                            fontSize: Schrift.text,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurfaceVariant,
                          ),
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}
