import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/player_absence.dart';
import '../providers.dart';

/// **Verletzt oder gesperrt — als Zeichen an der Zeile, nicht erst im Profil.**
///
/// Gemeldet als: *„Man muss im Kaderbereich sehen, ohne in die Spieler-Karteien
/// reinzugehen, ob ein Spieler verletzt oder gesperrt ist."* Das Spielfeld
/// zeigte es längst (`_Eckzeichen` am Wappen), die Trade-Karte auch
/// ([SpielerKachel]) — die Kaderlisten daneben nicht: Bank, Spielerauswahl,
/// fremder Kader und die Bank im MatchUp führten denselben Spieler stumm.
///
/// **Rot für die Sperre, Gold für die Verletzung** — dieselbe Zuordnung wie
/// überall sonst in der App; zwei verschiedene Zustände dürfen nicht dieselbe
/// Farbe tragen. Das Symbol wiederholt die Aussage für den, der die Farben
/// nicht unterscheidet: durchgestrichener Kreis gegen Arztkoffer.
///
/// **Ein Symbol, kein Wort.** In einem Chip oder einer Listenzeile ist für
/// „Verletzung der hinteren Oberschenkelmuskulatur" kein Platz; der Grund
/// gehört ins Profil. Die Vorlesehilfe bekommt ihn trotzdem — über
/// [Semantics], und wer mit der Maus darauf zeigt, über den Tooltip.
class AusfallZeichen extends StatelessWidget {
  const AusfallZeichen({super.key, required this.ausfall, this.size = 13});

  final PlayerAbsence ausfall;

  /// Kantenlänge des Symbols. Voreinstellung passt in eine Chip- oder
  /// Listenzeile, ohne deren Höhe zu ändern.
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '${ausfall.kopf} · ${ausfall.grund}',
      child: Semantics(
        label: ausfall.kurz,
        child: Icon(
          ausfall.gesperrt ? Icons.block : Icons.medical_services_outlined,
          size: size,
          color: ausfallFarbe(ausfall),
        ),
      ),
    );
  }
}

/// Rot = Sperre, Gold = Verletzung.
Color ausfallFarbe(PlayerAbsence a) =>
    a.gesperrt ? const Color(0xFFF23030) : const Color(0xFFFFC83D);

/// Der Ausfall eines Spielers, oder `null`.
///
/// Steht hier und nicht in jedem Schirm noch einmal: Vier Listen lasen
/// denselben Provider auf vier leicht verschiedene Arten aus, und eine davon
/// hatte den Ausfall gar nicht erst geholt.
PlayerAbsence? ausfallFuer(WidgetRef ref, String playerId) =>
    (ref.watch(absencesProvider).valueOrNull ??
        const <String, PlayerAbsence>{})[playerId];
