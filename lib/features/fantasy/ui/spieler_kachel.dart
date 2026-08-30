import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/fantasy_models.dart';
import '../providers.dart';
import 'club_badge.dart';

/// Die Spielerkarte des Trade-Bereichs: Positionsfarbe als Fläche, das Wappen
/// groß und halb über den rechten Rand hinaus, Name und Position links.
///
/// Sie steckte als private `_tile` in der Auswahlspalte des Trade-Screens und
/// ist herausgelöst, weil die **Angebotskarte** dieselbe Darstellung braucht.
/// Dort standen die Spieler vorher als Komma-Liste („J. Urbig, S. Kolo Muani")
/// — dieselbe Auskunft, aber ohne Verein, ohne Position und ohne
/// Wiedererkennung. Wer ein Angebot beurteilen soll, schaut auf Spieler, nicht
/// auf einen Satz.
///
/// [hervor] steuert die Lautstärke: In der Auswahl heißt es „ausgewählt" (mit
/// Häkchen), im Angebot heißt es schlicht „das ist der Inhalt" — deshalb ist
/// das Häkchen über [mitHaken] abschaltbar.
class SpielerKachel extends ConsumerWidget {
  const SpielerKachel({
    super.key,
    required this.spieler,
    this.iconUrl,
    this.hervor = false,
    this.mitHaken = true,
    this.hoehe = 110,
    this.breite,
    this.onTap,
  });

  final FantasyPlayer spieler;
  final String? iconUrl;

  /// Kräftige Positionsfarbe statt gedämpfter Fläche.
  final bool hervor;

  /// Häkchen oben links, wenn [hervor] — nur in der Auswahl sinnvoll.
  final bool mitHaken;

  final double hoehe;

  /// Feste Breite; ohne Angabe nimmt die Karte, was sie bekommt.
  ///
  /// In der Auswahlspalte füllt sie die Spalte — dort ist sie das einzige
  /// Element. Im Angebot stehen mehrere nebeneinander: Über die volle Breite
  /// gezogen wirkten sie viel zu groß für das bisschen Inhalt, den sie tragen.
  final double? breite;

  final VoidCallback? onTap;

  /// Vorname auf einen Buchstaben kürzen: „Jonas Urbig" → „J. Urbig".
  static String kurzerName(String full) {
    final parts = full.trim().split(RegExp(r'\s+'));
    if (parts.length < 2 || parts.first.isEmpty) return full;
    return '${parts.first[0]}. ${parts.sublist(1).join(' ')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final base = positionColor(spieler.position);
    // Hervorgehoben: kräftige Positionsfarbe (Sticker-Optik), Text lesbar (auf
    // Gelb schwarz). Sonst direkt dunkel gezeichnet — kein aufgesetztes
    // Overlay, damit die Ränder nicht „durchleuchten".
    final fg = hervor
        ? (spieler.position == PlayerPosition.def
            ? Colors.black
            : Colors.white)
        : Colors.white.withValues(alpha: 0.82);
    final gradient = hervor
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(base, Colors.white, 0.14)!,
              base,
              Color.lerp(base, Colors.black, 0.36)!,
            ],
          )
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(base, const Color(0xFF12141C), 0.70)!,
              Color.lerp(base, const Color(0xFF12141C), 0.85)!,
            ],
          );

    // Wappen und Schrift folgen der Kartenhöhe, damit die kompakte Fassung im
    // Angebot nicht wie die große mit abgeschnittenem Rand aussieht.
    final wappen = hoehe * 0.98;
    final namensgroesse = hoehe < 80 ? 13.0 : 15.0;
    // Der Platz, den das überstehende Wappen rechts wegnimmt — mit der
    // Kartenhöhe skaliert, nicht fest. Bei 60 px fest blieb auf einer schmalen
    // Karte für den Namen fast nichts übrig.
    final rechterRand = wappen * 0.55;
    final ausfall =
        (ref.watch(absencesProvider).valueOrNull ?? const {})[spieler.id];

    final karte = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: hoehe,
      width: breite,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: gradient,
        border: Border.all(
          color: hervor && mitHaken
              ? Colors.white
              : Colors.white.withValues(alpha: 0.05),
          width: hervor && mitHaken ? 3 : 1,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // **Fällt er aus, steht es auf der Karte.** Ein Symbol, kein Text:
          // Auf 124 Punkten Breite ist für „Muskuläre Probleme" kein Platz,
          // und der genaue Grund gehört ohnehin ins Profil. Rot für die
          // Sperre (eine Folge des eigenen Verhaltens), Gold für die
          // Verletzung — dieselbe Bedeutung wie überall sonst in der App.
          if (ausfall != null)
            // **Oben rechts, nicht links.** Links steht der Name, und auf
            // einer 42 Punkte hohen Kachel überlappte das Symbol ihn. Rechts
            // liegt nur das halb durchscheinende Wappen — dort nimmt es
            // nichts weg.
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(7, 3, 6, 4),
                decoration: BoxDecoration(
                  color: (ausfall.gesperrt
                          ? const Color(0xFFF23030)
                          : const Color(0xFFFFC83D))
                      .withValues(alpha: 0.92),
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(15),
                    bottomLeft: Radius.circular(10),
                  ),
                ),
                child: Icon(
                  ausfall.gesperrt
                      ? Icons.block
                      : Icons.medical_services_outlined,
                  size: hoehe < 60 ? 10 : 13,
                  color: Colors.black,
                ),
              ),
            ),
          Positioned(
            right: -wappen * 0.48,
            top: 0,
            bottom: 0,
            child: Center(
              child: Opacity(
                opacity: hervor ? 1 : 0.6,
                child: ClubBadge(
                    club: spieler.club, iconUrl: iconUrl, size: wappen),
              ),
            ),
          ),
          Positioned(
            left: hervor && mitHaken ? 10 : 12,
            right: rechterRand,
            top: 0,
            bottom: 0,
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
                      fontSize: namensgroesse,
                      fontWeight: FontWeight.w800,
                      height: 1.05,
                      color: fg,
                      shadows: hervor &&
                              spieler.position == PlayerPosition.def
                          ? null
                          : const [
                              Shadow(color: Colors.black38, blurRadius: 3)
                            ],
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  spieler.position.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: fg.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
          if (hervor && mitHaken)
            Positioned(
              left: 8,
              top: 8,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 4),
                  ],
                ),
                padding: const EdgeInsets.all(3),
                child: Icon(Icons.check_rounded,
                    size: 18, color: base, weight: 900),
              ),
            ),
        ],
      ),
    );

    // Ohne `onTap` kein `InkWell`: Eine Karte, die auf Tippen reagiert, ohne
    // etwas zu tun, verspricht etwas, das es nicht gibt.
    return Material(
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? karte
          : InkWell(onTap: onTap, child: karte),
    );
  }
}
