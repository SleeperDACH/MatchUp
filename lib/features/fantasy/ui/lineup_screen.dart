import 'dart:async';

import 'package:flutter/material.dart';
import '../../../app/widgets/skelett.dart';
import '../../../app/widgets/kapitelmarke.dart';
import 'meine_picks.dart';
import '../logic/wechsel_mit_formation.dart';
import 'package:flutter/services.dart';

import '../../../app/theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/typografie.dart';
import '../../../app/widgets/pill_selector.dart';
import '../../../app/widgets/punktzahl.dart';

import '../logic/spieler_schnitt.dart';
import '../../../core/models/models.dart';
import '../../auth/providers.dart';
import '../logic/fantasy_scoring_engine.dart';
import '../logic/naechstes_spiel.dart';
import '../logic/aufstellung_sperre.dart';
import '../logic/aufstellung_uebernahme.dart';
import '../logic/formation_umbau.dart';
import '../logic/lineup_autosave.dart';
import '../logic/projektion.dart';
import '../data/fantasy_league_repository.dart';
import '../models/fantasy_models.dart';
import '../models/player_absence.dart';
import '../providers.dart';
import 'ausfall_zeichen.dart';
import 'club_badge.dart';
import 'spiel_marke.dart';
import 'free_agency_screen.dart';
import 'pitch_painter.dart';
import 'player_profile_sheet.dart';
import '../logic/formation_luecke.dart';
import '../logic/formation_fuer_elf.dart';

/// Aufstellung als Fußballfeld: Startelf je Spieltag visuell auf dem Platz
/// wählen. Oben Chips für gültige Formationen (flexibel, Min/Max je Position
/// aus der Kader-Konfiguration); Tippen auf eine Position öffnet die Liste der
/// verfügbaren Spieler **derselben Position** (ein Stürmer kann nicht in die
/// Abwehr). Vor Anstoß änderbar, danach gesperrt. Ohne gespeicherte
/// Aufstellung zählt die automatische beste Elf.
/// Eigenständiger Aufstellungs-Screen (Editor mit AppBar).
class LineupScreen extends StatelessWidget {
  const LineupScreen({super.key, required this.league});

  final FantasyLeague league;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Aufstellung')),
      body: SingleChildScrollView(child: LineupEditor(league: league)),
    );
  }
}

/// Einbettbarer Aufstellungs-Editor (Platz + Formation + Speichern) ohne
/// eigenes Scaffold — steht im Kader-Tab auch unter weiteren Inhalten und
/// wird vom umgebenden Screen gescrollt.
class LineupEditor extends ConsumerStatefulWidget {
  const LineupEditor({super.key, required this.league});

  final FantasyLeague league;

  @override
  ConsumerState<LineupEditor> createState() => _LineupEditorState();
}

/// Reihenfolge auf dem Platz: Sturm oben, Torwart unten.
const _pitchOrder = [
  PlayerPosition.fwd,
  PlayerPosition.mid,
  PlayerPosition.def,
  PlayerPosition.gk,
];

class _LineupEditorState extends ConsumerState<LineupEditor> {
  /// Aufstellung als feste Slot-Listen je Position (Länge = Formation),
  /// Einträge können leer (null) sein. null = noch ungespeicherte Saat zeigen.
  Map<PlayerPosition, List<String?>>? _slots;
  bool _saving = false;

  List<String> _lastIds = const [];
  bool _valid = false;

  /// Spieltag, für den gespeichert wird — `null`, solange er noch lädt.
  ///
  /// Vorher war das ein `int` und bekam im `build` den Wert `round`, der
  /// seinerseits aus `current ?? 34` kam. Wer seine Elf zog, bevor
  /// `fantasyCurrentRoundProvider` geantwortet hatte, speicherte sie damit auf
  /// **Spieltag 34** — angenommen vom Server, unsichtbar für Spieltag 1, keine
  /// Fehlermeldung. In `fantasy_lineups` steht genau so eine Zeile (07.07.).
  /// Der Schirm rendert nämlich, sobald der *Pool* da ist; auf den Spieltag
  /// wartet er nicht.
  int? _effRound;
  Timer? _saveTimer;

  /// Es gibt eine Änderung, die noch nicht beim Server angekommen ist.
  ///
  /// Ohne diese Merkung log die Fußzeile: Sie zeigte „automatisch
  /// gespeichert", während in Wahrheit noch ein Timer lief, ein Speichern
  /// unterwegs war — oder gar nichts passieren konnte, weil die Elf
  /// unvollständig war.
  bool _dirty = false;

  /// Wie oft das Speichern hintereinander gescheitert ist (0 = alles gut).
  ///
  /// Steuert den Abstand des nächsten Versuchs und die Fußzeile. Vorher gab es
  /// das nicht: Ein Fehlschlag zeigte eine Snackbar, und danach passierte
  /// **nichts mehr** — der einzige Ausgang des Auto-Speichers ohne zweiten
  /// Versuch.
  int _fehlversuche = 0;

  /// Für den Flush in [dispose] festgehalten: `ref` ist dann nicht mehr
  /// verlässlich zu benutzen.
  FantasyLeagueRepository? _repo;

  /// Ebenso für den Flush: Nach dem Abschicken muss die Liste der
  /// Aufstellungen neu geholt werden, und `ref` gibt es dann nicht mehr.
  ProviderContainer? _container;

  /// Spieler, deren Spiel schon läuft — im `build` gesetzt, damit der
  /// Spielerwahl-Dialog sie nicht anbietet. Ein gesperrter Spieler im Dialog
  /// wäre ein Angebot, das der Server anschließend ablehnt.
  Set<String> _gesperrt = const {};
  Map<String, String?> _clubIcons = const {};

