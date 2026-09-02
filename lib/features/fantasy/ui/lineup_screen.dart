import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/widgets/pill_selector.dart';

import '../../auth/providers.dart';
import '../logic/fantasy_scoring_engine.dart';
import '../logic/aufstellung_sperre.dart';
import '../logic/aufstellung_uebernahme.dart';
import '../logic/formation_umbau.dart';
import '../logic/lineup_autosave.dart';
import '../data/fantasy_league_repository.dart';
import '../models/fantasy_models.dart';
import '../models/player_absence.dart';
import '../providers.dart';
import 'club_badge.dart';
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

  /// Slots für eine Formation bauen; bevorzugt Spieler aus [prefer]
  /// (bestehende Auswahl / gespeicherte Elf), füllt sonst die punktbesten.
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
      final preferred = [
        for (final p in ordered)
          if (prefer.contains(p.id)) p.id,
      ];
      final rest = [
        for (final p in ordered)
          if (!prefer.contains(p.id)) p.id,
      ];
      final pick = [...preferred, ...rest].take(n).toList();
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
        child: Center(child: CircularProgressIndicator()),
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
        final valid = _roster.isValidFormation(
          gkCount: slots[PlayerPosition.gk]?.whereType<String>().length ?? 0,
          defCount: slots[PlayerPosition.def]?.whereType<String>().length ?? 0,
          midCount: slots[PlayerPosition.mid]?.whereType<String>().length ?? 0,
          fwdCount: slots[PlayerPosition.fwd]?.whereType<String>().length ?? 0,
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

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Die Sperre gilt je Spieler, also sagt die Zeile auch, wie
            // viele. „Aufstellung gesperrt" wäre ab dem Freitagsspiel
            // falsch — der Sonntagsspieler ist ja noch frei.
            if (gesperrt.isNotEmpty)
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
                        allesZu
                            ? 'Alle Spiele laufen — die Aufstellung steht.'
                            : gesperrt.length == 1
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
              slots: slots,
              playerById: playerById,
              points: points,
              clubIcons: clubIcons,
              onOpenProfile: _openProfile,
              gesperrt: gesperrt,
              onTapSlot: allesZu
                  ? null
                  : (pos, i) =>
                        _openPicker(pos, i, slots, byPos, points, stats),
              onDrop: allesZu
                  ? null
                  : (data, pos, i) => _applyDrop(slots, data, pos, i),
            ),
            // Formationen unter dem Spielfeld.
            if (!assigned.any(gesperrt.contains))
              _FormationChips(
                roster: _roster,
                byPos: byPos,
                current: (d, m, f),
                onSelected: (fm) {
                  // **Dieselben elf Spieler.** Vorher füllte `_buildSlots` die
                  // neue Formation mit den punktbesten Bankspielern auf — der
                  // Formationsknopf tauschte damit ungefragt den Kader.
                  setState(
                    () => _slots = umbauAufFormation(
                      slots: slots,
                      formation: fm,
                      torhueter: _roster.gk,
                    ),
                  );
                  _autoSave();
                },
              ),
            _Bench(
              bench: bench,
              points: points,
              clubIcons: clubIcons,
              emptySlots: emptySlots,
              onOpenProfile: _openProfile,
              onOpenFreeAgency: _openFreeAgency,
              onDropToBench: allesZu ? null : (data) => _benchDrop(slots, data),
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
                            SpeicherAnzeige.laeuft => Icons.sync,
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
    final isValid = _roster.isValidFormation(
      gkCount: _roster.gk,
      defCount: formation.$1,
      midCount: formation.$2,
      fwdCount: formation.$3,
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

  /// Spieler per Drag & Drop auf einen Platz ziehen. Gleiche Position ist
  /// durch das DragTarget garantiert: vom Feld → Tausch der beiden Plätze,
  /// von der Bank → der bisherige Spieler rückt auf die Bank.
  void _applyDrop(
    Map<PlayerPosition, List<String?>> slots,
    _DragData data,
    PlayerPosition pos,
    int index,
  ) {
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
  });

  final RosterConfig roster;
  final Map<PlayerPosition, List<FantasyPlayer>> byPos;
  final (int, int, int) current;
  final ValueChanged<(int, int, int)> onSelected;

  @override
  Widget build(BuildContext context) {
    final imKader = {
      for (final p in PlayerPosition.values) p: (byPos[p] ?? const []).length,
    };
    String? fehlt((int, int, int) fm) => formationLuecke(fm, imKader: imKader);

    // **Nicht spielbare Formationen verschwinden nicht, sie stehen gedämpft
    // da.** Vorher waren sie schlicht weg — und wer sie zählt, kommt auf
    // sieben statt neun und hält das für einen Fehler. Ein Zustand „geht
    // nicht" muss sich von „gibt es nicht" unterscheiden; das ist dieselbe
    // Regel, an der in dieser App schon mehrfach etwas hing.
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
              child: PillChip(
                label: '${fm.$1}-${fm.$2}-${fm.$3}',
                gedaempft: fehlt(fm) != null,
                selected: fm == current,
                // **Der Tipp erklärt, statt nichts zu tun.** Ein gedämpftes
                // Element, das auf Berührung schweigt, ist genauso ratlos
                // machend wie ein fehlendes.
                onTap: () {
                  final grund = fehlt(fm);
                  if (grund == null) {
                    onSelected(fm);
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Für ${fm.$1}-${fm.$2}-${fm.$3} '
                        'fehlt dir $grund.',
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _Pitch extends StatelessWidget {
  const _Pitch({
    required this.slots,
    required this.playerById,
    required this.points,
    required this.clubIcons,
    required this.onOpenProfile,
    required this.onTapSlot,
    required this.onDrop,
    required this.gesperrt,
  });

  /// IDs der Spieler, deren Spiel schon läuft — festgenagelt (Migration 0084).
  final Set<String> gesperrt;

  final Map<PlayerPosition, List<String?>> slots;
  final Map<String, FantasyPlayer> playerById;
  final Map<FantasyPlayer, double> points;
  final Map<String, String?> clubIcons;
  final ValueChanged<FantasyPlayer> onOpenProfile;
  final void Function(PlayerPosition pos, int index)? onTapSlot;
  final void Function(_DragData data, PlayerPosition pos, int index)? onDrop;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      height: 420,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: pitchGradient,
      ),
      child: CustomPaint(
        painter: const PitchLinesPainter(),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
          child: Column(
            children: [
              for (final pos in _pitchOrder)
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (var i = 0; i < (slots[pos]?.length ?? 0); i++)
                        _slotTarget(pos, i),
                    ],
                  ),
                ),
            ],
          ),
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
      onWillAcceptWithDetails: (d) =>
          onDrop != null &&
          d.data.pos == pos &&
          d.data.from != (pos, i) &&
          !platzZu &&
          !gesperrt.contains(d.data.playerId),
      onAcceptWithDetails: (d) => onDrop!(d.data, pos, i),
      builder: (context, candidate, rejected) {
        final slot = _Slot(
          player: player,
          pos: pos,
          points: pts,
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
    required this.pos,
    required this.points,
    required this.iconUrl,
    required this.onProfile,
    required this.onEditPosition,
    this.highlight = false,
    this.gesperrt = false,
  });

  /// Sein Spiel läuft — der Platz ist zu. Wird als Schloss gezeigt, statt nur
  /// stumm nicht zu reagieren.
  final bool gesperrt;

  final FantasyPlayer? player;
  final PlayerPosition pos;
  final double? points;
  final String? iconUrl;

  /// Tippen auf den Spieler (Avatar/Name) → Profil.
  final VoidCallback? onProfile;

  /// Tippen auf die Positions-Pille → Aufstellung bearbeiten (Spielerwahl).
  final VoidCallback? onEditPosition;

  /// Hervorhebung, wenn ein passender Spieler über diesen Platz gezogen wird.
  final bool highlight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = player;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 70,
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
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
          // Avatar + Name: Spieler antippen → Profil (leer → Spielerwahl).
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: p != null ? onProfile : onEditPosition,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (p == null)
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white24,
                      border: Border.all(
                        color: positionColor(pos).withValues(alpha: 0.9),
                        width: 2,
                      ),
                    ),
                    child: const Icon(Icons.add, color: Colors.white, size: 22),
                  )
                else
                  Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      // Gesperrt: gedimmt, damit der Platz nicht nur stumm
                      // nicht reagiert, sondern erkennbar zu ist.
                      Opacity(
                        opacity: gesperrt ? 0.55 : 1,
                        child: ClubBadge(
                          club: p.club,
                          iconUrl: iconUrl,
                          size: 42,
                        ),
                      ),
                      // **Ausfall unten links, Spielsperre oben links.**
                      // Zwei verschiedene Aussagen: „sein Spiel läuft schon"
                      // ist eine Frist, „verletzt" ein Zustand. Sie dürfen
                      // nicht dieselbe Ecke teilen.
                      if (_ausfall(ref, p) != null)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _ausfall(ref, p)!.gesperrt
                                  ? const Color(0xFFF23030)
                                  : const Color(0xFFFFC83D),
                            ),
                            child: Icon(
                              _ausfall(ref, p)!.gesperrt
                                  ? Icons.block
                                  : Icons.medical_services_outlined,
                              size: 10,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      if (gesperrt)
                        Positioned(
                          top: 0,
                          left: 0,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: Colors.black87,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.lock,
                              size: 11,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          formatPoints(points ?? 0),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black38,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    p == null ? 'frei' : _short(p.name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 3),
          // Positions-Pille = Bearbeiten-Button (Spieler tauschen). Läuft sein
          // Spiel schon, steht dort „läuft" statt eines Knopfes, der nichts tut.
          if (gesperrt)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'läuft',
                style: TextStyle(color: Colors.white70, fontSize: 9),
              ),
            )
          else
            _posPill(context),
        ],
      ),
    );
  }

  Widget _posPill(BuildContext context) {
    final color = positionColor(pos);
    final editable = onEditPosition != null;
    if (!editable) {
      // Gesperrt: nur ein kleiner Farbpunkt als Positionshinweis.
      return Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black.withValues(alpha: 0.35)),
        ),
      );
    }
    // Bearbeitbar: Tausch-Symbol in der Positionsfarbe (dunkler Kreis + Ring,
    // damit es sich vom Rasen abhebt).
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onEditPosition,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 1.4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 2,
            ),
          ],
        ),
        child: Icon(Icons.swap_horiz, size: 15, color: color),
      ),
    );
  }

  static String _short(String name) {
    final parts = name.trim().split(' ');
    return parts.length > 1 ? parts.last : name;
  }
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

