import 'package:flutter/material.dart';

/// Warnhinweis, wenn ein Kader das Limit ([limit] = Kadergröße) überschreitet:
/// Solange zu viele Spieler im Kader sind, gibt es keine Punkte. Sobald genug
/// Spieler abgegeben wurden ([count] <= [limit]), verschwindet der Hinweis.
class RosterLimitBanner extends StatelessWidget {
  const RosterLimitBanner({
    super.key,
    required this.count,
    required this.limit,
    this.margin = const EdgeInsets.fromLTRB(12, 12, 12, 0),
  });

  final int count;
  final int limit;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    if (count <= limit) return const SizedBox.shrink();
    const red = Color(0xFFF23030);
    final over = count - limit;
    return Container(
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: red.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: red.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: red, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Kaderlimit überschritten: $count/$limit Spieler',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: red)),
                const SizedBox(height: 2),
                Text(
                  'Keine Punkte, solange der Kader zu groß ist. Gib noch '
                  '$over Spieler ab, dann zählt dein Team wieder.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