  RosterConfig get _roster => widget.league.roster;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(fantasyLeagueRepositoryProvider);
    _container = ProviderScope.containerOf(context, listen: false);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    // Offene Änderung noch abschicken. Vorher hat `cancel()` sie verworfen:
    // Wer den letzten Spieler zog und innerhalb der 700 ms Verzögerung
    // zurücktippte, verlor die Aufstellung wortlos — und die Fußzeile hatte
    // ihm gerade versprochen, dass automatisch gespeichert wird. Ohne await
    // und ohne Rückmeldung; der Schirm ist weg, aber der Aufruf läuft.
    if (_dirty && _valid && _effRound != null) {
      unawaited(
        _repo!
            .setLineup(widget.league.id, _effRound!, _lastIds)
            .then((_) => _container?.invalidate(
                  leagueLineupsProvider(widget.league.id),
                ))
            .catchError((Object e) => debugPrint('[AUFSTELLUNG] Flush: $e')),
      );
    }
    super.dispose();
  }

  /// Änderungen automatisch speichern, sobald die Aufstellung gültig ist —
  /// kein extra Speichern-Button nötig.
  ///
  /// [sofort] für **Wechsel** (Spielerwahl, Ziehen aufs Feld, Ziehen auf die
  /// Bank): Gewünscht nach dem letzten Spieltag — *„Bitte so umbauen, dass,
  /// wenn ein Spieler eingewechselt wird, die Aufstellung gespeichert wird."*
  /// Die 700 ms Verzögerung sind für einen Wechsel die falsche Größe: Wer
  /// tauscht und sofort den Schirm verlässt oder in ein Funkloch fährt, hat
  /// eine Aufstellung gesehen, die es nirgends gibt.
  ///
  /// Ohne [sofort] bleibt es beim Sammeln — für den Formationswechsel, bei
  /// dem man sich durch die Auswahl tippt.
  ///
  /// **Nicht direkt, sondern nach dem nächsten Bild.** `_valid` und `_lastIds`
  /// entstehen im `build`; unmittelbar nach `setState` stehen dort noch die
  /// Werte von *vor* dem Zug. Genau davon lebte die alte Verzögerung, ohne
  /// dass es irgendwo stand.
  void _autoSave({bool sofort = false}) {
    _dirty = true;
    _fehlversuche = 0; // neue Änderung, neuer Anlauf
    _saveTimer?.cancel();
    if (sofort) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _versuchenZuSpeichern(),
      );
      return;
    }
    _saveTimer = Timer(
      const Duration(milliseconds: 700),
      _versuchenZuSpeichern,
    );
  }

  /// Ein Speicherversuch, der sich selbst noch einmal einbestellt, statt
  /// aufzugeben.
  ///
  /// Beide Abbrüche hier waren vorher endgültig und stumm:
  ///  * **Läuft schon ein Speichern**, wurde die *neuere* Änderung fallen
  ///    gelassen. Zwei Züge kurz hintereinander — der zweite kam nie an.
  ///  * **Ist die Elf unvollständig**, passiert nichts. Das ist richtig (der
  ///    Server nähme sie ohnehin nicht), aber es muss drüberstehen; sonst
  ///    füllt jemand zehn von elf Plätzen, liest „wird automatisch
  ///    gespeichert" und geht.
  void _versuchenZuSpeichern() {
    if (!mounted) return;
    switch (naechsterSpeicherSchritt(
      gueltig: _valid,
      laeuftGerade: _saving,
      spieltag: _effRound,
    )) {
      case SpeicherSchritt.spaeterErneut:
        _saveTimer = Timer(
          const Duration(milliseconds: 400),
          _versuchenZuSpeichern,
        );
      case SpeicherSchritt.unvollstaendig:
        setState(() {}); // Fußzeile sagt, dass nichts gespeichert ist.
      case SpeicherSchritt.speichern:
        _save(_effRound!, _lastIds);
    }
  }

  /// Spielerprofil (Leistungstabelle + Droppen) öffnen.
  void _openProfile(FantasyPlayer p) => showPlayerProfile(
    context,
    league: widget.league,
    player: p,
    clubIcon: _clubIcons[p.club],
    isMine: true,
  );

  /// Leeren Kaderplatz füllen → Free Agency.
  void _openFreeAgency() => Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => FreeAgencyScreen(league: widget.league)),
  );

  /// Alle aktuell aufgestellten Spieler-IDs (über alle Positionen).
  Set<String> _assignedIds(Map<PlayerPosition, List<String?>> slots) => {
    for (final list in slots.values)
      for (final id in list) ?id,
  };

  /// Slots für eine Formation bauen — **nur** mit Spielern aus [prefer]
  /// (gespeicherte bzw. übernommene Elf, sonst die beste Elf als Saat).
  ///
  /// **Eine Lücke bleibt leer** (17.10.2026, live gemeldet). Vorher füllte
  /// diese Funktion jede freie Stelle mit dem nächsten Bankspieler auf. Nach
  /// einem Drop (Potulski raus, Uduokhai rein) hatte die gespeicherte Elf zehn
  /// Spieler — und auf dem Schirm stand auf dem freien Platz Mario Götze, der
  /// nie aufgestellt war und dessen Spiel schon lief. Er punktete nicht (der
  /// Server kannte ihn nicht), ließ sich nicht entfernen (gesperrt), und jede
  /// weitere Änderung scheiterte am Server, weil sie ihn nachträglich in die
  /// Elf geschrieben hätte. **Wer auf dem Feld steht, entscheidet der Manager,
  /// nicht der Schirm.**
  Map<PlayerPosition, List<String?>> _buildSlots(
    (int, int, int) formation,
    Set<String> prefer,
    Map<PlayerPosition, List<FantasyPlayer>> byPos,
  ) {
    final counts = {
      PlayerPosition.gk: _roster.gk,
      PlayerPosition.def: formation.$1,
      PlayerPosition.mid: formation.$2,
      PlayerPosition.fwd: formation.$3,
    };
    final res = <PlayerPosition, List<String?>>{};
    counts.forEach((pos, n) {
      final ordered = byPos[pos] ?? const <FantasyPlayer>[];
      final pick = [
        for (final p in ordered)
          if (prefer.contains(p.id)) p.id,
      ].take(n).toList();
      res[pos] = [for (var i = 0; i < n; i++) i < pick.length ? pick[i] : null];
    });
    return res;
  }

  (int, int, int) _formationOf(Map<PlayerPosition, List<String?>> slots) => (
    slots[PlayerPosition.def]?.length ?? 0,
    slots[PlayerPosition.mid]?.length ?? 0,
    slots[PlayerPosition.fwd]?.length ?? 0,
  );

  Future<void> _save(int round, List<String> ids) async {
    setState(() => _saving = true);
    try {
      await ref
          .read(fantasyLeagueRepositoryProvider)
          .setLineup(widget.league.id, round, ids);
      // Nur bei Erfolg: Ein Fehlschlag lässt die Änderung offen, damit der
      // Flush in dispose sie noch mitnimmt.
      _dirty = false;
      _fehlversuche = 0;
      // **Den gespeicherten Stand frisch holen, nicht auf Realtime warten.**
      // Kommt das Ereignis nicht an (abgerissener Kanal), zeigten MatchUp-Tab
      // und der wiedergeöffnete Schirm sonst die alte Elf, obwohl hier
      // „Gespeichert" stand. Die Auswahl auf diesem Schirm (`_slots`) bleibt
      // dabei unangetastet.
      if (mounted) ref.invalidate(leagueLineupsProvider(widget.league.id));
    } catch (e) {
      if (mounted) {
        _fehlversuche++;
        // **Noch einmal versuchen.** Das war die Lücke hinter „häufiger
        // Speicherprobleme": Ein Netzfehler zeigte eine Snackbar und war
        // fertig. Die Änderung blieb offen (`_dirty`), aber niemand nahm sie
        // je wieder auf — außer zufällig der nächste Zug.
        _saveTimer?.cancel();
        _saveTimer = Timer(
          wartezeitNachFehler(_fehlversuche),
          _versuchenZuSpeichern,
        );
        // Nur beim ersten Mal laut. Danach trägt die Fußzeile den Zustand;
        // eine Snackbar je Versuch wäre Lärm über einem Schirm, an dem man
        // gerade arbeitet.
        if (_fehlversuche == 1) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Speichern fehlgeschlagen: $e — versuche es '
                  'weiter.'),
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final league = widget.league;
    // **Nicht der angezeigte Spieltag, sondern der aufzustellende.** Ist die
    // Runde durch, plant man hier schon die nächste — während Übersicht und
    // MatchUp-Tab die Abrechnung noch 24 Stunden stehen lassen.
    final current = ref.watch(fantasyAufstellungsRundeProvider).valueOrNull;
    final round = current ?? 34;

    final poolAsync = ref.watch(playerPoolProvider);
    final roster =
        ref.watch(leagueRosterProvider(league.id)).valueOrNull ??
        const <RosterEntry>[];
    final lineups =
        ref.watch(leagueLineupsProvider(league.id)).valueOrNull ??
        const <FantasyLineup>[];
    final statsAsync = ref.watch(roundStatsProvider(round));
    final clubIcons =
        ref.watch(clubIconsProvider).valueOrNull ?? const <String, String?>{};
    final myId = ref.watch(currentUserProvider)?.id;

    // Anpfiff je Verein für diesen Spieltag — daraus ergibt sich die Sperre
    // **je Spieler** (Migration 0084). `deadline` bleibt für die Auskunft
    // „ab wann geht gar nichts mehr" in der Fußzeile.
    final anpfiff = anpfiffJeVerein(
      ref.watch(fantasySeasonFixturesProvider).valueOrNull ?? const [],
      round,
    );
    final jetzt = DateTime.now();

    return poolAsync.when(
      loading: () => const SizedBox(
        height: 320,
        child: Skelett(),
      ),
      error: (e, _) =>
          SizedBox(height: 320, child: Center(child: Text('Fehler: $e'))),
      data: (pool) {
        final playerById = {for (final p in pool) p.id: p};
        final myPlayers = [
          for (final r in roster)
            if (r.managerId == myId && playerById[r.playerId] != null)
              playerById[r.playerId]!,
        ];
        final stats =
            statsAsync.valueOrNull ?? const <String, PlayerMatchStats>{};
        final points = {
          for (final p in myPlayers)
            p: scorePlayer(
              stats[p.id] ?? const PlayerMatchStats(),
              p.position,
              league.scoring,
            ),
        };
        // Spieler je Position, nach Punkten absteigend (für Auto-Fill/Listen).
        final byPos = <PlayerPosition, List<FantasyPlayer>>{};
        for (final p in myPlayers) {
          byPos.putIfAbsent(p.position, () => []).add(p);
        }
        for (final list in byPos.values) {
          list.sort((a, b) => (points[b] ?? 0).compareTo(points[a] ?? 0));
        }

        if (myPlayers.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Noch kein Kader — der Draft muss erst laufen.',
              textAlign: TextAlign.center,
            ),
          );
        }

        // Wer schon spielt, ist festgenagelt.
        final gesperrt = {
          for (final p in myPlayers)
            if (spielerGesperrt(p, anpfiff, jetzt)) p.id,
        };
        // Alles zu: Für den Rest des Spieltags gibt es nichts mehr zu tun.
        final allesZu =
            myPlayers.isNotEmpty && gesperrt.length == myPlayers.length;
        _gesperrt = gesperrt;

        // **Saat: dieser Spieltag, sonst der letzte gestellte, sonst die
        // beste Elf.** Die Regel steht in `logic/aufstellung_uebernahme.dart`
        // und spiegelt die des Servers (0110) — beide müssen dasselbe meinen,
        // sonst springt die Aufstellung um, sobald dessen Lauf durch ist.
        final seedIds =
            uebernommeneElf(lineups.where((l) => l.managerId == myId), round, {
              for (final p in myPlayers) p.id,
            }) ??
            bestEleven(points, _roster).starterIds;

        // Slots auflösen: Nutzer-Auswahl oder Saat (in gültiger Formation).
        // Slots gegen den aktuellen Kader bereinigen: gedroppte Spieler
        // (nicht mehr im Roster) werden zu leeren „frei"-Plätzen.
        final rosterIds = {for (final p in myPlayers) p.id};
        final slots = _slots == null
            ? _seedSlots(seedIds, byPos)
            : {
                for (final entry in _slots!.entries)
                  entry.key: [
                    for (final id in entry.value)
                      (id != null && rosterIds.contains(id)) ? id : null,
                  ],
              };

        final assigned = _assignedIds(slots);
        final (d, m, f) = _formationOf(slots);
        // **Hat er überhaupt einen Torwart?** Verlässt der einzige die
        // Bundesliga, nimmt ihn der Abgangs-Lauf aus dem Kader — ohne diese
        // Ausnahme wäre danach keine Elf mehr gültig, und der Schirm stünde
        // für immer auf „noch nicht vollständig". Dieselbe Regel steht in
        // `fantasy_set_lineup` (Migration 0120).
        final hatTorwart =
            myPlayers.any((p) => p.position == PlayerPosition.gk);
        final valid = _roster.isValidFormation(
          gkCount: slots[PlayerPosition.gk]?.whereType<String>().length ?? 0,
          defCount: slots[PlayerPosition.def]?.whereType<String>().length ?? 0,
          midCount: slots[PlayerPosition.mid]?.whereType<String>().length ?? 0,
          fwdCount: slots[PlayerPosition.fwd]?.whereType<String>().length ?? 0,
          torwartImKader: hatTorwart,
        );
        _lastIds = assigned.toList();
        _valid = valid;
        _effRound = current; // nur der echte Wert, nie der 34er-Notnagel
        _clubIcons = clubIcons;

        // Bank: Kaderspieler, die nicht aufgestellt sind.
        final bench =
            [
              for (final p in myPlayers)
                if (!assigned.contains(p.id)) p,
            ]..sort((a, b) {
              final cmp = a.position.index.compareTo(b.position.index);
              return cmp != 0
                  ? cmp
                  : (points[b] ?? 0).compareTo(points[a] ?? 0);
            });
        // Freie Kaderplätze (durch Drops entstanden).
        final emptySlots = (league.roster.squadSize - myPlayers.length).clamp(
          0,
          99,
        );

        // **Prognose der Startelf — nur zwischen den Spieltagen.**
        //
        // Sobald der erste Spieler festgenagelt ist, läuft der Spieltag: Dann
        // tragen die Kacheln echte Punkte, und eine Schätzung daneben wäre
        // eine zweite, schlechtere Antwort auf dieselbe Frage. Dasselbe
        // Signal, an dem auch die Kachel zwischen „Gegner und Anstoß" und
        // „Punktzahl" umschaltet.
        final elf = [
          for (final id in assigned)
            if (playerById[id] != null) playerById[id]!,
        ];
        // **Unbedingt beobachten, nicht erst im Zweig.** Ein `ref.watch` in
        // einem Ternär meldet die Abhängigkeit ab, sobald der andere Zweig
        // greift — die Provider dieses Schirms wechselten dann mit dem
        // Anpfiff, und ein nachgeladener Wert käme im falschen Moment nicht
        // an. Beide hängen ohnehin schon am Vorwärmer, kosten hier also nichts.
        final saison =
            ref.watch(seasonStatsProvider).valueOrNull ??
            const <int, Map<String, PlayerMatchStats>>{};
        final ausfaelle =
            ref.watch(absencesProvider).valueOrNull ??
            const <String, PlayerAbsence>{};
        // Ø je Einsatz auf jeder Kachel — dieselbe Zahl wie im Profil, nur
        // über abgepfiffene Spieltage.
        final fertig = gewerteteRunden(
            ref.watch(abgepfiffeneRundenProvider), saison.keys);
        final gewertet = {
          for (final e in saison.entries)
            if (fertig.contains(e.key)) e.key: e.value,
        };
        final schnitte = <String, double?>{
          for (final p in [...elf, ...bench])
            p.id: spielerSchnitt(
              saison: gewertet,
              spielerId: p.id,
              position: p.position,
              regeln: league.scoring,
            ).punkteJeEinsatz,
        };
        final vorschau = gesperrt.isEmpty
            ? projektion(
                elf: elf,
                saison: saison,
                regeln: league.scoring,
                ausfaelle: ausfaelle,
              )
            : null;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Die Sperre gilt je Spieler, also sagt die Zeile auch, wie
            // viele. „Aufstellung gesperrt" wäre ab dem Freitagsspiel
            // falsch — der Sonntagsspieler ist ja noch frei.
            if (gesperrt.isNotEmpty && !allesZu)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        gesperrt.length == 1
                            ? 'Ein Spieler ist gesperrt, sein Spiel läuft.'
                            : '${gesperrt.length} Spieler sind gesperrt, '
                                  'ihre Spiele laufen.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            _Pitch(
              schnitte: schnitte,
              slots: slots,
              playerById: playerById,
              points: points,
              clubIcons: clubIcons,
              onOpenProfile: _openProfile,
              gesperrt: gesperrt,
              allesZu: allesZu,
              projektion: vorschau,
              // Für die Kopfzeile der Kachel: gegen wen und wann er spielt,
              // solange es noch keine Punkte gibt.
              spiele:
                  ref.watch(fantasySeasonFixturesProvider).valueOrNull ??
                  const <Fixture>[],
              runde: round,
              onTapSlot: allesZu
                  ? null
                  : (pos, i) =>
                        _openPicker(pos, i, slots, byPos, points, stats),
              onDrop: allesZu
                  ? null
                  : (data, pos, i) => _applyDrop(slots, data, pos, i),
            ),
            // Formationen unter dem Spielfeld — **auch während des Spieltags**
            // (17.10.2026). Vorher verschwanden sie, sobald ein aufgestellter
            // Spieler gesperrt war. Jetzt bleiben sie; welche nicht mehr gehen,
            // zeigt die Leiste selbst (`formationGesperrtWeil`).
            if (!allesZu)
              _FormationChips(
                roster: _roster,
                byPos: byPos,
                current: (d, m, f),
                slots: slots,
                gesperrt: gesperrt,
                onSelected: (fm) {
                  // **Dieselben elf Spieler.** Vorher füllte `_buildSlots` die
                  // neue Formation mit den punktbesten Bankspielern auf — der
                  // Formationsknopf tauschte damit ungefragt den Kader.
                  // Ein spürbarer Klick wie beim Ziehen (Design-Ideen
                  // Punkt 6) — die Elf hat sich sichtbar umgebaut.
                  HapticFeedback.selectionClick();
                  setState(
                    () => _slots = umbauAufFormation(
                      slots: slots,
                      formation: fm,
                      torhueter: _roster.gk,
                      gesperrt: gesperrt,
                    ),
                  );
                  _autoSave();
                },
              ),
            _Bench(
              bench: bench,
              schnitte: schnitte,
              points: points,
              clubIcons: clubIcons,
              emptySlots: emptySlots,
              onOpenProfile: _openProfile,
              onOpenFreeAgency: _openFreeAgency,
              onDropToBench: allesZu ? null : (data) => _benchDrop(slots, data),
              spiele: ref.watch(fantasySeasonFixturesProvider).valueOrNull ??
                  const <Fixture>[],
              runde: round,
              gesperrt: gesperrt,
            ),
            // **Die Picks für den Reset-Draft unter der Bank** (0145, auf
            // Ansage). Sie gehören zum Kader der Rückrunde und lassen sich
            // während der Hinrunde wie Spieler handeln.
            if (widget.league.resetAktiv &&
                !(widget.league.draftPhase == 'reset' &&
                    widget.league.draftStatus == DraftStatus.done))
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Kapitelmarke('Picks · Reset-Draft'),
                    const SizedBox(height: 4),
                    MeinePicks(league: widget.league),
                  ],
                ),
              ),
            if (!allesZu)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                child: Builder(
                  builder: (context) {
                    // Vier Zustände, nicht einer. „Speichere …" stand vorher
                    // auch dann da, wenn der letzte Versuch gescheitert war —
                    // der Unterschied zwischen „ist gleich da" und „ist nicht
                    // angekommen" ist aber genau der, auf den es ankommt.
                    final zustand = speicherAnzeige(
                      gueltig: _valid,
                      laeuftGerade: _saving,
                      offen: _dirty,
                      fehlversuche: _fehlversuche,
                    );
                    final warnt =
                        zustand == SpeicherAnzeige.unvollstaendig ||
                        zustand == SpeicherAnzeige.fehlgeschlagen;
                    final farbe = warnt
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.onSurfaceVariant;
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          switch (zustand) {
                            SpeicherAnzeige.unvollstaendig =>
                              Icons.error_outline,
                            SpeicherAnzeige.fehlgeschlagen =>
                              Icons.cloud_off_outlined,
                            SpeicherAnzeige.laeuft => Icons.sync_outlined,
                            SpeicherAnzeige.gespeichert =>
                              Icons.cloud_done_outlined,
                          },
                          size: 14,
                          color: farbe,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            switch (zustand) {
                              SpeicherAnzeige.unvollstaendig =>
                                'Nicht gespeichert – die Elf ist noch nicht '
                                    'vollständig',
                              SpeicherAnzeige.fehlgeschlagen =>
                                'Nicht gespeichert – neuer Versuch läuft',
                              SpeicherAnzeige.laeuft => 'Speichere …',
                              SpeicherAnzeige.gespeichert => 'Gespeichert',
                            },
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: farbe),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              )
            else
              const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  /// Saat-Slots aus einer Startelf-Menge; nimmt deren Formation, fällt bei
  /// ungültiger (z. B. degenerierter Kader) auf die erste machbare zurück.
  Map<PlayerPosition, List<String?>> _seedSlots(
    Set<String> seedIds,
    Map<PlayerPosition, List<FantasyPlayer>> byPos,
  ) {
    int cnt(PlayerPosition pos) =>
        (byPos[pos] ?? const []).where((p) => seedIds.contains(p.id)).length;
    var formation = (
      cnt(PlayerPosition.def),
      cnt(PlayerPosition.mid),
      cnt(PlayerPosition.fwd),
    );
    final hatTorwart = (byPos[PlayerPosition.gk] ?? const []).isNotEmpty;
    final isValid = _roster.isValidFormation(
      gkCount: hatTorwart ? _roster.gk : 0,
      defCount: formation.$1,
      midCount: formation.$2,
      fwdCount: formation.$3,
      torwartImKader: hatTorwart,
    );
    if (!isValid) {
      // **Die Lücke bleibt, wo sie ist.** Vorher wurde hier die erste
      // besetzbare Formation genommen — aus 4-4-2 ohne einen Verteidiger
      // wurde 3-4-3, und ein Stürmer rückte in die Elf, den niemand
      // aufgestellt hatte.
      final passend = formationFuerElf(
        gesetzt: formation,
        besetzbar: _feasibleFormations(byPos),
        basis: (_roster.def, _roster.mid, _roster.fwd),
      );
      formation =
          passend ?? _feasibleFormations(byPos).firstOrNull ?? formation;
    }
    return _buildSlots(formation, seedIds, byPos);
  }

  /// Gültige Formationen, die der Kader auch besetzen kann.
  List<(int, int, int)> _feasibleFormations(
    Map<PlayerPosition, List<FantasyPlayer>> byPos,
  ) {
    int avail(PlayerPosition pos) => (byPos[pos] ?? const []).length;
    return [
      for (final fm in _roster.validFormations())
        if (fm.$1 <= avail(PlayerPosition.def) &&
            fm.$2 <= avail(PlayerPosition.mid) &&
            fm.$3 <= avail(PlayerPosition.fwd) &&
            _roster.gk <= avail(PlayerPosition.gk))
          fm,
    ];
  }

  Future<void> _openPicker(
    PlayerPosition pos,
    int slotIndex,
    Map<PlayerPosition, List<String?>> slots,
    Map<PlayerPosition, List<FantasyPlayer>> byPos,
    Map<FantasyPlayer, double> points,
    Map<String, PlayerMatchStats> stats,
  ) async {
    final samePosAssigned = slots[pos]!.whereType<String>().toSet();
    // Verfügbar: Spieler dieser Position, die nicht schon aufgestellt sind.
    final candidates = [
      for (final p in byPos[pos] ?? const <FantasyPlayer>[])
        // Gesperrte gar nicht erst anbieten — ihr Spiel läuft schon.
        if (!samePosAssigned.contains(p.id) && !_gesperrt.contains(p.id)) p,
    ];
    final occupied = slots[pos]![slotIndex] != null;

    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => _PlayerPicker(
        position: pos,
        candidates: candidates,
        points: points,
        stats: stats,
        clubIcons: _clubIcons,
        canClear: occupied,
      ),
    );
    if (picked == null) return;
    // Dieselbe Rückmeldung wie beim Ziehen aufs Feld.
    HapticFeedback.selectionClick();
    setState(() {
      final next = {
        for (final e in slots.entries) e.key: [...e.value],
      };
      next[pos]![slotIndex] = picked == _clearSentinel ? null : picked;
      _slots = next;
    });
    _autoSave(sofort: true);
  }

  Map<PlayerPosition, List<String?>> _copy(
    Map<PlayerPosition, List<String?>> s,
  ) => {
    for (final e in s.entries) e.key: [...e.value],
  };

  /// Spieler per Drag & Drop auf einen Platz ziehen: vom Feld → Tausch der
  /// beiden Plätze, von der Bank → der bisherige Spieler rückt auf die Bank.
  /// Von der Bank auf eine **andere Positionsgruppe** passt sich die
  /// Formation an (`wechselMitFormation`); geht sie nicht, sagt eine Meldung
  /// warum, und nichts ändert sich.
  void _applyDrop(
    Map<PlayerPosition, List<String?>> slots,
    _DragData data,
    PlayerPosition pos,
    int index,
  ) {
    if (data.pos != pos) {
      final w = wechselMitFormation(
        slots: slots,
        spielerId: data.playerId,
        spielerPos: data.pos,
        von: data.from,
        zielPos: pos,
        zielIndex: index,
        roster: _roster,
        torwartImKader: (slots[PlayerPosition.gk]?.length ?? 0) > 0,
      );
      if (w.fehler != null) {
        HapticFeedback.heavyImpact();
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(w.fehler!)));
        return;
      }
      HapticFeedback.selectionClick();
      setState(() => _slots = w.slots);
      _autoSave(sofort: true);
      return;
    }
    final next = _copy(slots);
    final occupant = next[pos]![index];
    final from = data.from;
    if (from != null) next[from.$1]![from.$2] = occupant;
    next[pos]![index] = data.playerId;
    HapticFeedback.selectionClick();
    setState(() => _slots = next);
    _autoSave(sofort: true);
  }

  /// Einen aufgestellten Spieler per Drag auf die Bank setzen (Platz wird frei).
  void _benchDrop(Map<PlayerPosition, List<String?>> slots, _DragData data) {
    final from = data.from;
    if (from == null) return; // war schon Bank
    final next = _copy(slots);
    next[from.$1]![from.$2] = null;
    HapticFeedback.selectionClick();
    setState(() => _slots = next);
    _autoSave(sofort: true);
  }
}

