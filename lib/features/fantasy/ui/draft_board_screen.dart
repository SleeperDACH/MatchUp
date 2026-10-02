import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';
import 'draft_room_screen.dart' show DraftBoard;

/// Das Draft-Board zum **Nachschauen**, nach dem Draft.
///
/// Bewusst nicht der Draft-Raum: Der bringt einen Sekunden-Ticker, den
/// Auto-Pick-Umschalter, die Wunschliste und den Verfügbar-Tab mit — alles
/// Dinge, die nach dem letzten Pick nichts mehr tun, aber weiter Arbeit machen
/// (der Ticker baut das Board jede Sekunde neu auf). Hier steht nur das Board,
/// und es steht still.
class DraftBoardScreen extends ConsumerStatefulWidget {
  const DraftBoardScreen({super.key, required this.league});

  final FantasyLeague league;

  @override
  ConsumerState<DraftBoardScreen> createState() => _DraftBoardScreenState();
}

class _DraftBoardScreenState extends ConsumerState<DraftBoardScreen> {
  @override
  Widget build(BuildContext context) {
    final id = widget.league.id;
    // Die Liga live, damit ein noch laufender Draft mitläuft, wenn jemand von
    // hier aus zusieht.
    final league = ref.watch(draftLeagueProvider(id)).valueOrNull ??
        widget.league;
    final picks = ref.watch(draftPicksProvider(id)).valueOrNull ??
        const <DraftPick>[];
    final managers =
        ref.watch(fantasyManagersProvider(id)).valueOrNull ??
            const <FantasyManager>[];
    final pool =
        ref.watch(playerPoolProvider).valueOrNull ?? const <FantasyPlayer>[];
    final myId = ref.watch(currentUserProvider)?.id;

    // **Ein Draft, keine Phasen.** Der Umschalter zwischen Aufbau- und
    // U20-Draft ist mit dem Dynasty-Modus entfallen; das Board zeigt jetzt
    // schlicht alle Picks dieser Liga.
    //
    // Nur so viele Zeilen zeichnen, wie wirklich gedraftet wurde — sonst
    // hängen unter einem abgebrochenen Draft leere Runden.
    final rounds = picks.isEmpty
        ? 0
        : picks.map((p) => p.round).reduce((a, b) => a > b ? a : b);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Draft-Board'),
      ),
      body: picks.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('In dieser Liga wurde noch nicht gedraftet.',
                    textAlign: TextAlign.center),
              ),
            )
          : DraftBoard(
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
            ),
    );
  }
}
