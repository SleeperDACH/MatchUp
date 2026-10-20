/// **Kopf und Übersicht des Spielerprofils nach dem Vorbild Sleeper**
/// (19.10.2026, auf Ansage mit Screenshot).
///
/// Der Kopf trägt, was man auf einen Blick wissen will: links groß das Wappen
/// (Spielerfotos gibt es nicht), darunter Verein und Position; rechts wem er
/// gehört, der Name in schrägen Versalien, drei Kennzahlen und die Knöpfe.
/// Der Reiter „Übersicht" davor fasst zusammen, was vorher über vier Reiter
/// verstreut war: Rang, letzte Leistung, letztes Spiel, die nächsten
/// Spieltage mit Prognose.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/typografie.dart';
import '../../../app/widgets/kapitelmarke.dart';
import '../../../app/widgets/karte.dart';
import '../../../app/widgets/punktzahl.dart';
import '../../../core/logic/vereins_kuerzel.dart';
import '../../../core/models/models.dart';
import '../../../core/util/club_colors.dart';
import '../logic/fantasy_scoring_engine.dart';
import '../logic/naechstes_spiel.dart';
import '../logic/saison_punkte.dart';
import '../logic/spieler_schnitt.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';
import '../../tippspiel/ui/team_badge.dart';
import 'club_badge.dart';
import 'punkte_aufschluesselung.dart';

const _versalSchraeg = TextStyle(
  fontWeight: Schrift.ueberschriftGewicht,
  fontStyle: Schrift.ueberschriftStil,
  color: Colors.white,
  height: 1.05,
);

/// Der Kopf: Wappen links, Name und Kennzahlen rechts, Knöpfe darunter.
class SpielerProfilKopf extends StatelessWidget {
  const SpielerProfilKopf({
    super.key,
    required this.player,
    required this.clubIcon,
    required this.alter,
    required this.besitzer,
    required this.schnitt,
    required this.aktionen,
  });

  final FantasyPlayer player;
  final String? clubIcon;
  final int alter;

  /// „→ Teamname", „Dein Kader" oder „Free Agent".
  final String besitzer;
  final SpielerSchnitt? schnitt;
  final List<Widget> aktionen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ton = vereinsTon(player.club);
    final teile = player.name.trim().split(' ');
    final nachname = teile.last;
    final vorname = teile.length > 1
        ? teile.sublist(0, teile.length - 1).join(' ')
        : '';
    final s = schnitt;

