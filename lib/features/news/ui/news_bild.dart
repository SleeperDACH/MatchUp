import 'package:flutter/material.dart';

/// **Das Titelbild einer Meldung** — an einer Stelle, für alle Listen.
///
/// Es kommt aus dem Feed, nicht aus dem Artikel: Gemessen am 03.09.2026
/// liefert Google News gar kein Bild je Meldung, kicker nur das Kanal-Logo,
/// die Sportschau ein 16:9-Bild in `content:encoded`. Deshalb steht sie in der
/// Edge Function `news` als erste Quelle — und deshalb gibt es trotzdem
/// Meldungen ohne Bild.
///
/// **Fehlt es, steht hier eine Fläche mit Zeitungssymbol**, keine Lücke: Eine
/// leere Stelle sähe aus wie ein Ladefehler, und dasselbe gilt für die
/// Sekunde, in der das Bild noch unterwegs ist.
class NewsBild extends StatelessWidget {
  const NewsBild({
    super.key,
    required this.url,
    this.breite = double.infinity,
    this.hoehe = double.infinity,
    this.radius = 9,
  });

  final String? url;
  /// Feste Maße für die Zeilenform; ohne Angabe füllt die Kachel, was sie
  /// bekommt (Kartenform mit `AspectRatio` darüber).
  final double breite;
  final double hoehe;
  final double radius;

  /// Blau des News-Bereichs (Abschnittsmarke auf dem Startbildschirm).
  static const _blau = Color(0xFF5B9DF9);

  @override
  Widget build(BuildContext context) {
    final ersatz = ColoredBox(
      color: _blau.withValues(alpha: 0.14),
      child: Center(
        child: Icon(Icons.newspaper,
            size: hoehe.isFinite ? hoehe * 0.32 : 34,
            color: _blau.withValues(alpha: 0.75)),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: breite,
        height: hoehe,
        child: url == null
            ? ersatz
            : Image.network(
                url!,
                fit: BoxFit.cover,
                loadingBuilder: (_, kind, fortschritt) =>
                    fortschritt == null ? kind : ersatz,
                errorBuilder: (_, _, _) => ersatz,
              ),
      ),
    );
  }
}
