import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/typografie.dart';
import '../logic/fantasy_scoring_engine.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';
import 'club_badge.dart';

/// Die Spielerkarte des Trade-Bereichs: Wappen, Name, Positionsmarke — als
/// **Zeile**, nicht als Sticker.
///
/// Sie steht an vier Stellen (Trade-Auswahl, Bestätigung, Angebotskarte,
/// Transfers) und sah bis dahin so aus: Positionsfarbe über die ganze Fläche,
/// das Wappen halb über den rechten Rand hinaus, Name und Position darüber.
/// Zwei Meldungen haben sie erledigt — erst überschnitt das Ausfall-Symbol das
/// Wappen, dann der Knopf ins Profil. **Beides war kein Platzierungsfehler,
/// sondern die Folge des Aufbaus:** Wer den halben Kartenrücken mit einem
/// Wappen füllt, hat für alles Weitere nur noch dessen Fläche übrig.
///
/// Jetzt hat jedes Ding seinen eigenen Platz in einer Reihe, und nichts liegt
/// mehr auf etwas anderem. Die Positionsfarbe trägt nur noch die kleine Marke
/// unter dem Namen — und die Fläche, wenn die Karte **gewählt** ist. Das ist
/// die Ausnahme, die die Kartenregel ausdrücklich zulässt: „etwas ist
/// ausgewählt" darf Farbe tragen.
class SpielerKachel extends ConsumerWidget {
  const SpielerKachel({
    super.key,
    required this.spieler,
    this.iconUrl,
    this.hervor = false,
    this.mitHaken = true,
    this.hoehe = 62,
    this.breite,
    this.onTap,
    this.onProfil,
    this.punkte,
  });

  final FantasyPlayer spieler;
  final String? iconUrl;

  /// Gewählt (Auswahl) beziehungsweise „das ist der Inhalt" (Angebotskarte):
  /// Die Fläche nimmt die Positionsfarbe auf, die Kante ebenso.
  final bool hervor;

  /// Häkchen, wenn [hervor] — nur in der Auswahl sinnvoll. In der
  /// Angebotskarte behauptet die Farbe keine Entscheidung, sie zeigt Inhalt.
  final bool mitHaken;

  final double hoehe;

  /// Feste Breite; ohne Angabe nimmt die Karte, was sie bekommt.
  ///
  /// In der Auswahlspalte füllt sie die Spalte — dort ist sie das einzige
  /// Element. Im Angebot stehen mehrere nebeneinander: Über die volle Breite
  /// gezogen wirkten sie viel zu groß für das bisschen Inhalt, den sie tragen.
  final double? breite;

  final VoidCallback? onTap;

  /// **Der zweite Weg von dieser Karte weg.** Wo der Tipp auf die Karte schon
  /// etwas anderes tut — in der Trade-Auswahl wählt er sie aus —, führt sonst
  /// nichts mehr ins Profil, und genau dort will man vor einem Angebot
  /// nachsehen. Ohne Angabe erscheint der Knopf nicht.
  final VoidCallback? onProfil;

  /// Saisonpunkte nach der Wertung **dieser Liga**, wenn der Aufrufer sie
  /// kennt. Auf dem Trade-Schirm ist das die Zahl, an der man ein Angebot
  /// überhaupt beurteilen kann — vorher stand sie dort nirgends, und wer
  /// wissen wollte, was er hergibt, musste jeden Spieler einzeln öffnen.
  final double? punkte;