const _clearSentinel = '__clear__';

/// Nutzdaten eines gezogenen Spielers: ID, Position und Herkunft
/// (Feld-Slot `from` = (Position, Index); `null` = von der Bank).
class _DragData {
  const _DragData({required this.playerId, required this.pos, this.from});
  final String playerId;
  final PlayerPosition pos;
  final (PlayerPosition, int)? from;
}

class _FormationChips extends StatelessWidget {
  const _FormationChips({
    required this.roster,
    required this.byPos,
    required this.current,
    required this.onSelected,
    this.slots = const {},
    this.gesperrt = const {},
  });

  final RosterConfig roster;
  final Map<PlayerPosition, List<FantasyPlayer>> byPos;
  final (int, int, int) current;

  /// Die aktuelle Elf und wer darin schon gespielt hat — daraus folgt, welche
  /// Formationen noch gehen.
  final Map<PlayerPosition, List<String?>> slots;
  final Set<String> gesperrt;
  final ValueChanged<(int, int, int)> onSelected;

  @override
  Widget build(BuildContext context) {
    final imKader = {
      for (final p in PlayerPosition.values) p: (byPos[p] ?? const []).length,
    };
    String? fehlt((int, int, int) fm) => formationLuecke(fm, imKader: imKader);

    // **Jede Formation ist wählbar — auch die, für die der Kader nicht
    // reicht.**
    //
    // Erst fehlten sie ganz, dann standen sie gedämpft da und wehrten den Tipp
    // mit einem Hinweis ab. Beides war bevormundend. Auf Ansage: *„Wenn man
    // keine fünf Verteidiger hat, darf die fünfte Kette trotzdem nicht
    // ausgegraut sein. Da ist es dann halt leer, und wenn man in den Spieltag
    // geht und einen weniger aufgestellt hat, hat man Pech, aber es soll
    // auswählbar sein."*
    //
    // Der Umbau trägt das ohne Weiteres: `umbauAufFormation` rechnet rein
    // positionsweise und lässt neue Plätze leer — die Lücke ist auf dem Feld
    // als gestrichelter Kreis sichtbar und jederzeit zu füllen. Die gedämpfte
    // Darstellung bleibt, sie sagt jetzt „hier bleibt etwas leer" statt „geht
    // nicht".
    final formations = roster.validFormations();
    if (formations.length < 2) return const SizedBox.shrink();
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          for (final fm in formations)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              // `PillChip` statt `ChoiceChip`: Material-Auswahlelemente ziehen
              // ihre Auswahlfarbe aus `secondaryContainer`, und aus dem grünen
              // Seed wird das ein stumpfes Oliv, das zu nichts sonst in der
              // App passt (siehe CLAUDE.md). Fällt mit neun Formationen noch
              // mehr auf als mit acht.
              child: Builder(builder: (context) {
                // **Geht nicht mehr, weil zu viele schon gespielt haben** —
                // gedämpft und mit Schloss, ein Tipp sagt warum. Alles andere
                // bleibt wählbar wie bisher.
                final blockiert = fm == current
                    ? null
                    : formationGesperrtWeil(
                        slots: slots, formation: fm, gesperrt: gesperrt);
                if (blockiert != null) {
                  return Semantics(
                    button: true,
                    label: '${fm.$1}-${fm.$2}-${fm.$3}, nicht wählbar: '
                        '$blockiert',
                    excludeSemantics: true,
                    child: PillChip(
                      label: '${fm.$1}-${fm.$2}-${fm.$3}',
                      selected: false,
                      gedaempft: true,
                      leading: const Icon(Icons.lock_outline, size: 13),
                      onTap: () {
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('${fm.$1}-${fm.$2}-${fm.$3} geht '
                              'nicht mehr: $blockiert — ihre Spiele laufen '
                              'oder sind vorbei.'),
                        ));
                      },
                    ),
                  );
                }
                return PillChip(
                label: '${fm.$1}-${fm.$2}-${fm.$3}',
                // **Nicht gedämpft.** Die Dämpfung liegt bei 38 % Deckkraft
                // und liest sich als „gesperrt" — und gesperrt ist hier nichts
                // mehr. Dass ein Platz leer bleibt, sagt das Feld selbst: ein
                // gestrichelter Kreis, wo niemand steht.
                selected: fm == current,
                // **Umstellen zuerst, Hinweis danach.** Der Hinweis sagt, was
                // leer bleibt — er verhindert nichts mehr.
                onTap: () {
                  onSelected(fm);
                  final grund = fehlt(fm);
                  if (grund == null) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '${fm.$1}-${fm.$2}-${fm.$3}: '
                        'Dir fehlt $grund — der Platz bleibt frei.',
                      ),
                    ),
                  );
                },
              );
              }),
            ),
        ],
      ),
    );
  }
}

