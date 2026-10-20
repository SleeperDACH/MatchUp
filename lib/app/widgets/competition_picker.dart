import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../../core/ui/einstellungs_zeile.dart';
import 'competition_emblem.dart';
import 'league_logo.dart';

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
    // **Zeilen statt Pillen** (18.10.2026): Auf „Tippspiel erstellen" ist
    // jede Einstellung eine Zeile — die Wettbewerbe als Pillenhaufen waren
    // dort die eine Stelle, die anders aussah. Das Wappen bleibt vorn, weil
    // es die Erkennung trägt (siehe oben).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, league) in leagues.indexed) ...[
          if (i > 0) const EinstellungsTrenner(),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            secondary: _Wappen(leagueId: league.id),
            value: selected.contains(league.id),
            onChanged: (_) => onToggle(league.id),
            title: Text(league.name, style: einstellungsStil),
          ),
        ],
      ],
    );
  }
}

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
