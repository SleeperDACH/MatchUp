import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/models.dart';
import '../features/tippspiel/models/tip_round.dart';
import '../features/tippspiel/providers.dart';
import '../features/tippspiel/ui/league_hub_screen.dart';
import '../features/tippspiel/ui/matchday_screen.dart';
import '../features/tippspiel/ui/points_screen.dart';
import '../features/tippspiel/ui/tips_table_tab.dart';

/// Liga-Ansicht: Hier findet das Tippen statt — entweder in einer
/// Server-Liga (mit Rangliste) oder im lokalen Schnelltipp-Modus
/// (mit Wettbewerbs-Umschalter).
class LeagueScreen extends ConsumerStatefulWidget {
  const LeagueScreen({super.key, required this.round});

  /// `null` = Schnelltippen (lokal, ohne Liga).
  final TipRound? round;

  @override
  ConsumerState<LeagueScreen> createState() => _LeagueScreenState();
}

class _LeagueScreenState extends ConsumerState<LeagueScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final round = widget.round;
    final league = ref.watch(selectedLeagueProvider);

    // Hinweis am Liga-Symbol bei ungelesenen Chat-Nachrichten. Auf dem
    // Liga-Tab selbst (Index 2) gibt es keinen Hinweis — dort wird alles
    // als gelesen markiert.
    var ligaUnread = false;
    if (round != null) {
      if (_index == 2) {
        final msgs = ref.watch(roundMessagesProvider(round.id)).valueOrNull;
        if (msgs != null && msgs.isNotEmpty) {
          final latest = msgs
              .map((m) => m.createdAt)
              .reduce((a, b) => a.isAfter(b) ? a : b);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(chatLastReadProvider(round.id).notifier).markRead(latest);
          });
        }
      } else {
        ligaUnread = ref.watch(unreadChatProvider(round.id));
      }
    }

    final tabs = <Widget>[
      const MatchdayScreen(),
      if (round != null) TipsTableTab(round: round),
      // In einer Server-Liga: Chat + Regeln. Im lokalen Schnelltipp-Modus
      // (keine Liga, kein Chat) bleibt die eigene Punkteübersicht.
      if (round != null) LeagueHubScreen(round: round) else const PointsScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text(round?.name ?? 'Schnelltippen'),
            Text(
              league.name,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary),
            ),
          ],
        ),
        actions: [
          // Im Schnelltipp-Modus ist der Wettbewerb frei wählbar; in
          // einer Liga ist er durch die Liga festgelegt.
          if (round == null)
            PopupMenuButton<LeagueInfo>(
              tooltip: 'Wettbewerb wählen',
              icon: const Icon(Icons.swap_horiz),
              onSelected: (selected) =>
                  ref.read(selectedLeagueProvider.notifier).state = selected,
              itemBuilder: (context) => [
                for (final l in Leagues.all)
                  PopupMenuItem(
                    value: l,
                    child: Row(
                      children: [
                        if (l.id == league.id) ...[
                          const Icon(Icons.check, size: 18),
                          const SizedBox(width: 8),
                        ],
                        Text(l.name),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
      body: IndexedStack(index: _index, children: tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.sports_soccer),
            label: 'Tippen',
          ),
          if (round != null)
            const NavigationDestination(
              icon: Icon(Icons.table_chart_outlined),
              selectedIcon: Icon(Icons.table_chart),
              label: 'Tabelle',
            ),
          if (round != null)
            NavigationDestination(
              icon: Badge(
                isLabelVisible: ligaUnread,
                child: const Icon(Icons.forum_outlined),
              ),
              selectedIcon: const Icon(Icons.forum),
              label: 'Liga',
            )
          else
            const NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Meine Punkte',
            ),
        ],
      ),
    );
  }
}