/// Breite des Prognose-Kastens neben dem Torwart — eigene Zahl, nicht die
/// Kachelbreite: Seit die Kachel schmaler ist (62), brach „PROGNOSE" um.
const _prognoseBreite = 70.0;

class _Pitch extends StatelessWidget {
  const _Pitch({
    required this.slots,
    required this.schnitte,
    required this.playerById,
    required this.points,
    required this.clubIcons,
    required this.spiele,
    required this.runde,
    required this.onOpenProfile,
    required this.onTapSlot,
    required this.onDrop,
    required this.gesperrt,
    required this.allesZu,
    this.projektion,
  });

  /// Prognose der Startelf, oder `null`, solange der Spieltag läuft.
  final Projektion? projektion;

  /// Ø je Einsatz je Spieler-ID.
  final Map<String, double?> schnitte;

  /// IDs der Spieler, deren Spiel schon läuft — festgenagelt (Migration 0084).
  final Set<String> gesperrt;

  /// Jeder Spieler der Elf ist festgenagelt: An dieser Aufstellung ist nichts
  /// mehr zu ändern.
  final bool allesZu;

  final Map<PlayerPosition, List<String?>> slots;
  final Map<String, FantasyPlayer> playerById;
  final Map<FantasyPlayer, double> points;
  final Map<String, String?> clubIcons;

