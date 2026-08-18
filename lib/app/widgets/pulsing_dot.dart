import 'package:flutter/material.dart';

import '../theme.dart';

/// Pulsierender Punkt — Signal für „läuft gerade" (Live-Status, Pick-Uhr).
class PulsingDot extends StatefulWidget {
  const PulsingDot({super.key, this.size = 8, this.color = MatchUpColors.red});

  final double size;

  /// Signalfarbe; Standard ist das Live-Rot.
  final Color color;

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 1.0, end: 0.25)
          .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
            color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}
