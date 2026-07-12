import 'package:flutter/material.dart';

/// Kleiner Platzierungs-Chip für Liga-Zeilen: „Platz [rank]/[total]".
/// Rang 1 wird golden hervorgehoben. Bewegungspfeil optional.
class RankChip extends StatelessWidget {
  const RankChip({super.key, required this.rank, required this.total});

  final int rank;
  final int total;

  static const _gold = Color(0xFFFFC83D);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final top = rank == 1;
    final color = top ? _gold : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(top ? Icons.emoji_events : Icons.leaderboard_outlined,
              size: 13, color: color),
          const SizedBox(width: 4),
          Text('$rank/$total',
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
