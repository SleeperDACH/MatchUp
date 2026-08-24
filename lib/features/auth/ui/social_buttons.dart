import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart' show AppleLogoPainter;

/// Die Anmeldeknöpfe von Google und Apple.
///
/// Beide Anbieter schreiben Logo, Beschriftung und Kontrast vor, und beide
/// verlangen auf dunklem Grund die **helle** Variante — deshalb stehen hier
/// zwei weiße Flächen und nicht das dunkle Glas der übrigen Karte. Das ist
/// kein Bruch aus Versehen: Ein Anmeldeknopf, den man nicht als den von Google
/// erkennt, verfehlt seinen einzigen Zweck.
///
/// Form und Höhe kommen dagegen aus der App (Pille, 48 Punkt wie „Anmelden"),
/// damit die drei Knöpfe übereinander eine Reihe ergeben und nicht drei
/// Fundstücke.

/// Trennlinie zwischen Anbieter- und E-Mail-Anmeldung.
class SocialDivider extends StatelessWidget {
  const SocialDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final farbe = Theme.of(context).colorScheme.onSurfaceVariant;
    final linie = Expanded(child: Divider(color: farbe.withValues(alpha: 0.35)));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(
        children: [
          linie,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'oder',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: farbe),
            ),
          ),
          linie,
        ],
      ),
    );
  }
}

/// Gemeinsame Hülle: weiße Pille, Logo links, Text mittig.
class _AnbieterKnopf extends StatelessWidget {
  const _AnbieterKnopf({
    required this.logo,
    required this.text,
    required this.onPressed,
  });

  final Widget logo;
  final String text;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1F1F1F),
          disabledBackgroundColor: Colors.white.withValues(alpha: 0.4),
          disabledForegroundColor: const Color(0xFF1F1F1F).withValues(alpha: 0.4),
          // Nicht `const TextStyle(...)`: `styleFrom` **ersetzt** den Stil des
          // Knopfes, statt ihn zu ergänzen. Ohne Familie fiele die
          // Beschriftung auf die Systemschrift zurück und stünde als einzige
          // Zeile der App in einer fremden Schrift da.
          textStyle: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Höhe vorgeben, Breite dem Logo überlassen: Das Apple-Zeichen
            // ist schmaler als hoch (25:31), in einem Quadrat würde es in die
            // Breite gezogen — bei einer Marke fällt genau das auf.
            SizedBox(height: 20, child: logo),
            const SizedBox(width: 12),
            // Der Text darf schrumpfen statt zu kappen: „Mit Google anmelden"
            // ist auf einem schmalen Gerät samt Logo dicht an der Kante.
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(text, maxLines: 1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// „Mit Google anmelden" — weiße Fläche, mehrfarbiges „G", wie von Googles
/// Markenrichtlinien verlangt.
class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return _AnbieterKnopf(
      logo: SvgPicture.string(_googleG, width: 20, height: 20),
      text: 'Mit Google anmelden',
      onPressed: onPressed,
    );
  }
}

/// „Mit Apple anmelden" — weiße Fläche mit schwarzem Logo. Apple verlangt auf
/// dunklem Grund genau diese Variante; der schwarze Knopf verschwände im
/// fast schwarzen Hintergrund der App.
class AppleSignInButton extends StatelessWidget {
  const AppleSignInButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return _AnbieterKnopf(
      // Das Logo sitzt optisch tief, wenn es auf der Grundlinie steht —
      // Apples eigener Knopf hebt es leicht an.
      logo: const Padding(
        padding: EdgeInsets.only(bottom: 2),
        child: AspectRatio(
          aspectRatio: 25 / 31,
          child:
              CustomPaint(painter: AppleLogoPainter(color: Color(0xFF1F1F1F))),
        ),
      ),
      text: 'Mit Apple anmelden',
      onPressed: onPressed,
    );
  }
}

/// Googles „G" als SVG. Liegt bewusst hier und nicht unter `assets/`: Das
/// Zeichen gehört zum Knopf, nicht zum Bildbestand der App, und ein Logo, das
/// beim Ausliefern vergessen wird, macht aus dem Anmeldeknopf ein Rätsel.
const _googleG = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">
<path fill="#4285F4" d="M45.12 24.5c0-1.56-.14-3.06-.4-4.5H24v8.51h11.84c-.51 2.75-2.06 5.08-4.39 6.64v5.52h7.11c4.16-3.83 6.56-9.47 6.56-16.17z"/>
<path fill="#34A853" d="M24 46c5.94 0 10.92-1.97 14.56-5.33l-7.11-5.52c-1.97 1.32-4.49 2.1-7.45 2.1-5.73 0-10.58-3.87-12.31-9.07H4.34v5.7C7.96 41.07 15.4 46 24 46z"/>
<path fill="#FBBC05" d="M11.69 28.18C11.25 26.86 11 25.45 11 24s.25-2.86.69-4.18v-5.7H4.34C2.85 17.09 2 20.45 2 24s.85 6.91 2.34 9.88l7.35-5.7z"/>
<path fill="#EA4335" d="M24 10.75c3.23 0 6.13 1.11 8.41 3.29l6.31-6.31C34.91 4.18 29.93 2 24 2 15.4 2 7.96 6.93 4.34 14.12l7.35 5.7c1.73-5.2 6.58-9.07 12.31-9.07z"/>
</svg>
''';