  /// Spielplan der Saison und der aufzustellende Spieltag — daraus ergibt sich
  /// je Spieler „gegen wen und wann".
  final List<Fixture> spiele;
  final int runde;
  final ValueChanged<FantasyPlayer> onOpenProfile;
  final void Function(PlayerPosition pos, int index)? onTapSlot;
  final void Function(_DragData data, PlayerPosition pos, int index)? onDrop;

  @override
  Widget build(BuildContext context) {
    // **Höher als früher (470 statt 420).** Der Platz kommt den Spielern
    // zugute: größeres Wappen, lesbarer Name, eine Punktzahl, die man nicht
    // suchen muss. Bei 420 stand alles davon im selben Raum wie vorher.
    return Container(
      margin: const EdgeInsets.all(12),
      // 440 seit der kompakten Kachel (19.10.2026, 90 hoch); vorher 500 für
      // die 108 hohe.
      height: 440,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: pitchGradient,
        // Dieselbe Haarlinie wie an jeder Karte dieser App.
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: CustomPaint(
        painter: const PitchLinesPainter(),
        child: Stack(
          children: [
            Padding(
              // Vier Punkte weniger oben und unten: Sie fehlten den Reihen,
              // seit die Kachel Gegner und Anstoß als eigene Zeilen trägt.
              // Geholt werden sie am Rand des Rasens, nicht an der Schrift —
              // kleiner setzen hieße, genau das aufzugeben, worum es ging.
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 10),
              child: Column(
                children: [
                  for (final pos in _pitchOrder)
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // **Die Prognose steht links neben dem Torwart.**
                          // Dort ist die einzige Reihe mit Platz: Ein Torwart
                          // teilt sich die Breite mit niemandem. Der leere
                          // Kasten auf der Gegenseite hält ihn trotzdem in der
                          // Mitte — ohne ihn rutschte er um die halbe Boxbreite
                          // nach rechts, und die Elf stünde schief auf dem Feld.
                          if (pos == PlayerPosition.gk && projektion != null)
                            SizedBox(
                              width: _prognoseBreite,
                              child: _ProjektionsBox(werte: projektion!),
                            ),
                          // **Jeder Platz nimmt seinen Anteil an der Reihe.**
                          // Vorher war er 76 Punkte breit, fest: Fünf davon
                          // sind 380 und passen auf keinen Telefonschirm — bei
                          // einer 3-5-2 lief die Mittelfeldreihe über.
                          for (var i = 0; i < (slots[pos]?.length ?? 0); i++)
                            Expanded(child: _slotTarget(pos, i)),
                          if (pos == PlayerPosition.gk && projektion != null)
                            const SizedBox(width: _prognoseBreite),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            // **Steht die Elf, sagt es das Feld selbst.** Vorher stand darüber
            // eine graue Textzeile, die neben dem Rasen kaum auffiel — und der
            // wichtigste Zustand dieses Schirms ist genau der, in dem nichts
            // mehr geht.
            if (allesZu)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: _Sperrband(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _slotTarget(PlayerPosition pos, int i) {
    final player = playerById[slots[pos]![i]];
    final pts = player == null ? null : points[player];
    // Ein Platz ist zu, wenn der Spieler darauf schon spielt. Er anzunehmen
    // wäre genauso falsch wie ihn wegzuziehen: Beides änderte die Elf
    // rückwirkend für ein laufendes Spiel.
    final platzZu = player != null && gesperrt.contains(player.id);
    return DragTarget<_DragData>(
      // Gleiche Position wie bisher; **von der Bank auch auf eine andere
      // Gruppe** — dann passt sich die Formation an (`wechselMitFormation`).
      // Der Torwart bleibt außen vor, seine Zahl steht fest.
      onWillAcceptWithDetails: (d) =>
          onDrop != null &&
          (d.data.pos == pos ||
              (d.data.from == null &&
                  d.data.pos != PlayerPosition.gk &&
                  pos != PlayerPosition.gk)) &&
          d.data.from != (pos, i) &&
          !platzZu &&
          !gesperrt.contains(d.data.playerId),
      onAcceptWithDetails: (d) => onDrop!(d.data, pos, i),
      builder: (context, candidate, rejected) {
        final slot = _Slot(
          player: player,
          schnitt: player == null ? null : schnitte[player.id],
          pos: pos,
          points: pts,
          spiel: player == null
              ? null
              : naechstesSpiel(spiele, runde, player.club),
          alleZu: allesZu,
          iconUrl: player == null ? null : clubIcons[player.club],
          highlight: candidate.isNotEmpty,
          // Spieler antippen → Profil; Positions-Pille → Aufstellung bearbeiten.
          onProfile: player == null ? null : () => onOpenProfile(player),
          gesperrt: platzZu,
          onEditPosition: (onTapSlot == null || platzZu)
              ? null
              : () => onTapSlot!(pos, i),
        );
        if (player == null || onDrop == null || platzZu) return slot;
        final data = _DragData(playerId: player.id, pos: pos, from: (pos, i));
        return LongPressDraggable<_DragData>(
          // Kurz halten genügt — mit der Standardzeit (0,5 s) fühlte sich das
          // Ziehen an, als gäbe es es nicht.
          delay: const Duration(milliseconds: 250),
          data: data,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: _DragFeedback(
            player: player,
            iconUrl: clubIcons[player.club],
          ),
          childWhenDragging: Opacity(opacity: 0.3, child: slot),
          child: slot,
        );
      },
    );
  }
}

PlayerAbsence? _ausfall(WidgetRef ref, FantasyPlayer? p) => p == null
    ? null
    : (ref.watch(absencesProvider).valueOrNull ?? const {})[p.id];

class _Slot extends ConsumerWidget {
  const _Slot({
    required this.player,
    this.schnitt,
    required this.pos,
    required this.points,
    required this.spiel,
    required this.iconUrl,
    required this.onProfile,
    required this.onEditPosition,
    this.highlight = false,
    this.gesperrt = false,
    this.alleZu = false,
  });

  /// Sein Spiel läuft — der Platz ist zu. Wird als Schloss gezeigt, statt nur
  /// stumm nicht zu reagieren.
  final bool gesperrt;

  /// **Die ganze Elf steht.** Dann trägt das Band über dem Feld die Auskunft,
  /// und das Schloss am Wappen entfällt: Elf Schlösser sagen nicht mehr als
  /// eines, sie machen nur das Feld unruhig. Beim *einzelnen* gesperrten
  /// Spieler bleibt es — dort ist es die einzige Stelle, an der steht, wen es
  /// betrifft.
  final bool alleZu;

  /// Ø je Einsatz (für die Kachel).
  final double? schnitt;
  final FantasyPlayer? player;
  final PlayerPosition pos;
  final double? points;

  /// Sein Spiel an diesem Spieltag — `null`, wenn sein Verein frei hat.
  final NaechstesSpiel? spiel;
  final String? iconUrl;

  /// Tippen auf den Spieler (Avatar/Name) → Profil.
  final VoidCallback? onProfile;

  /// Tippen auf die Positions-Pille → Aufstellung bearbeiten (Spielerwahl).
  final VoidCallback? onEditPosition;

  /// Hervorhebung, wenn ein passender Spieler über diesen Platz gezogen wird.
  final bool highlight;

  /// **Jede Kachel ist gleich groß — und zwar so breit wie die engste Reihe
  /// es zulässt.**
  ///
  /// Eine Reihe teilt ihre Breite unter ihren Plätzen auf: Beim Torwart ist
  /// das die ganze Feldbreite, bei einer Fünferkette ein Fünftel davon. Mit
  /// einer bloßen Obergrenze waren die Kacheln deshalb verschieden breit, und
  /// der Inhalt musste sich in der Fünferkette zusammenschrumpfen lassen —
  /// gemeldet als: *„Wenn ich auf eine Fünferkette umstelle, sieht man die
  /// Uhrzeit und das Spiel ja kaum."*
  ///
  /// Gerechnet: 402 Punkte Schirmbreite − 2 × 12 Rand des Feldes − 2 × 4
  /// Innenabstand = 370 für die Reihe, geteilt durch fünf = 74, minus Rand (2)
  /// und Polster (4) der Kachel = **68**. Was hier hineinpasst, passt überall
  /// hinein.
  static const _kachelBreite = 62.0;

  /// Breiter wird eine Kachel nicht — mit vier in einer Reihe sind es rund
  /// 86 Punkte, beim Torwart wäre sonst eine Karte über die halbe Feldbreite.
  static const _kachelMax = 76.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = player;
    final ausfall = _ausfall(ref, p);
    // **Eine Zahl steht nur da, wenn sie etwas bedeutet.** Vor dem Anpfiff
    // seines Vereins gibt es keine Leistung dieses Spieltags — angezeigt wurde
    // trotzdem eine Zahl, und zwischen zwei Spieltagen kam sie aus der
    // Ersatzrechnung eines fremden Spieltags (`LiveStatsSource` springt ein,
    // solange `player_match_stats` für die Runde leer ist). Gemeldet als:
    // „Die Punkte zwischen den Spieltagen brauchen wir nicht."
    final zeigePunkte = gesperrt && p != null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      margin: const EdgeInsets.symmetric(horizontal: 1),
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: highlight ? Colors.white.withValues(alpha: 0.18) : null,
        border: Border.all(
          color: highlight ? Colors.white : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Karte antippen → Profil (leerer Platz → Spielerwahl).
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: p != null ? onProfile : onEditPosition,
            // **Die Breite folgt dem Platz in der Reihe** (16.10.2026, auf
            // Ansage: „die sehen so zusammengequetscht aus"). Fest 68 Punkte
            // waren das Maß der Fünferkette — und galten damit auch für den
            // Torwart, der die ganze Breite hat. Jetzt nimmt die Kachel, was
            // die Reihe hergibt, höchstens [_kachelMax].
            child: LayoutBuilder(builder: (context, c) {
              final breite = c.maxWidth.isFinite
                  ? c.maxWidth.clamp(_kachelBreite, _kachelMax).toDouble()
                  : _kachelMax;
              return SizedBox(
                width: breite,
                child: p == null
                    ? _LeererPlatz(pos: pos)
                    : _SpielerAufRasen(
                        spieler: p,
                        schnitt: schnitt,
                        iconUrl: iconUrl,
                        ausfall: ausfall,
                        spiel: spiel,
                        gesperrt: gesperrt,
                        zeigePunkte: zeigePunkte,
                        punkte: points,
                        onTausch: (gesperrt || onEditPosition == null)
                            ? null
                            : onEditPosition,
                        tauschLabel: '${pos.label} tauschen',
                      ),
              );
            }),
          ),
          // **Kein Kreis mehr unter der Karte.** Tausch und Schloss stehen in
          // der Kopfzeile der Kachel; der eigene Knopf darunter kostete jede
          // Reihe rund 28 Punkte Höhe und trug elf farbige Ringe auf den
          // Rasen, die dort nichts sagten.
        ],
      ),
    );
  }
}

/// Ein leerer Platz auf dem Feld: gestrichelter Kreis in der Positionsfarbe.
///
/// Er ist eine **Einladung**, kein Fehler — deshalb trägt er die Farbe seiner
/// Position und ein Plus, nicht die stille graue Fläche von früher.
/// **Die voraussichtliche Punktzahl der Startelf.**
///
/// Zwischen den Spieltagen ist der Rasen sonst eine Ansammlung von Kacheln
/// ohne eine einzige Zahl — die Frage „reicht das am Samstag?" beantwortet
/// nichts. Sie steht bewusst **auf** dem Feld und nicht in einer Kopfzeile
/// darüber: Sie gehört zu dieser Elf, und sie ändert sich, sobald man einen
/// Spieler tauscht.
///
/// **Leise gebaut.** Kartengrund und Haarlinie wie jede Karte dieser App,
/// keine Signalfarbe: Eine Prognose meldet nichts, sie rechnet nur. Grün hieße
/// „hier läuft etwas", und hier läuft gerade ausdrücklich nichts.
class _ProjektionsBox extends StatelessWidget {
  const _ProjektionsBox({required this.werte});

  final Projektion werte;

  @override
  Widget build(BuildContext context) {
    final grund = werte.ausgelassen == 0
        ? 'Prognose aus dem Schnitt der ${werte.gezaehlt} aufgestellten Spieler'
        : 'Prognose aus dem Schnitt von ${werte.gezaehlt} Spielern — '
              '${werte.ausgelassen} fallen aus und zählen nicht mit';

    return Tooltip(
      message: werte.hatDaten
          ? grund
          : 'Noch keine gewerteten Spieltage — es gibt nichts zu mitteln',
      child: Semantics(
        label: werte.hatDaten
            ? 'Voraussichtlich ${formatPoints(werte.punkte)} Punkte. $grund'
            : 'Noch keine Prognose',
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            // Deckend wie die Spielerkacheln — auf dem Rasen ist alles
            // Durchscheinende schon einmal als „verschwommen" gemeldet worden.
            color: Theme.of(context).colorScheme.surfaceContainer,
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                // **Deutsch wie der Rest der App.** Hieß „PROJECTED" nach dem
                // Wort der Ansage; im MatchUp-Kopf steht dieselbe Sache als
                // „PROGNOSE", und zwei Sprachen für eine Zahl sind eine zu
                // viel.
                'PROGNOSE',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: Schrift.mikro,
                  height: 1.1,
                  letterSpacing: 0.5,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              // **Ein Strich, keine Null.** Vor dem ersten gewerteten Spieltag
              // gibt es keinen Schnitt; eine 0 wäre eine Aussage, die niemand
              // gemacht hat — dieselbe Regel wie in der Punktebox im MatchUp.
              if (!werte.hatDaten)
                Text(
                  '–',
                  style: TextStyle(
                    fontSize: Schrift.titel,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                )
              else
                Punktzahl(
                  werte.punkte,
                  stil: const TextStyle(
                    fontSize: Schrift.titel,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              // Auf wie vielen Spielern die Zahl beruht, sagt der Tooltip
              // (lange drücken) — als dritte Zeile in 9 Punkt stand es
              // dauerhaft im Bild (Design-Ideen Punkt 4, 15.10.2026).
            ],
          ),
        ),
      ),
    );
  }
}

/// **Ein Spieler auf dem Rasen — ohne Kasten** (21.10.2026, auf Ansage: „mit
/// dem Kaderbereich, wie dort die Spieler auf dem Spielfeld sind, noch nicht
/// zufrieden … Name, Logo und Durchschnittspunkte müssen mit rein").
///
/// Vorher standen elf dunkle Karten auf dem Rasen, jede mit einem bunten
/// Tauschkreis an der Ecke und einem Positionsstrich am Fuß — das Feld war
/// eine Fläche aus Kästen, und der Rasen darunter nur noch Rand. Jetzt nach
/// dem Muster von Sleeper und FPL: **Das Wappen steht auf dem Rasen**,
/// darunter ein schmales, deckendes Namensschild (Nachname, weiß, fett) und
/// darunter eine hellere Zeile mit Heim/Auswärts samt Gegnerwappen und dem Ø
/// — läuft sein Spiel, stehen dort die Punkte. Die Position sagt die Reihe;
/// Tausch und Schloss sind ein kleiner **neutraler** Kreis am Wappen.
///
/// Deckend, nicht durchscheinend: Auf dem Rasen ist Durchscheinendes schon
/// einmal als „verschwommen" gemeldet worden. Die Bank behält die Karte
/// ([_SpielerKachelFeld]) — auf schwarzem Grund ginge ein dunkles Schild unter.
class _SpielerAufRasen extends StatelessWidget {
  const _SpielerAufRasen({
    required this.spieler,
    required this.iconUrl,
    required this.ausfall,
    required this.spiel,
    required this.gesperrt,
    required this.zeigePunkte,
    required this.punkte,
    required this.onTausch,
    required this.tauschLabel,
    this.schnitt,
    this.aufBank = false,
    this.ohneEcke = false,
  });

  /// **Auf der Bank** (21.10.2026, auf Ansage „auf der Bank bitte auch in die
  /// Richtung"): dieselbe Form, aber die Schilder eine Stufe heller, damit
  /// sie sich vom schwarzen Grund abheben; die Position als Strich unter dem
  /// Schild (dort sagt sie keine Reihe); ein Ausfall färbt das Namensschild
  /// gold bzw. rot — vorher die ganze Karte (17.10.2026, ausdrücklich
  /// gewollt: „wen kann ich überhaupt bringen?").
  final bool aufBank;

  /// Kein Kreis an der Ecke (Bank ohne laufendes Spiel).
  final bool ohneEcke;

  final FantasyPlayer spieler;
  final String? iconUrl;
  final PlayerAbsence? ausfall;
  final NaechstesSpiel? spiel;
  final bool gesperrt;
  final bool zeigePunkte;
  final double? punkte;
  final double? schnitt;
  final VoidCallback? onTausch;
  final String tauschLabel;

  /// Feste Höhe, damit eine Reihe nicht schief steht, egal ob vor, während
  /// oder nach dem Spiel: Wappen 34 + 5 + Schild 19 + Zeile 17 = 75.
  static const hoehe = 76.0;

  static const _schild = Color(0xFF111111);
  static const _zeile = Color(0xFF2B2B2B);
  static const _schildBank = Color(0xFF1E1E1E);
  static const _zeileBank = Color(0xFF2E2E2E);

  static String _kurz(String name) {
    final teile = name.trim().split(' ');
    return teile.length > 1 ? teile.last : name;
  }

  @override
  Widget build(BuildContext context) {
    final leise = Colors.white.withValues(alpha: 0.75);
    final nachname = _kurz(spieler.name);
    final schildGrund = aufBank
        ? (ausfall != null
            ? Color.alphaBlend(
                ausfallFarbe(ausfall!).withValues(alpha: 0.45), _schildBank)
            : _schildBank)
        : _schild;
    final zeileGrund = aufBank ? _zeileBank : _zeile;

    final Widget unten;
    if (zeigePunkte) {
      unten = Text(
        formatPoints(punkte ?? 0),
        style: TextStyle(
          color: (punkte ?? 0) < 0 ? const Color(0xFFF23030) : MatchUpColors.snow,
          fontSize: Schrift.label,
          fontWeight: FontWeight.w800,
          height: 1.0,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
    } else {
      unten = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (spiel != null)
            SpielMarke(
                spiel: spiel!,
                farbe: leise,
                mitZeit: false,
                buchstabe: true,
                wappen: 12)
          else
            Text('frei',
                style: TextStyle(
                    fontSize: Schrift.mikro, height: 1.0, color: leise)),
          if (schnitt != null) ...[
            const SizedBox(width: 5),
            Text(
              'Ø ${formatPoints(schnitt!)}',
              style: const TextStyle(
                fontSize: Schrift.label,
                fontWeight: FontWeight.w700,
                height: 1.0,
                color: MatchUpColors.snow,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      );
    }

    final ecke = Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _schild,
        border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
      ),
      child: Icon(
        onTausch == null ? Icons.lock_outline : Icons.swap_horiz,
        size: 12,
        color: MatchUpColors.snow,
      ),
    );

    return SizedBox(
      height: hoehe,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // **Volle Kachelbreite**, damit der Kreis rechts oben *innerhalb*
          // liegt: Flutter nimmt Tipps außerhalb eines Elements nicht an —
          // ein Kreis, der über den Rand ragt, wäre nur zum Ansehen da.
          SizedBox(
            width: double.infinity,
            height: 34,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Opacity(
                  opacity: gesperrt ? 0.6 : 1,
                  child: ClubBadge(
                      club: spieler.club, iconUrl: iconUrl, size: 32),
                ),
                if (ausfall != null)
                  Align(
                    alignment: const Alignment(-0.45, 1),
                    child: AusfallZeichen(ausfall: ausfall!, size: 15),
                  ),
                // Rechts neben dem Wappen statt darauf.
                if (!ohneEcke)
                Positioned(
                  top: onTausch == null ? 0 : -6,
                  right: onTausch == null ? 0 : -6,
                  child: onTausch == null
                      ? ecke
                      // Der Name bleibt für die Vorlesehilfe — sonst hießen
                      // alle elf Knöpfe „Schaltfläche".
                      : Semantics(
                          button: true,
                          label: tauschLabel,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: onTausch,
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: ecke,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          // Namensschild und Zeile darunter als ein Stück: oben dunkel und
          // fett, unten eine Stufe heller.
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 19,
                  color: schildGrund,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  alignment: Alignment.center,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      nachname,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        color: gesperrt
                            ? MatchUpColors.snow.withValues(alpha: 0.6)
                            : MatchUpColors.snow,
                        fontSize: Schrift.text,
                        fontWeight: FontWeight.w800,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
                Container(
                  height: aufBank ? 15 : 17,
                  color: zeileGrund,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.center,
                  child: FittedBox(fit: BoxFit.scaleDown, child: unten),
                ),
                if (aufBank)
                  Container(height: 2, color: positionColor(spieler.position)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LeererPlatz extends StatelessWidget {
  const _LeererPlatz({required this.pos});

  final PlayerPosition pos;

  @override
  Widget build(BuildContext context) {
    final farbe = positionColor(pos);
    return SizedBox(
      height: 54,
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.35),
          border: Border.all(color: farbe.withValues(alpha: 0.85), width: 2),
        ),
        child: Icon(Icons.add, color: farbe, size: 22),
      ),
    );
  }
}

/// Das Band über dem Feld, wenn an der Elf nichts mehr zu ändern ist.
class _Sperrband extends StatelessWidget {
  const _Sperrband();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.black.withValues(alpha: 0.72),
              Colors.black.withValues(alpha: 0.42),
            ],
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock, size: 14, color: Color(0xFFFFC83D)),
            const SizedBox(width: 7),
            Text(
              'Aufstellung steht — alle Spiele laufen',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.92),
                fontSize: Schrift.label,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      );
}

/// Spieler-Avatar als Drag-Vorschau unter dem Finger.
class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.player, required this.iconUrl});

  final FantasyPlayer player;
  final String? iconUrl;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Transform.translate(
        offset: const Offset(-27, -27),
        child: Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          padding: const EdgeInsets.all(3),
          child: ClubBadge(club: player.club, iconUrl: iconUrl, size: 46),
        ),
      ),
    );
  }
}

class _Bench extends ConsumerWidget {
  const _Bench({
    required this.bench,
    required this.schnitte,
    required this.points,
    required this.clubIcons,
    required this.emptySlots,
    required this.onOpenProfile,
    required this.onOpenFreeAgency,
    required this.onDropToBench,
    this.spiele = const [],
    this.runde,
    this.gesperrt = const {},
  });

