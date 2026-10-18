import 'package:flutter/material.dart';

/// **Leuchtet einmal kurz auf, wenn [zaehler] steigt** — beim Tor.
///
/// Live-Daten kommen alle paar Sekunden; was sich geändert hat, sah man bisher
/// nur, wenn man die alte Zahl im Kopf hatte. Ein Aufleuchten von 900 ms sagt
/// „hier ist gerade etwas passiert", ohne Platz zu kosten (Design-Ideen
/// Punkt 6, 15.10.2026).
///
/// Nur beim **Steigen**: Ein Zähler, der fällt (korrigiertes Tor, neu geladene
/// Daten), ist kein Ereignis. Und nie beim ersten Aufbau — wer den Schirm
/// öffnet, hat nichts verpasst, was gerade passiert.
class Aufleuchten extends StatefulWidget {
  const Aufleuchten({
    super.key,
    required this.zaehler,
    required this.child,
    this.farbe,
    this.radius = const BorderRadius.all(Radius.circular(14)),
  });

  final int zaehler;
  final Widget child;

  /// Farbe des Leuchtens — Standard ist Weiß, also neutral; wer es einfärbt,
  /// braucht einen Grund (Grün für die eigene Seite).
  final Color? farbe;
  final BorderRadius radius;

  @override
  State<Aufleuchten> createState() => _AufleuchtenState();
}

class _AufleuchtenState extends State<Aufleuchten>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didUpdateWidget(covariant Aufleuchten alt) {
    super.didUpdateWidget(alt);
    if (widget.zaehler > alt.zaehler) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final farbe = widget.farbe ?? Colors.white;
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                // Schnell an, langsam aus.
                final t = _c.value;
                final staerke = t < 0.15 ? t / 0.15 : 1 - (t - 0.15) / 0.85;
                if (!_c.isAnimating || staerke <= 0) {
                  return const SizedBox.shrink();
                }
                return DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: widget.radius,
                    color: farbe.withValues(alpha: 0.22 * staerke),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
