import 'package:flutter/material.dart';

/// **Text, der nie mitten im Wort umbricht.**
///
/// Auf den schmalen Ligakarten des Startbildschirms brach „Übungsliga" zweimal
/// mitten im Wort — beim Wechsel auf Inter (14.10.2026) und wieder, als die
/// Schriftleiter auf vier Stufen ging (15.10.2026, 13 → 14 Punkt). Jede Größe,
/// die man dort von Hand einstellt, hält nur bis zum nächsten Namen.
///
/// Dieser Baustein misst stattdessen das **längste Wort**: Passt es nicht in
/// die Breite, schrumpft die ganze Schrift genau so weit, dass es passt.
/// Dieselbe Regel wie überall in der App — schrumpfen statt kappen —, nur für
/// mehrzeiligen Text, den `FittedBox` nicht kann (er nähme die Zeilenumbrüche
/// weg).
class GanzeWoerter extends StatelessWidget {
  const GanzeWoerter(
    this.text, {
    super.key,
    required this.style,
    this.maxLines = 2,
  });

  final String text;
  final TextStyle style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      // Gemessen wird mit dem **aufgelösten** Stil: Der übergebene trägt
      // keine Schriftfamilie, und ohne sie misst `TextPainter` in der
      // Ersatzschrift — im Test sind das gleich breite Kästchen.
      final stil = DefaultTextStyle.of(context).style.merge(style);
      final groesse = stil.fontSize ?? 14;
      final scaler = MediaQuery.textScalerOf(context);
      var breitestes = 0.0;
      for (final wort in text.split(RegExp(r'\s+'))) {
        if (wort.isEmpty) continue;
        final tp = TextPainter(
          text: TextSpan(text: wort, style: stil),
          textDirection: Directionality.of(context),
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        if (tp.width > breitestes) breitestes = tp.width;
      }
      final faktor = constraints.maxWidth.isFinite &&
              breitestes > constraints.maxWidth &&
              breitestes > 0
          ? (constraints.maxWidth / breitestes) * 0.98
          : 1.0;
      return Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: style.copyWith(fontSize: groesse * faktor),
      );
    });
  }
}
