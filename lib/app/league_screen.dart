import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/tippspiel/models/tip_round.dart';
import '../features/tippspiel/providers.dart';
import 'widgets/leise_reiter.dart';
import 'widgets/vibrant_league_title.dart';
import '../features/tippspiel/ui/league_hub_screen.dart';
import '../features/tippspiel/ui/matchday_screen.dart';
import '../features/tippspiel/ui/tip_duels_tab.dart';
import '../features/tippspiel/ui/tip_settings_sheet.dart';
import '../features/tippspiel/ui/tipp_uebersicht_tab.dart';
import '../features/tippspiel/ui/tips_table_tab.dart';

/// Ansicht einer Tipprunde: Reiter **oben** wie bei Fantasy — Übersicht,
/// Tippen, Tabelle und im Head-to-Head-Modus Duelle (09.11.2026, „Richtung
/// B" aus dem Redesign). Vorher eine untere Leiste Tippen · Tabelle · Liga;
/// der Liga-Reiter (Chat mit Regeln) steht jetzt als Zeile in der Übersicht.
class LeagueScreen extends ConsumerStatefulWidget {
  const LeagueScreen({
    super.key,
    required this.round,
    this.initialTab = TippReiter.uebersicht,
    this.chatOeffnen = false,
  });

  final TipRound round;

  /// Start-Reiter, siehe [TippReiter]. Standard ist die Übersicht.
  final int initialTab;

  /// Gleich den Liga-Chat öffnen (Push auf eine Chatnachricht). Er ist kein
  /// Reiter mehr, also legt der Schirm die Chat-Seite nach dem ersten Bild
  /// darüber — zurück führt dann in die Übersicht.
  final bool chatOeffnen;

  @override
  ConsumerState<LeagueScreen> createState() => _LeagueScreenState();
}

class _LeagueScreenState extends ConsumerState<LeagueScreen> {
  @override
  void initState() {
    super.initState();
    final r = widget.round;
    if (widget.chatOeffnen && !r.isFantasyLinked && !r.istGlobal) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => TipRundenChat(round: r)),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Aktive Runde beobachten, damit Einstellungsänderungen (Wertung/Modi)
    // sofort durchschlagen; sonst die übergebene Runde.
    final active = ref.watch(activeRoundProvider);
    final round =
        (active != null && active.id == widget.round.id) ? active : widget.round;
    final league = ref.watch(selectedLeagueProvider);

    // Im Head-to-Head-Modus kommt ein vierter Reiter „Duelle" dazu.
    final h2h = round.scoring.headToHead;
    final titel = ['Übersicht', 'Tippen', 'Tabelle', if (h2h) 'Duelle'];

    return DefaultTabController(
      // Der Schlüssel baut den Controller neu, wenn „Duelle" an- oder
      // abgeschaltet wird — sonst passte seine Länge nicht mehr.
      key: ValueKey(titel.length),
      length: titel.length,
      initialIndex: widget.initialTab.clamp(0, titel.length - 1),
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 12,
          title: VibrantLeagueTitle(
            // **Das globale Tippspiel in Versalien** (09.11.2026, gemeldet:
            // „beim globalen Tippspiel ist oben der Name nicht in
            // Großbuchstaben"). Auf der Startseite steht es als
            // „GLOBALES TIPPSPIEL" — eigene Runden heißen dort, wie sie
            // eingegeben wurden, und bleiben es hier auch.
            name: round.istGlobal ? round.name.toUpperCase() : round.name,
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
          bottom: LeiseReiter(
            titel: titel,
            horizontal: 12,
            versalien: true,
          ),
        ),
        body: TabBarView(
          children: [
            TippUebersichtTab(round: round),
            const MatchdayScreen(),
            TipsTableTab(round: round),
            if (h2h) TipDuelsTab(round: round),
          ],
        ),
      ),
    );
  }
}
