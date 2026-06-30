import 'package:flutter/material.dart';

import '../theme.dart';

/// Pulsierender roter Punkt — Signal für „läuft gerade" (Live-Status).
class PulsingDot extends StatefulWidget {
  const PulsingDot({super.key, this.size = 8});

  final double size;

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
        decoration: const BoxDecoration(
            color: MatchUpColors.red, shape: BoxShape.circle),
      ),
    );
  }
}
