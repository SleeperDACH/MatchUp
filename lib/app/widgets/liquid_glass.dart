import 'dart:ui';

import 'package:flutter/material.dart';

/// „Liquid Glass"-Fläche im Stil von iOS 26: echter Hintergrund-Blur
/// ([BackdropFilter]), eine leicht durchscheinende Tönung, ein feiner
/// Licht-Rand oben und ein sanfter Glanz-Verlauf. Damit der Blur sichtbar
/// wird, muss Inhalt hinter dem Panel liegen (z. B. `extendBody`/scrollender
/// Inhalt) — auf komplett flachem Grund bleibt nur die Tönung.
class LiquidGlass extends StatelessWidget {
  const LiquidGlass({
    super.key,
    required this.child,
    this.borderRadius = 22,
    this.blur = 24,
    this.padding,
    this.tintOpacity,
  });

  final Widget child;
  final double borderRadius;
  final double blur;
  final EdgeInsetsGeometry? padding;

  /// Deckkraft der Grundtönung; ohne Angabe je nach Helligkeit gewählt.
  final double? tintOpacity;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Auf Dunkel eine aufhellende weiße Tönung, auf Hell eine weiße Milchglas-
    // Schicht — beides so, dass der Untergrund durchschimmert.
    final tint = (dark ? Colors.white : Colors.white)
        .withValues(alpha: tintOpacity ?? (dark ? 0.10 : 0.55));
    final radius = BorderRadius.circular(borderRadius);

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            // Diagonaler Glanz: oben links heller, unten rechts fast klar —
            // das gibt dem Glas Tiefe und die typische Lichtbrechung.
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                tint,
                tint.withValues(alpha: (tint.a * 0.55).clamp(0.0, 1.0)),
              ],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: dark ? 0.18 : 0.55),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.35 : 0.12),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
        ),
      ),
    );
  }
}