class _Bench extends StatelessWidget {
  const _Bench({
    required this.bench,
    required this.points,
    required this.clubIcons,
    required this.emptySlots,
    required this.onOpenProfile,
    required this.onOpenFreeAgency,
    required this.onDropToBench,
  });

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
  Widget build(BuildContext context) {
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
                else ...[
                  // Nach Position gruppiert (TW → ABW → MF → ST), farbig.
                  for (final pos in PlayerPosition.values)
                    if (bench.any((p) => p.position == pos)) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 4),
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
                            Text(
                              pos.label,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: positionColor(pos),
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final p in bench)
                            if (p.position == pos) _benchChip(p),
                        ],
                      ),
                    ],
                  // Freie Plätze durch Drops → Spieler holen.
                  if (emptySlots > 0) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 4),
                      child: Text(
                        'Freie Plätze ($emptySlots)',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var i = 0; i < emptySlots; i++)
                          _emptySlot(context),
                      ],
                    ),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _benchChip(FantasyPlayer p) {
    final color = positionColor(p.position);
    final chip = Chip(
      avatar: ClubBadge(club: p.club, iconUrl: clubIcons[p.club], size: 22),
      side: BorderSide(color: color.withValues(alpha: 0.6)),
      label: Text('${_short(p.name)} · ${formatPoints(points[p] ?? 0)}'),
    );
    // Tippen → Profil; langes Drücken → auf/vom Feld ziehen.
    final tappable = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onOpenProfile(p),
      child: chip,
    );
    if (onDropToBench == null) return tappable;
    final data = _DragData(playerId: p.id, pos: p.position);
    return LongPressDraggable<_DragData>(
      data: data,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _DragFeedback(player: p, iconUrl: clubIcons[p.club]),
      childWhenDragging: Opacity(opacity: 0.3, child: tappable),
      child: tappable,
    );
  }

  Widget _emptySlot(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onOpenFreeAgency,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: scheme.outline.withValues(alpha: 0.6),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 18, color: scheme.primary),
            const SizedBox(width: 6),
            Text(
              'Freier Platz — holen',
              style: TextStyle(color: scheme.primary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  static String _short(String name) {
    final parts = name.trim().split(' ');
    return parts.length > 1 ? parts.last : name;
  }
}

/// Bottom-Sheet: verfügbare Spieler einer Position auswählen (oder Slot leeren).
class _PlayerPicker extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
                    TextButton.icon(
                      onPressed: () =>
                          Navigator.of(context).pop(_clearSentinel),
                      icon: const Icon(Icons.remove_circle_outline, size: 18),
                      label: const Text('Slot leeren'),
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
                    final detail = <String>[
                      p.club,
                      if ((s?.goals ?? 0) > 0) '${s!.goals} Tor',
                      if (s?.cleanSheet ?? false) 'Zu Null',
                    ].join(' · ');
                    return ListTile(
                      leading: ClubBadge(
                        club: p.club,
                        iconUrl: clubIcons[p.club],
                      ),
                      title: Text(p.name),
                      subtitle: Text(detail),
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