  /// Für die Karten: Gegner und Anstoß bzw. ob sein Spiel läuft.
  final List<Fixture> spiele;
  final int? runde;
  final Set<String> gesperrt;

  /// Ø je Einsatz je Spieler-ID.
  final Map<String, double?> schnitte;
  final List<FantasyPlayer> bench;
  final Map<FantasyPlayer, double> points;
  final Map<String, String?> clubIcons;

  /// Freie Kaderplätze (durch Drops entstanden).
  final int emptySlots;
  final ValueChanged<FantasyPlayer> onOpenProfile;
  final VoidCallback onOpenFreeAgency;

  /// Aufgestellten Spieler per Drag auf die Bank setzen (`null` = gesperrt).
  final void Function(_DragData data)? onDropToBench;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: DragTarget<_DragData>(
        onWillAcceptWithDetails: (d) =>
            onDropToBench != null && d.data.from != null,
        onAcceptWithDetails: (d) => onDropToBench!(d.data),
        builder: (context, candidate, rejected) {
          final hot = candidate.isNotEmpty;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: hot ? scheme.primary.withValues(alpha: 0.10) : null,
              border: Border.all(
                color: hot ? scheme.primary : Colors.transparent,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bank (${bench.length})',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                if (bench.isEmpty && emptySlots == 0)
                  Text(
                    hot
                        ? 'Hier ablegen, um auf die Bank zu setzen.'
                        : 'Alle Spieler stehen in der Startelf.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  )
                else
                  // **Dieselben Karten wie auf dem Feld, in einer Reihe zum
                  // Wischen** (17.10.2026, auf Ansage). Vorher kleine Chips,
                  // nach Position gruppiert und umbrechend — eine zweite
                  // Darstellung desselben Spielers neben der auf dem Rasen.
                  // Sortiert nach Position, dann Punkten; freie Kaderplätze
                  // stehen als eigene Karte am Ende.
                  SizedBox(
                    height: _SpielerAufRasen.hoehe + 8,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      padding: const EdgeInsets.only(top: 4, right: 4),
                      children: [
                        // `Align` lockert die Höhe: Eine waagerechte Liste
                        // zwingt ihren Kindern ihre volle Höhe auf, und die
                        // Karte wäre 96 statt 92 Punkte hoch geworden.
                        for (final p in _sortiert())
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: SizedBox(
                                width: _kartenBreite,
                                child: _bankKarte(ref, p),
                              ),
                            ),
                          ),
                        for (var i = 0; i < emptySlots; i++)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: SizedBox(
                                width: _kartenBreite,
                                child: _freierPlatz(context),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// So breit wie eine Karte in einer Viererreihe auf dem Feld.
  static const _kartenBreite = 74.0;

  List<FantasyPlayer> _sortiert() => [...bench]
    ..sort((a, b) {
      final p = a.position.index.compareTo(b.position.index);
      if (p != 0) return p;
      return (points[b] ?? 0).compareTo(points[a] ?? 0);
    });

  Widget _bankKarte(WidgetRef ref, FantasyPlayer p) {
    final zu = gesperrt.contains(p.id);
    final karte = _SpielerAufRasen(
      aufBank: true,
      spieler: p,
      schnitt: schnitte[p.id],
      iconUrl: clubIcons[p.club],
      // Der Ausfall steht am Wappen — die Bank ist die Liste, aus der man
      // den Ersatz holt.
      ausfall: ausfallFuer(ref, p.id),
      spiel: runde == null ? null : naechstesSpiel(spiele, runde!, p.club),
      gesperrt: zu,
      zeigePunkte: zu,
      punkte: points[p],
      onTausch: null,
      tauschLabel: '',
      ohneEcke: !zu,
    );
    // Tippen → Profil; langes Drücken → aufs Feld ziehen.
    final tappable = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onOpenProfile(p),
      child: karte,
    );
    if (onDropToBench == null || zu) return tappable;
    final data = _DragData(playerId: p.id, pos: p.position);
    return LongPressDraggable<_DragData>(
      delay: const Duration(milliseconds: 250),
      data: data,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _DragFeedback(player: p, iconUrl: clubIcons[p.club]),
      childWhenDragging: Opacity(opacity: 0.3, child: tappable),
      child: tappable,
    );
  }

  /// Ein freier Kaderplatz (durch einen Drop) — führt zu „Spieler".
  Widget _freierPlatz(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Freier Kaderplatz — Spieler holen',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onOpenFreeAgency,
        child: Container(
          height: _SpielerAufRasen.hoehe,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, size: 22, color: scheme.onSurfaceVariant),
              const SizedBox(height: 6),
              Text('Frei',
                  style: TextStyle(
                      fontSize: Schrift.label,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom-Sheet: verfügbare Spieler einer Position auswählen (oder Slot leeren).
class _PlayerPicker extends ConsumerWidget {
  const _PlayerPicker({
    required this.position,
    required this.candidates,
    required this.points,
    required this.stats,
    required this.clubIcons,
    required this.canClear,
  });

  final PlayerPosition position;
  final List<FantasyPlayer> candidates;
  final Map<FantasyPlayer, double> points;
  final Map<String, PlayerMatchStats> stats;
  final Map<String, String?> clubIcons;
  final bool canClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
              child: Row(
                children: [
                  Text(
                    '${position.label} wählen',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  if (canClear)
                    TextButton(
                      onPressed: () =>
                          Navigator.of(context).pop(_clearSentinel),
                      child: const Text('Slot leeren'),
                    ),
                ],
              ),
            ),
            if (candidates.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Keine weiteren ${position.label}-Spieler im Kader.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: candidates.length,
                  itemBuilder: (context, i) {
                    final p = candidates[i];
                    final s = stats[p.id];
                    // **Hier fällt die Entscheidung.** Wer einen Spieler auf
                    // den Platz setzt, sieht in dieser Liste sonst nur Verein
                    // und Punkte — und stellt einen Verletzten auf, dessen
                    // Zustand eine Tippebene tiefer steht.
                    final ausfall = ausfallFuer(ref, p.id);
                    final detail = <String>[
                      p.club,
                      if ((s?.goals ?? 0) > 0) '${s!.goals} Tor',
                      if (s?.cleanSheet ?? false) 'Zu Null',
                      if (ausfall != null) ausfall.kurz,
                    ].join(' · ');
                    return ListTile(
                      leading: ClubBadge(
                        club: p.club,
                        iconUrl: clubIcons[p.club],
                      ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (ausfall != null) ...[
                            const SizedBox(width: 6),
                            AusfallZeichen(ausfall: ausfall, size: 14),
                          ],
                        ],
                      ),
                      subtitle: Text(
                        detail,
                        style: ausfall == null
                            ? null
                            : TextStyle(color: ausfallFarbe(ausfall)),
                      ),
                      trailing: Text(
                        formatPoints(points[p] ?? 0),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: scheme.primary,
                            ),
                      ),
                      onTap: () => Navigator.of(context).pop(p.id),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
