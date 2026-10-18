import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/league_chat.dart';
import '../../auth/providers.dart';
import '../models/fantasy_models.dart';
import '../models/roster_move.dart';
import '../providers.dart';
import 'kader_meldung.dart';
import 'player_profile_sheet.dart';

/// Ligainterner Chat einer Fantasy-Liga (nur Mitglieder, Realtime).
/// Nutzt das geteilte [LeagueChat]-Widget; Namen werden über die
/// Managerliste aufgelöst.
class FantasyChatScreen extends ConsumerWidget {
  const FantasyChatScreen({super.key, required this.league});

  final FantasyLeague league;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final nachrichten = ref.watch(fantasyMessagesProvider(league.id));
    // **Kaderbewegungen zwischen den Nachrichten** (17.10.2026) — aus dem
    // Kaderprotokoll, nach Zeit einsortiert. Fehlt das Protokoll noch, steht
    // der Chat ohne sie da, statt zu warten.
    final moves = ref.watch(rosterMovesProvider(league.id)).valueOrNull ??
        const <RosterMove>[];
    final meldungen = kaderMeldungen(moves);
    final messages = nachrichten.whenData((ms) => [
          ...ms,
          for (final m in meldungen.values) m.nachricht,
        ]..sort((a, b) => a.createdAt.compareTo(b.createdAt)));
    final pool = ref.watch(playerPoolProvider).valueOrNull ??
        const <FantasyPlayer>[];
    final spieler = {for (final p in pool) p.id: p};
    final clubIcons =
        ref.watch(clubIconsProvider).valueOrNull ?? const <String, String?>{};
    final besitzer = {
      for (final r in ref.watch(leagueRosterProvider(league.id)).valueOrNull ??
          const <RosterEntry>[])
        r.playerId: r.managerId,
    };
    final managers =
        ref.watch(fantasyManagersProvider(league.id)).valueOrNull ??
            const <FantasyManager>[];
    final myId = ref.watch(currentUserProvider)?.id;

    final names = {for (final m in managers) m.userId: m.display};
    final avatars = {
      for (final m in managers)
        m.userId: (url: m.avatarUrl, emoji: m.avatarEmoji, color: m.avatarColor)
    };

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Column(
          children: [
            const Text('Liga-Chat'),
            Text(league.name,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
      body: LeagueChat(
        messages: messages,
        names: names,
        avatars: avatars,
        myId: myId,
        systemBuilder: (context, m) {
          final e = meldungen[m.id]?.ereignis;
          if (e == null) return null;
          return KaderMeldung(
            ereignis: e,
            namen: names,
            spieler: spieler,
            clubIcons: clubIcons,
            onSpieler: (p) => showPlayerProfile(
              context,
              league: league,
              player: p,
              clubIcon: clubIcons[p.club],
              isMine: besitzer[p.id] == myId,
            ),
          );
        },
        onSend: (text, replyTo) => ref
            .read(fantasyLeagueRepositoryProvider)
            .sendMessage(league.id, text, replyTo: replyTo),
        onRetry: () => ref.invalidate(fantasyMessagesProvider(league.id)),
      ),
    );
  }
}
