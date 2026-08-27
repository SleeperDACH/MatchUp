import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/fantasy_models.dart';
import '../providers.dart';

/// Startet den Draft — **nur nach ausdrücklicher Bestätigung.**
///
/// Der Start ist nicht rückgängig zu machen: Er friert die Reihenfolge ein und
/// setzt die ganze Liga in Gang. Deshalb steht davor immer ein Dialog, der
/// sagt, was gleich passiert.
///
/// Liegt hier und nicht im Draft-Raum, weil zwei Wege hineinführen: der Knopf
/// im Raum und der Auftrags-Kopf der Liga-Übersicht („Draft starten"). Der
/// zweite hat vorher nur den Raum geöffnet — ein Knopf, der ankündigt zu
/// starten und stattdessen navigiert, ist eine kleine Lüge, und die
/// Rückfrage stand dann nur auf dem einen Weg.
///
/// Gibt `true` zurück, wenn der Draft tatsächlich gestartet wurde.
Future<bool> draftStartenMitBestaetigung(
  BuildContext context,
  WidgetRef ref,
  FantasyLeague league,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final isU20 = league.draftPhase == DraftPhase.u20;
  final bestaetigt = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(isU20 ? 'U20-Draft starten?' : 'Draft starten?'),
      content: Text(
        isU20
            ? 'Der U20-Draft startet mit der aktuellen Reihenfolge und kann '
                  'nicht mehr geändert werden.'
            : 'Der Draft startet mit der aktuellen Reihenfolge und kann nicht '
                  'mehr geändert werden. '
                  '${league.draftOrderMode == 'manual' ? '' : 'Die Reihenfolge wird beim Start zufällig ausgelost.'}',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Starten'),
        ),
      ],
    ),
  );
  if (bestaetigt != true) return false;

  try {
    final repo = ref.read(draftRepositoryProvider);
    // Im U20-Setup startet der U20-Draft, sonst der Haupt-Draft.
    if (isU20) {
      await repo.startU20Draft(league.id);
    } else {
      await repo.startDraft(league.id);
    }
    ref.invalidate(draftLeagueProvider(league.id));
    ref.invalidate(fantasyManagersProvider(league.id));
    return true;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Fehlgeschlagen: $e')));
    return false;
  }
}
