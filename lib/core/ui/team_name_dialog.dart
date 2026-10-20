import 'package:flutter/material.dart';

import 'eingabe_blatt.dart';

/// Setzen/Ändern des ligaspezifischen Teamnamens, als Blatt (siehe
/// [eingabeBlatt]). Gibt den neuen Namen zurück (leerer String = zurücksetzen
/// auf den Nutzernamen) oder `null`, wenn abgebrochen wurde.
Future<String?> showTeamNameDialog(BuildContext context, {String? current}) {
  return eingabe(
    context,
    titel: 'Teamname',
    text: 'Steht in dieser Liga statt deines Nutzernamens. '
        'Leer lassen für den Nutzernamen.',
    feld: EingabeFeld(label: 'Teamname', start: current ?? '', maxLaenge: 24),
    ja: 'Speichern',
  );
}
