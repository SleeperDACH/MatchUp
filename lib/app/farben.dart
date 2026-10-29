import 'package:flutter/material.dart';

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
    auswahlFlaeche: Color(0x24EDEFF4), // Snow 14 %
    auswahlKante: Color(0x8CEDEFF4), // Snow 55 %
    naviGlas: Color(0x94000000), // Schwarz 58 %
    schimmer: Color(0x14FFFFFF),
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
