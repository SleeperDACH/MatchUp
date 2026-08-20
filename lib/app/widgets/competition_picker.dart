import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../theme.dart';
import 'competition_emblem.dart';
import 'league_logo.dart';
import 'pill_selector.dart';

/// Mehrfachauswahl von Wettbewerben — mit **Wappen**, nicht nur Namen.
///
/// Vorher standen hier Materials `FilterChip`s: reine Textpillen, deren
/// ausgewählter Zustand aus der Material-Vorgabe kam. Ein Wettbewerb ist aber
/// vor allem an seinem Zeichen zu erkennen; „Bundesliga" und „2. Bundesliga"
/// unterscheiden sich als Text nur in zwei Zeichen, als Logo sofort.
class CompetitionPicker extends StatelessWidget {
  const CompetitionPicker({
    super.key,
    required this.leagues,
    required this.selected,
    required this.onToggle,
  });

  final List<LeagueInfo> leagues;

  /// IDs der gewählten Wettbewerbe.
  final Set<String> selected;

  /// Wird mit der angetippten ID gerufen; der Aufrufer entscheidet, ob die
  /// Abwahl erlaubt ist (mindestens einer muss bleiben).
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final league in leagues)
          PillChip(
            label: league.name,
            selected: selected.contains(league.id),
            outlined: true,
            onTap: () => onToggle(league.id),
            leading: _Wappen(leagueId: league.id),
            trailing: selected.contains(league.id)
                ? const Icon(Icons.check_rounded,
                    size: 16, color: MatchUpColors.green)
                : null,
          ),
      ],
    );
  }
}

/// Wettbewerbslogo auf hellem Plättchen — die offiziellen Logos sind für
/// hellen Untergrund gezeichnet und würden auf dem dunklen Grund absaufen.
class _Wappen extends StatelessWidget {
  const _Wappen({required this.leagueId});

  final String leagueId;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(6),
      ),
      child: LeagueLogo(
        leagueId: leagueId,
        size: 17,
        fallback: CompetitionEmblem(leagueId: leagueId, size: 17),
      ),
    );
  }
}
