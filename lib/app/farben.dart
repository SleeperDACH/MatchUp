import 'package:flutter/material.dart';

import 'theme.dart';

/// Die Signal- und Zustandsfarben der App — **je Helligkeit eine Fassung**.
///
/// Bis zum hellen Modus standen diese Farben als feste Werte quer durch den
/// Code (Gold allein achtmal als `#FFC83D`). Auf Schwarz waren sie richtig, auf
/// Weiß sind sie es nicht: Gemessen hat das Markengrün dort einen Kontrast von
/// 1,8:1, das Gold 1,6:1 — beides unlesbar. Die hellen Fassungen sind dieselben
/// Farbtöne, dunkler gesetzt, und liegen alle bei mindestens 4,5:1 auf Weiß
/// (`test/hell_kontrast_test.dart` hält das fest).
///
/// **Die dunklen Werte sind exakt die bisherigen.** Der dunkle Modus ändert
/// sich durch diese Datei um keinen Pixel.
///
/// Zugriff über `context.farben` (oder `Theme.of(context).extension<…>()`).
@immutable
class MatchUpFarben extends ThemeExtension<MatchUpFarben> {
  const MatchUpFarben({
    required this.gruen,
    required this.rot,
    required this.gold,
    required this.blau,
    required this.tuerkis,
    required this.orange,
    required this.violett,
    required this.silber,
    required this.bronze,
    required this.neutral,
    required this.auswahlFlaeche,
    required this.auswahlKante,
    required this.naviGlas,
    required this.schimmer,
    required this.vorne,
  });

  /// Grün: ich / gut / läuft. Als Schrift, Symbol und Strich.
  final Color gruen;

  /// Rot: live / schlecht / Fehler.
  final Color rot;

  /// Gold: hier ist etwas zu tun; Tippspiel; Platz 1.
  final Color gold;

  /// Blau: Torwart, Vereine & News, zweite Liga.
  final Color blau;

  /// Türkis: Tordifferenz, Conference League.
  final Color tuerkis;

  /// Orange: Europa League, 3. Liga.
  final Color orange;

  /// Violett: Relegation.
  final Color violett;

  /// Silber (Platz 2) und Bronze (Platz 3).
  final Color silber;
  final Color bronze;

  /// Neutrales Grau für Zustände ohne Wertung (Unentschieden, Siegchance).
  final Color neutral;

  /// „Gewählt / das bist du": helle Fläche auf Dunkel, dunkle auf Hell.
  final Color auswahlFlaeche;
  final Color auswahlKante;

  /// Tönung der schwebenden Navileiste über beliebigem Inhalt.
  final Color naviGlas;

  /// Der leise Lichtschimmer, den Flächen auf Dunkel tragen (weiß, wenige
  /// Prozent); auf Hell ein ebenso leiser Schatten.
  final Color schimmer;

  /// Die stärkste Schrift: reines Weiß auf Dunkel, Schwarz auf Hell. Für die
  /// Stellen, die im dunklen Modus bewusst Weiß statt Snow tragen (große
  /// Zahlen, Namen im MatchUp-Kasten).
  final Color vorne;

  static const dunkel = MatchUpFarben(
    gruen: Color(0xFF4ADE6A),
    rot: Color(0xFFF23030),
    gold: Color(0xFFFFC83D),
    blau: Color(0xFF5B9DF9),
    tuerkis: Color(0xFF4FC3A1),
    orange: Color(0xFFF97316),
    violett: Color(0xFFA78BFA),
    silber: Color(0xFFC4CBD4),
    bronze: Color(0xFFCD8B4E),
    neutral: Color(0xFF9AA0AA),
    // Exakt die Werte, die vorher als `withValues(alpha: …)` im Code standen —
    // als Hexwert gerundet wichen sie um eine Stufe ab, und der dunkle Modus
    // soll sich um keinen Pixel ändern.
    auswahlFlaeche: Color.from(alpha: 0.14, red: 237 / 255, green: 239 / 255, blue: 244 / 255),
    auswahlKante: Color.from(alpha: 0.55, red: 237 / 255, green: 239 / 255, blue: 244 / 255),
    naviGlas: Color.from(alpha: 0.58, red: 0, green: 0, blue: 0),
    schimmer: Color.from(alpha: 0.08, red: 1, green: 1, blue: 1),
    vorne: Color(0xFFFFFFFF),
  );

  static const hell = MatchUpFarben(
    gruen: Color(0xFF1A7F37),
    rot: Color(0xFFD70015),
    gold: Color(0xFF9A6700),
    blau: Color(0xFF1F6FE5),
    tuerkis: Color(0xFF0F7F68),
    orange: Color(0xFFC2410C),
    violett: Color(0xFF7C3AED),
    silber: Color(0xFF6B7280),
    bronze: Color(0xFF9A5B2A),
    neutral: Color(0xFF6E6E73),
    auswahlFlaeche: Color(0x12000000), // Schwarz 7 %
    auswahlKante: Color(0x73000000), // Schwarz 45 %
    naviGlas: Color(0xE0FFFFFF), // Weiß 88 %
    schimmer: Color(0x0A000000),
    vorne: Color(0xFF000000),
  );

  @override
  MatchUpFarben copyWith() => this;

  @override
  MatchUpFarben lerp(MatchUpFarben? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return MatchUpFarben(
      gruen: l(gruen, other.gruen),
      rot: l(rot, other.rot),
      gold: l(gold, other.gold),
      blau: l(blau, other.blau),
      tuerkis: l(tuerkis, other.tuerkis),
      orange: l(orange, other.orange),
      violett: l(violett, other.violett),
      silber: l(silber, other.silber),
      bronze: l(bronze, other.bronze),
      neutral: l(neutral, other.neutral),
      auswahlFlaeche: l(auswahlFlaeche, other.auswahlFlaeche),
      auswahlKante: l(auswahlKante, other.auswahlKante),
      naviGlas: l(naviGlas, other.naviGlas),
      schimmer: l(schimmer, other.schimmer),
      vorne: l(vorne, other.vorne),
    );
  }
}

extension MatchUpFarbenContext on BuildContext {
  /// Die Signalfarben des aktuellen Themes. Fehlt die Erweiterung (ein Test
  /// ohne App-Theme), gilt die dunkle Fassung — der bisherige Stand.
  MatchUpFarben get farben =>
      Theme.of(this).extension<MatchUpFarben>() ?? MatchUpFarben.dunkel;

  /// Wahr im hellen Modus.
  bool get istHell => Theme.of(this).brightness == Brightness.light;
}

/// Ein Bereich, der **in beiden Modi dunkel** bleibt: das Spielfeld, Bilder
/// mit dunklem Grund. Der Rasen ist Inhalt wie ein Foto — auf ihm stehen
/// weiße Namen, und eine Kachel, die sich nach dem hellen Theme richtet, wäre
/// dort weiß auf hellem Kasten (so geschehen beim Prognose-Kasten).
///
/// Alles darunter liest das dunkle Theme — auch was später dazukommt.
class DunkleInsel extends StatelessWidget {
  const DunkleInsel({super.key, required this.child});

  final Widget child;

  static final _dunkel = buildAppTheme(brightness: Brightness.dark);

  @override
  Widget build(BuildContext context) {
    if (!context.istHell) return child;
    return Theme(data: _dunkel, child: child);
  }
}