  /// Vorname auf einen Buchstaben kürzen: „Jonas Urbig" → „J. Urbig".
  static String kurzerName(String full) {
    final parts = full.trim().split(RegExp(r'\s+'));
    if (parts.length < 2 || parts.first.isEmpty) return full;
    return '${parts.first[0]}. ${parts.sublist(1).join(' ')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final farbe = positionColor(spieler.position);
    final ausfall =
        (ref.watch(absencesProvider).valueOrNull ?? const {})[spieler.id];

    // Zwei Größen, ein Aufbau: In der Auswahl steht die Karte allein in ihrer
    // Spalte, in Angebot und Transfers zu mehreren nebeneinander.
    final klein = hoehe < 56;
    final wappen = klein ? 20.0 : 28.0;
    final rand = klein ? 8.0 : 10.0;

    final grund = theme.cardColor;
    final flaeche =
        hervor ? Color.alphaBlend(farbe.withValues(alpha: 0.20), grund) : grund;

    final karte = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: hoehe,
      width: breite,
      padding: EdgeInsets.symmetric(horizontal: rand),
      decoration: BoxDecoration(
        color: flaeche,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          // Gewählt trägt Farbe, alles andere die Haarlinie — dieselbe Kante
          // wie jede Karte dieser App.
          color: hervor
              ? farbe.withValues(alpha: 0.65)
              : theme.dividerColor,
          width: hervor ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          ClubBadge(club: spieler.club, iconUrl: iconUrl, size: wappen),
          SizedBox(width: klein ? 7 : 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Lange Namen schrumpfen, statt abgeschnitten zu werden.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    kurzerName(spieler.name),
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: klein ? Schrift.koerperKlein : Schrift.koerper,
                      fontWeight: FontWeight.w800,
                      height: 1.05,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                SizedBox(height: klein ? 2 : 3),
                Row(
                  children: [
                    _Positionsmarke(
                        position: spieler.position, gefuellt: hervor),
                    // **Fällt er aus, steht es neben der Position.** Ein
                    // Symbol, kein Text: Für „Muskuläre Probleme" ist hier
                    // kein Platz, und der genaue Grund gehört ins Profil. Rot
                    // für die Sperre, Gold für die Verletzung — dieselbe
                    // Bedeutung wie überall sonst in der App.
                    if (ausfall != null) ...[
                      const SizedBox(width: 5),
                      Icon(
                        ausfall.gesperrt
                            ? Icons.block
                            : Icons.medical_services_outlined,
                        size: klein ? 11 : 13,
                        color: ausfall.gesperrt
                            ? const Color(0xFFF23030)
                            : const Color(0xFFFFC83D),
                      ),
                    ],
                    if (punkte != null) ...[
                      const Spacer(),
                      Text(
                        formatPoints(punkte!),
                        style: TextStyle(
                          fontSize: klein ? Schrift.winzig : Schrift.klein,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (hervor && mitHaken)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(Icons.check_circle_rounded, size: 20, color: farbe),
            ),
          if (onProfil != null)
            // **Neben dem Inhalt, nicht darauf.** Der Knopf lag einmal oben
            // rechts auf dem Wappen; in einer Reihe braucht er dafür keinen
            // fremden Platz mehr.
            IconButton(
              tooltip: 'Profil von ${spieler.name}',
              onPressed: onProfil,
              iconSize: 18,
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 32, height: 44),
              icon: Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );

    // Ohne `onTap` kein `InkWell`: Eine Karte, die auf Tippen reagiert, ohne
    // etwas zu tun, verspricht etwas, das es nicht gibt.
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? karte : InkWell(onTap: onTap, child: karte),
    );
  }
}

/// Die Position als kleine Marke: „ABW" statt „Abwehr".
///
/// Sie trägt die Positionsfarbe, seit die Karte sie nicht mehr über die ganze
/// Fläche zieht — an einer Stelle, an der sie etwas unterscheidet, statt als
/// Dekoration. Gefüllt heißt „gewählt".
class _Positionsmarke extends StatelessWidget {
  const _Positionsmarke({required this.position, required this.gefuellt});

  final PlayerPosition position;
  final bool gefuellt;

  @override
  Widget build(BuildContext context) {
    final farbe = positionColor(position);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: gefuellt ? farbe : farbe.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        position.short,
        style: TextStyle(
          fontSize: Schrift.winzig,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          height: 1.3,
          // Auf dem gefüllten Gelb der Abwehr ist Weiß nicht zu lesen.
          color: gefuellt
              ? (position == PlayerPosition.def
                  ? const Color(0xFF12141C)
                  : Colors.white)
              : farbe,
        ),
      ),
    );
  }
}
