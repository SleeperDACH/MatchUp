import 'package:flutter/material.dart';

import 'eingabe_blatt.dart';

/// Umbenennen einer Liga/Tipprunde, als Blatt (siehe [eingabeBlatt]). Gibt
/// den neuen (getrimmten) Namen zurück oder `null` bei Abbruch. Ein zu kurzer
/// Name schließt das Blatt nicht, sondern sagt, was fehlt.
Future<String?> showRenameLeagueDialog(BuildContext context,
    {required String current}) {
  return eingabe(
    context,
    titel: 'Liga-Name ändern',
    feld: EingabeFeld(
      label: 'Name der Liga',
      start: current,
      maxLaenge: 64,
      grossschreibung: TextCapitalization.sentences,
    ),
    ja: 'Speichern',
    pruefe: (v) =>
        v.length < 3 ? 'Der Name braucht mindestens 3 Zeichen.' : null,
  );
}
