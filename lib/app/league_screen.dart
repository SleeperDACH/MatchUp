import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/tippspiel/models/tip_round.dart';
import '../features/tippspiel/providers.dart';
import 'widgets/vibrant_league_title.dart';
import '../features/tippspiel/ui/league_hub_screen.dart';
import '../features/tippspiel/ui/matchday_screen.dart';
import '../features/tippspiel/ui/tip_duels_tab.dart';
import '../features/tippspiel/ui/tip_settings_sheet.dart';
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
    // Aktive Runde beobachten, damit Einstellungsänderungen (Wertung/Modi)
    // sofort durchschlagen; sonst die übergebene Runde.
    final active = ref.watch(activeRoundProvider);
    final round =
        (active != null && active.id == widget.round.id) ? active : widget.round;
    final league = ref.watch(selectedLeagueProvider);

    // Im Head-to-Head-Modus liegt zwischen Tabelle und Liga ein „Duelle"-Tab.
    final h2h = round.scoring.headToHead;
    final tabs = <Widget>[
      const MatchdayScreen(),
      TipsTableTab(round: round),
      if (h2h) TipDuelsTab(round: round),
      LeagueHubScreen(round: round),
    ];
    // Der Liga-Tab (Chat) ist immer der letzte.
    final ligaIndex = tabs.length - 1;

    // Hinweis am Liga-Symbol bei ungelesenen Chat-Nachrichten. Auf dem
    // Liga-Tab selbst wird alles als gelesen markiert.
    var ligaUnread = false;
    if (_index == ligaIndex) {
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

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: VibrantLeagueTitle(
          name: round.name,
          subtitle: league.name,
          logoUrl: round.logoUrl,
          logoEmoji: round.logoEmoji,
          logoColor: round.logoColor,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Einstellungen',
            onPressed: () => showTipSettings(context, round),
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
          const NavigationDestination(
            icon: Icon(Icons.table_chart_outlined),
            selectedIcon: Icon(Icons.table_chart),
            label: 'Tabelle',
          ),
          if (h2h)
            const NavigationDestination(
              icon: Icon(Icons.bolt_outlined),
              selectedIcon: Icon(Icons.bolt),
              label: 'Duelle',
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
