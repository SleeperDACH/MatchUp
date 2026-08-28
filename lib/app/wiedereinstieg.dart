import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/fantasy/providers.dart';
import '../features/news/providers.dart';
import '../features/tippspiel/providers.dart';

/// Was beim Zurückkommen aus dem Hintergrund neu geholt wird.
///
/// Die App hatte **keinen einzigen** `AppLifecycleState`-Beobachter. Alles,
/// was über einen `FutureProvider` kam, stand deshalb auf dem Stand des
/// letzten Ladens — und weil auch das Wiederaufwecken nichts auffrischte,
/// blieb den Leuten nur, die App wirklich zu beenden. Genau so wurde es
/// gemeldet: „muss man immer die App komplett schließen und neu öffnen".
///
/// Warum hier auch Streams stehen: Eine Realtime-Verbindung überlebt eine
/// längere Pause im Hintergrund nicht zwangsläufig. Sie verbindet sich zwar
/// neu, hat die Ereignisse der Auszeit aber nicht gesehen. Ein Neuaufbau holt
/// einen frischen Schnappschuss und ist billiger als ein falscher Stand.
///
/// **Bewusst nicht hier:** alles, was rein lokal ist (Favoriten,
/// Lesemarken) und alles, was der Nutzer gerade bearbeitet — ein Neuladen
/// unter den Händen wäre schlimmer als ein Wert von vor zehn Minuten.
void beimZurueckkommenAktualisieren(WidgetRef ref) {
  // Fantasy: Ligen, Mitglieder und alles, was am Beitritt hängt.
  ref.invalidate(myFantasyLeaguesProvider);
  ref.invalidate(fantasyManagersProvider);
  ref.invalidate(pendingMembersProvider);
  ref.invalidate(vacantTeamsProvider);

  // Tippspiel: eigene Runden und deren Punktestand.
  ref.invalidate(myRoundsProvider);
  ref.invalidate(myTipStatsProvider);

  // Nachrichtenleiste auf dem Startbildschirm.
  ref.invalidate(newsProvider);
}
