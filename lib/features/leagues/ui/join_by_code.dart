import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/league_screen.dart';
import '../../../core/ui/eingabe_blatt.dart';
import '../../fantasy/models/fantasy_models.dart';
import '../../fantasy/providers.dart';
import '../../fantasy/ui/fantasy_league_screen.dart';
import '../../tippspiel/providers.dart';

/// Beitritt über einen **Einladungscode** — der einzige Weg in eine Liga, die
/// nicht öffentlich gelistet ist.
///
/// Lag früher in `home_screen.dart`. Herausgelöst, weil die Ligasuche denselben
/// Weg anbietet und der Homescreen sie bereits importiert: ein Import zurück
/// wäre ein Zyklus gewesen. Hier hängt die Funktion an keinem der beiden
/// Schirme.
///
/// Der Code sagt nicht, wozu er gehört. Deshalb wird er **erst als
/// Fantasy-Liga, dann als Tipprunde** versucht — und ein Fehlschlag der ersten
/// Stufe nur dann durchgereicht, wenn er *nicht* „Ungültiger Einladungscode"
/// heißt: sonst verschluckt die Fantasy-Stufe echte Gründe (Draft läuft
/// bereits, Liga voll) und der Nutzer sähe nur „Code passt zu nichts".
Future<void> joinAnyFlow(BuildContext context, WidgetRef ref) async {
  final code = await eingabe(
    context,
    titel: 'Beitreten',
    text: 'Einladungscode einer Fantasy-Liga oder Tipprunde.',
    feld: const EingabeFeld(
      label: 'Einladungscode',
      autokorrektur: false,
      grossschreibung: TextCapitalization.characters,
    ),
    ja: 'Beitreten',
    pruefe: (v) => v.isEmpty ? 'Bitte gib einen Code ein.' : null,
  );
  if (code == null || code.trim().isEmpty) return;
  if (!context.mounted) return;
  await beitretenMitCode(context, ref, code);
}

/// Der Beitritt selbst — vom Code-Dialog und vom Einladungslink benutzt
/// (`EinladungsWaechter`), damit beide Wege dieselben Fälle kennen: erst
/// Fantasy-Liga, dann Tipprunde, echte Gründe werden gemeldet.
Future<void> beitretenMitCode(
  BuildContext context,
  WidgetRef ref,
  String code,
) async {
  final trimmed = code.trim();

  // 1) Als Fantasy-Liga versuchen.
  try {
    final league = await ref
        .read(fantasyLeagueRepositoryProvider)
        .joinLeague(trimmed);
    ref.invalidate(myFantasyLeaguesProvider);
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => FantasyLeagueScreen(league: league)),
    );
    // Nach Draft-Start ist man nur „pending" — der Admin muss noch ein freies
    // Team zuweisen. Kurzer Hinweis, damit klar ist, warum kein Kader da ist.
    if (league.draftStatus != DraftStatus.setup && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Beigetreten! Der Draft läuft bereits — der Admin weist '
            'dir ein Team zu, sobald ein Platz frei ist.',
          ),
        ),
      );
    }
    return;
  } catch (e) {
    final msg = e.toString();
    if (!msg.contains('Ungültiger Einladungscode')) {
      // Der Code gehört zu einer Fantasy-Liga, der Beitritt scheiterte aber
      // aus einem anderen Grund (z. B. Draft bereits begonnen).
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            msg.contains('bereits begonnen')
                ? 'Der Draft dieser Liga hat bereits begonnen.'
                : 'Beitritt fehlgeschlagen: $e',
          ),
        ),
      );
      return;
    }
    // Sonst: kein Fantasy-Code -> als Tipprunde weiterversuchen.
  }

  // 2) Als Tipprunde versuchen.
  try {
    final round = await ref.read(tipRoundRepositoryProvider).joinRound(trimmed);
    ref.invalidate(myRoundsProvider);
    activateRound(ref, round);
    if (!context.mounted) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => LeagueScreen(round: round)));
  } catch (e) {
    if (!context.mounted) return;
    final msg = e.toString();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg.contains('Ungültiger Einladungscode')
              ? 'Dieser Code passt zu keiner Fantasy-Liga und keiner Tipprunde.'
              : 'Beitritt fehlgeschlagen: $e',
        ),
      ),
    );
  }
}
