import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/tippspiel/models/tip_round.dart';
import '../features/tippspiel/providers.dart';
import '../features/tippspiel/ui/league_hub_screen.dart';
import '../features/tippspiel/ui/matchday_screen.dart';
import '../features/tippspiel/ui/tips_table_tab.dart';

/// Ansicht einer Tipprunde mit Tabs: Tippen, Tabelle und Liga (Chat + Regeln).
class LeagueScreen extends ConsumerStatefulWidget {
  const LeagueScreen({super.key, required this.round});

  final TipRound round;

  @override
  ConsumerState<LeagueScreen> createState() => _LeagueScreenState();
}

class _LeagueScreenState extends ConsumerState<LeagueScreen> {
  // Beim Öffnen zuerst die Tabelle (Index 1), nicht die Tippabgabe.
  int _index = 1;

  @override
  Widget build(BuildContext context) {
    final round = widget.round;
    final league = ref.watch(selectedLeagueProvider);

    // Hinweis am Liga-Symbol bei ungelesenen Chat-Nachrichten. Auf dem
    // Liga-Tab selbst (Index 2) wird alles als gelesen markiert.
    var ligaUnread = false;
    if (_index == 2) {
      final msgs = ref.watch(roundMessagesProvider(round.id)).valueOrNull;
      if (msgs != null && msgs.isNotEmpty) {
        final latest =
            msgs.map((m) => m.createdAt).reduce((a, b) => a.isAfter(b) ? a : b);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(chatLastReadProvider(round.id).notifier).markRead(latest);
        });
      }
    } else {
      ligaUnread = ref.watch(unreadChatProvider(round.id));
    }

    final tabs = <Widget>[
      const MatchdayScreen(),
      TipsTableTab(round: round),
      LeagueHubScreen(round: round),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text(round.name),
            Text(
              league.name,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary),
            ),
          ],
        ),
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
          const NavigationDestination(
            icon: Icon(Icons.table_chart_outlined),
            selectedIcon: Icon(Icons.table_chart),
            label: 'Tabelle',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: ligaUnread,
              child: const Icon(Icons.forum_outlined),
            ),
            selectedIcon: const Icon(Icons.forum),
            label: 'Liga',
          ),
        ],
      ),
    );
  }
}
