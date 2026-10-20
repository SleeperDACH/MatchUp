/// **Die Favoriten-Leiste oben auf der Startseite** (18.10.2026, auf Ansage:
/// „wenn man keine Favoriten hat, oben eine Leiste, in der man einen Favoriten
/// auswählen kann, damit die Leute darauf hingewiesen werden").
///
/// Ohne Favoriten fehlte der Startseite ihr Kopf: Die Kopfkarte mit dem
/// nächsten Spiel blendet sich dann aus, „Mein Wochenende" ebenso — und
/// nirgends stand, dass es beides gibt. Die Leiste steht an genau dieser
/// Stelle und nimmt die Wahl **ohne Umweg** an: ein Tipp aufs Wappen, und die
/// Kopfkarte erscheint an ihrer Stelle. Andere Wettbewerbe liegen einen Tipp
/// weiter im Verwaltungsschirm.
///
/// Drei Regeln:
///  * **Erst nach dem Laden.** Vor dem Laden ist die Liste leer, ohne dass es
///    keine Favoriten gibt — sonst sähe jeder beim Start kurz die Aufforderung
///    ([FavoritesNotifier.geladen]).
///  * **Nur Vereine zählen.** Wer bloß die Bundesliga als Wettbewerb
///    favorisiert hat, bekommt trotzdem keine Kopfkarte — die hängt an einem
///    Verein.
///  * **Gold, nicht Grün:** Gold heißt in dieser App „hier ist etwas zu tun".
///    Die Kante bleibt die Haarlinie.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logic/vereins_kuerzel.dart';
import '../core/models/models.dart';
import '../features/auth/providers.dart';
import '../features/favorites/favorites.dart';
import '../features/favorites/ui/favorites_manage_screen.dart';
import '../features/tippspiel/ui/team_badge.dart';
import 'typografie.dart';
import 'widgets/karte.dart';

const _kGold = Color(0xFFFFC83D);

/// Ob die Leiste erscheint — rein, damit es prüfbar ist.
bool zeigeFavoritWahl({
  required bool angemeldet,
  required bool geladen,
  required List<Favorite> favoriten,
}) =>
    angemeldet && geladen && !favoriten.any((f) => f.type == FavoriteType.team);

class FavoritWahl extends ConsumerWidget {
  const FavoritWahl({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favoriten = ref.watch(favoritesProvider);
    final notifier = ref.read(favoritesProvider.notifier);
    if (!zeigeFavoritWahl(
      angemeldet: ref.watch(currentUserProvider) != null,
      geladen: notifier.geladen,
      favoriten: favoriten,
    )) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final teams = ref
        .watch(leagueTeamsProvider(Leagues.bundesliga.id))
        .valueOrNull;

    // Kein eigener Abstand nach unten: Den bringt die Kopfkarten-Stelle mit.
    return Container(
      decoration: kartenDeko(context, hauch: _kGold),
      padding: const EdgeInsets.fromLTRB(14, 14, 6, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.star_border, size: 20, color: _kGold),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Wähle deinen Verein',
                  style: TextStyle(
                    fontSize: Schrift.titel,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const FavoritesManageScreen(),
                  ),
                ),
                // Grau: Der Link ist der Nebenweg, die Wappen sind die Wahl.
                style: TextButton.styleFrom(
                  foregroundColor: scheme.onSurfaceVariant,
                ),
                child: const Text('Andere Ligen'),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              'Dann steht hier sein nächstes Spiel — mit Anstoß, '
              'Live-Stand und Ergebnis.',
              style: TextStyle(
                fontSize: Schrift.label,
                color: scheme.onSurfaceVariant,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 70,
            child: teams == null
                ? const SizedBox.shrink()
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(right: 8),
                    itemCount: teams.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 4),
                    itemBuilder: (_, i) => _Wappen(
                      team: teams[i],
                      onTap: () {
                        HapticFeedback.selectionClick();
                        notifier.toggle(
                          Favorite.team(teams[i], Leagues.bundesliga.id),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Wappen extends StatelessWidget {
  const _Wappen({required this.team, required this.onTap});

  final TeamRef team;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = vereinsKurzname(team.name);
    return Semantics(
      button: true,
      label: '${team.name} als Favorit wählen',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 60,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TeamBadge(team: team, size: 38),
              const SizedBox(height: 5),
              // Schrumpfen statt kappen — „Gladbach" in 60 Punkten.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  name,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: Schrift.label,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
