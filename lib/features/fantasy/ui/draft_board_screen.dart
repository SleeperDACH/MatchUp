import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';
import '../../../app/widgets/pill_selector.dart';
import '../logic/reset_draft.dart';
import '../../../app/typografie.dart';
import 'draft_room_screen.dart' show DraftBoard;

/// Das Draft-Board zum **Nachschauen**, nach dem Draft — und in Ligen mit
/// Reset das **offizielle Board des Reset-Drafts** schon während der
/// Hinrunde (0145): Reihenfolge nach der aktuellen Tabelle, gehandelte Picks
/// mit ihrem neuen Besitzer. So sieht jeder, wo er gerade stünde.
///
/// Bewusst nicht der Draft-Raum: Der bringt einen Sekunden-Ticker, den
/// Auto-Pick-Umschalter, die Wunschliste und den Verfügbar-Tab mit — alles
/// Dinge, die nach dem letzten Pick nichts mehr tun, aber weiter Arbeit machen
/// (der Ticker baut das Board jede Sekunde neu auf). Hier steht nur das Board,
/// und es steht still.
class DraftBoardScreen extends ConsumerStatefulWidget {
  const DraftBoardScreen({super.key, required this.league, this.phase});

  final FantasyLeague league;

  /// Welcher Draft zuerst gezeigt wird; ohne Angabe der jüngere.
  final String? phase;

  @override
  ConsumerState<DraftBoardScreen> createState() => _DraftBoardScreenState();
}

class _DraftBoardScreenState extends ConsumerState<DraftBoardScreen> {
  /// Welcher Draft: `startup` (Hinrunde) oder `reset` (Rückrunde, 0143).
  String? _phase;

  @override
  Widget build(BuildContext context) {
    final id = widget.league.id;
    // Die Liga live, damit ein noch laufender Draft mitläuft, wenn jemand von
    // hier aus zusieht.
    final league =
        ref.watch(draftLeagueProvider(id)).valueOrNull ?? widget.league;
    final allePicks =
        ref.watch(draftPicksProvider(id)).valueOrNull ?? const <DraftPick>[];
    // **Zwei Drafts nach einem Reset** (0143): Umschalter, Standard ist der
    // jüngere. Ohne Reset-Picks gibt es nur einen und keinen Umschalter.
    final mitReset = league.resetAktiv || allePicks.any((p) => p.phase == 'reset');
    final phase = _phase ?? widget.phase ?? (mitReset ? 'reset' : 'startup');
    final picks = picksDerPhase(allePicks, phase);
    final alleManager = ref.watch(fantasyManagersProvider(id)).valueOrNull ??
        const <FantasyManager>[];

    // **Reset-Draft vor der Festschreibung:** Spalten nach der aktuellen
    // Tabelle (Tabellenletzter zuerst), alle Runden, gehandelte Picks mit
    // ihrem Besitzer. Ab dem Start des Reset-Drafts gilt `reset_position`.
    final rechte = phase == 'reset'
        ? ref.watch(draftRechteProvider(id)).valueOrNull
        : null;
    final vorschau = phase == 'reset' &&
        !alleManager.any((m) => m.resetPosition != null);
    final List<FantasyManager> managers;
    if (vorschau) {
      final folge = ref.watch(resetReihenfolgeProvider(id)) ?? const [];
      managers = [
        for (final (i, m) in folge.indexed) m.mitDraftPosition(i + 1),
      ];
    } else {
      managers = managerFuerDraft(alleManager, phase);
    }
    final pool =
        ref.watch(playerPoolProvider).valueOrNull ?? const <FantasyPlayer>[];
    final myId = ref.watch(currentUserProvider)?.id;

    // **Ein Draft, keine Phasen.** Der Umschalter zwischen Aufbau- und
    // U20-Draft ist mit dem Dynasty-Modus entfallen; das Board zeigt jetzt
    // schlicht alle Picks dieser Liga.
    //
    // Nur so viele Zeilen zeichnen, wie wirklich gedraftet wurde — sonst
    // hängen unter einem abgebrochenen Draft leere Runden.
    final rounds = phase == 'reset'
        ? league.rounds
        : picks.isEmpty
            ? 0
            : picks.map((p) => p.round).reduce((a, b) => a > b ? a : b);
    final leer = phase == 'reset' ? managers.isEmpty : picks.isEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Draft-Board')),
      body: leer && !mitReset
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'In dieser Liga wurde noch nicht gedraftet.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Column(
              children: [
                if (mitReset)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: PillSelector<String>(
                      options: const {
                        'startup': 'Hinrunde',
                        'reset': 'Rückrunde',
                      },
                      value: phase,
                      onSelect: (v) => setState(() => _phase = v),
                    ),
                  ),
                if (vorschau)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      'Reihenfolge nach der aktuellen Tabelle — sie steht mit '
                      'dem Reset am 24.12. fest.',
                      style: TextStyle(
                        fontSize: Schrift.label,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                Expanded(
                  child: DraftBoard(
                    picks: picks,
                    playerById: {for (final p in pool) p.id: p},
                    managers: managers,
                    maxTeams: league.maxTeams,
                    rounds: rounds,
                    // Nichts ist „am Zug" — das Board wird gelesen, nicht bedient.
                    currentManagerId: null,
                    currentRound: 0,
                    myId: myId,
                    showPlaceholders: false,
                    rechte: rechte,
                  ),
                ),
              ],
            ),
    );
  }
}