    return Container(
      // Ein Schimmer in der Vereinsfarbe von links — derselbe Gedanke wie die
      // Seitentönung der Kopfkarte auf dem Startbildschirm.
      decoration: BoxDecoration(
        gradient: ton == null
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: const Alignment(0.3, 0.6),
                colors: [ton.withValues(alpha: 0.32), Colors.transparent],
              ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Column(
              children: [
                ClubBadge(club: player.club, iconUrl: clubIcon, size: 80),
                const SizedBox(height: 10),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    vereinsKurzname(player.club).toUpperCase(),
                    style: _versalSchraeg.copyWith(fontSize: Schrift.titel),
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Die Position als Punkt in ihrer Farbe — Farbe als
                    // Akzent, nicht als Fläche.
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: positionColor(player.position),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${player.position.short} · ${vereinsKuerzel(player.club)}',
                      style: TextStyle(
                        fontSize: Schrift.label,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  besitzer,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: Schrift.label,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                if (vorname.isNotEmpty)
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      vorname.toUpperCase(),
                      style: _versalSchraeg.copyWith(fontSize: Schrift.titel),
                    ),
                  ),
                // Schrumpfen statt kappen — „SCHLOTTERBECK" in 230 Punkten.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    nachname.toUpperCase(),
                    style: _versalSchraeg.copyWith(fontSize: Schrift.gross),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _Kennzahl(titel: 'Alter', wert: '$alter'),
                    _Kennzahl(
                      titel: 'Ø',
                      wert: s == null || s.punkteJeEinsatz == null
                          ? '–'
                          : formatPoints(s.punkteJeEinsatz!),
                    ),
                    _Kennzahl(
                      titel: 'Einsätze',
                      wert: s == null ? '–' : '${s.einsaetze}',
                    ),
                  ],
                ),
                if (aktionen.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Row(children: aktionen),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Kennzahl extends StatelessWidget {
  const _Kennzahl({required this.titel, required this.wert});

  final String titel;
  final String wert;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titel.toUpperCase(),
          style: TextStyle(
            fontSize: Schrift.mikro,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            wert,
            style: const TextStyle(
              fontSize: Schrift.titel,
              fontWeight: FontWeight.w800,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    ),
  );
}

/// Der Reiter „Übersicht": Rang, letzte Leistung, letztes Spiel, Prognose.
class SpielerUebersicht extends ConsumerWidget {
  const SpielerUebersicht({
    super.key,
    required this.league,
    required this.player,
    required this.clubIcon,
    required this.saison,
    required this.spiele,
  });

  final FantasyLeague league;
  final FantasyPlayer player;
  final String? clubIcon;

  /// Spieltag → Spieler → Stats, wie im Leistungsreiter (mit laufender Runde).
  final Map<int, Map<String, PlayerMatchStats>> saison;
  final List<Fixture> spiele;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pool =
        ref.watch(playerPoolProvider).valueOrNull ?? const <FantasyPlayer>[];
    final abgepfiffen = ref.watch(abgepfiffeneRundenProvider);
    final schnitt = spielerSchnitt(
      saison: saison,
      spielerId: player.id,
      position: player.position,
      regeln: league.scoring,
    );

    // Rang nach Saisonpunkten — in der Position und über alle.
    final nachId = {for (final p in pool) p.id: p};
    final punkte = saisonPunkte(
      saison: saison,
      spieler: nachId,
      regeln: league.scoring,
    );
    int? rang(bool nurPosition) {
      final eigene = punkte[player.id];
      if (eigene == null) return null;
      var vor = 0;
      for (final MapEntry(key: id, value: wert) in punkte.entries) {
        if (nurPosition && nachId[id]?.position != player.position) continue;
        if (wert > eigene) vor++;
      }
      return vor + 1;
    }

    final rangPos = rang(true);
    final rangAlle = rang(false);

    // Letzter Spieltag mit Daten für ihn — sonst der letzte gewertete.
    final runden = saison.keys.toList()..sort();
    final letzte =
        runden.reversed
            .where((r) => (saison[r]?[player.id]?.minutes ?? 0) > 0)
            .firstOrNull ??
        runden.lastOrNull;

    // Die nächsten drei Spieltage, die noch nicht abgepfiffen sind.
    final alleRunden = {for (final f in spiele) f.round}.toList()..sort();
    final kommende = [
      for (final r in alleRunden)
        if (!abgepfiffen.contains(r) && !saison.containsKey(r)) r,
    ].take(3).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Block(
              titel: 'Rang',
              werte: [
                ('#${rangPos ?? '–'}', player.position.short),
                ('#${rangAlle ?? '–'}', 'Gesamt'),
              ],
            ),
            _Block(
              titel: 'Saison',
              werte: [
                (
                  punkte[player.id] == null
                      ? '–'
                      : formatPoints(punkte[player.id]!),
                  'Punkte',
                ),
              ],
            ),
            _Block(
              titel: 'Ø',
              werte: [
                (
                  schnitt.punkteJeEinsatz == null
                      ? '–'
                      : formatPoints(schnitt.punkteJeEinsatz!),
                  'je Einsatz',
                ),
              ],
            ),
          ],
        ),
        if (letzte != null) ...[
          const Kapitelmarke('Leistung'),
          _LeistungKarte(
            league: league,
            player: player,
            clubIcon: clubIcon,
            runde: letzte,
            stats: saison[letzte]?[player.id],
          ),
          if (_spielDesVereins(spiele, letzte, player.club) case final f?) ...[
            const SizedBox(height: 10),
            _SpielKarte(runde: letzte, spiel: f, verein: player.club),
          ],
        ],
        // **Spielplan statt Prognose** (19.10.2026, auf Ansage): nur die
        // nächsten Gegner. Die Prognose je Spieltag war eine einzige Zahl
        // (der Schnitt) in drei Kästen.
        if (kommende.isNotEmpty) ...[
          const Kapitelmarke('Spielplan'),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: kommende.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) => _GegnerKarte(
                runde: kommende[i],
                spiel: _spielDesVereins(spiele, kommende[i], player.club),
                verein: player.club,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Das Spiel seines Vereins an einem Spieltag — über die kanonische Form,
/// weil Kader und Spielplan denselben Verein verschieden schreiben (0108).
Fixture? _spielDesVereins(List<Fixture> spiele, int runde, String club) {
  final meiner = vereinKanonisch(club);
  for (final f in spiele) {
    if (f.round != runde) continue;
    if (vereinKanonisch(f.home.name) == meiner ||
        vereinKanonisch(f.away.name) == meiner) {
      return f;
    }
  }
  return null;
}

/// Eine Kennzahlengruppe: kleine Überschrift, darunter Wert und Beschriftung.
class _Block extends StatelessWidget {
  const _Block({required this.titel, required this.werte});

  final String titel;
  final List<(String, String)> werte;

  @override
  Widget build(BuildContext context) {
    final grau = Theme.of(context).colorScheme.onSurfaceVariant;
    final klein = TextStyle(
      fontSize: Schrift.label,
      fontWeight: FontWeight.w700,
      letterSpacing: 1,
      color: grau,
    );
    return Expanded(
      flex: werte.length,
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titel.toUpperCase(), style: klein),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final (wert, unter) in werte)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            wert,
                            style: const TextStyle(
                              fontSize: Schrift.gross,
                              fontWeight: FontWeight.w800,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                        Text(
                          unter.toUpperCase(),
                          style: klein.copyWith(fontSize: Schrift.mikro),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Die kleine Marke oben links in einer Karte („SPIELTAG 6").
class _Marke extends StatelessWidget {
  const _Marke(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TextStyle(
      fontSize: Schrift.label,
      fontWeight: Schrift.ueberschriftGewicht,
      fontStyle: Schrift.ueberschriftStil,
      letterSpacing: 1,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

/// Was er am Spieltag gemacht hat — Tipp öffnet die Aufschlüsselung.
class _LeistungKarte extends StatelessWidget {
  const _LeistungKarte({
    required this.league,
    required this.player,
    required this.clubIcon,
    required this.runde,
    required this.stats,
  });

  final FantasyLeague league;
  final FantasyPlayer player;
  final String? clubIcon;
  final int runde;
  final PlayerMatchStats? stats;

  /// „90' · 1 Tor · 2 Vorlagen · Gelb" — nur, was vorkam.
  static String zeile(PlayerMatchStats s, PlayerPosition pos) {
    String n(int z, String eins, String mehr) =>
        z == 1 ? '1 $eins' : '$z $mehr';
    return [
      "${s.minutes}'",
      if (s.goals > 0) n(s.goals, 'Tor', 'Tore'),
      if (s.assists > 0) n(s.assists, 'Vorlage', 'Vorlagen'),
      if (pos == PlayerPosition.gk && s.saves > 0)
        n(s.saves, 'Parade', 'Paraden'),
      if (s.cleanSheet &&
          (pos == PlayerPosition.gk || pos == PlayerPosition.def))
        'zu Null',
      if (s.red > 0 || s.secondYellow > 0) 'Rot' else if (s.yellow > 0) 'Gelb',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = stats;
    final gespielt = s != null && s.minutes > 0;
    final punkte = s == null
        ? null
        : scorePlayer(s, player.position, league.scoring);
    return Karte(
      onTap: s == null
          ? null
          : () => zeigePunkteAufschluesselung(
              context,
              titel: '${player.name} · $runde. Spieltag',
              score: scorePlayerDetailed(s, player.position, league.scoring),
              gespielt: s.hasContribution,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Marke('Spieltag $runde'),
          const SizedBox(height: 10),
          Row(
            children: [
              ClubBadge(club: player.club, iconUrl: clubIcon, size: 34),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  gespielt ? zeile(s, player.position) : 'Nicht eingesetzt',
                  style: TextStyle(
                    fontSize: Schrift.text,
                    fontWeight: FontWeight.w600,
                    color: gespielt ? null : scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (gespielt && punkte != null) ...[
                const SizedBox(width: 8),
                Punktzahl(
                  punkte,
                  negativRot: true,
                  stil: const TextStyle(
                    fontSize: Schrift.gross,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  'Pkt',
                  style: TextStyle(
                    fontSize: Schrift.label,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Das Spiel seines Vereins an dem Spieltag: beide Vereine und der Stand.
/// Wappen kommen aus dem Spielplan selbst (`TeamRef.iconUrl`).
class _SpielKarte extends StatelessWidget {
  const _SpielKarte({
    required this.runde,
    required this.spiel,
    required this.verein,
  });

  final int runde;
  final Fixture spiel;
  final String verein;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final zustand = switch (spiel.status) {
      FixtureStatus.finished => 'Ende',
      FixtureStatus.live => 'Live',
      _ => anpfiffKurz(spiel.kickoff),
    };
    final meiner = vereinKanonisch(verein);

    Widget zeile(TeamRef team, int? tore) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          TeamBadge(team: team, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              vereinsKurzname(team.name),
              style: TextStyle(
                fontSize: Schrift.titel,
                fontWeight: vereinKanonisch(team.name) == meiner
                    ? FontWeight.w800
                    : FontWeight.w500,
              ),
            ),
          ),
          Text(
            tore == null ? '–' : '$tore',
            style: const TextStyle(
              fontSize: Schrift.titel,
              fontWeight: FontWeight.w800,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );

    return Karte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Marke('Spieltag $runde'),
              const Spacer(),
              Text(
                zustand.toUpperCase(),
                style: TextStyle(
                  fontSize: Schrift.label,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                  color: spiel.status == FixtureStatus.live
                      ? scheme.error
                      : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          zeile(spiel.home, spiel.homeScore),
          zeile(spiel.away, spiel.awayScore),
        ],
      ),
    );
  }
}

/// Ein kommender Spieltag: Wappen und Name des Gegners, dazu der Anstoß.
class _GegnerKarte extends StatelessWidget {
  const _GegnerKarte({
    required this.runde,
    required this.spiel,
    required this.verein,
  });

  final int runde;
  final Fixture? spiel;
  final String verein;

  @override
  Widget build(BuildContext context) {
    final grau = Theme.of(context).colorScheme.onSurfaceVariant;
    final f = spiel;
    final heim =
        f != null && vereinKanonisch(f.home.name) == vereinKanonisch(verein);
    final gegner = f == null ? null : (heim ? f.away : f.home);
    return SizedBox(
      width: 112,
      child: Karte(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Marke('ST $runde'),
            const SizedBox(height: 6),
            if (gegner == null)
              Text('spielfrei', style: TextStyle(color: grau))
            else ...[
              Row(
                children: [
                  TeamBadge(team: gegner, size: 22),
                  const SizedBox(width: 6),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${heim ? '' : '@ '}${vereinsKurzname(gegner.name)}',
                        style: const TextStyle(
                          fontSize: Schrift.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                anpfiffKurz(f!.kickoff),
                style: TextStyle(fontSize: Schrift.label, color: grau),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
