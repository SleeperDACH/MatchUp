import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/league_chat.dart';
import '../../auth/providers.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';

/// Ligainterner Chat einer Fantasy-Liga (nur Mitglieder, Realtime).
/// Nutzt das geteilte [LeagueChat]-Widget; Namen werden über die
/// Managerliste aufgelöst.
class FantasyChatScreen extends ConsumerWidget {
  const FantasyChatScreen({super.key, required this.league});

  final FantasyLeague league;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final messages = ref.watch(fantasyMessagesProvider(league.id));
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
                    ?.copyWith(color: scheme.primary)),
          ],
        ),
      ),
      body: LeagueChat(
        messages: messages,
        names: names,
        avatars: avatars,
        myId: myId,
        onSend: (text, replyTo) => ref
            .read(fantasyLeagueRepositoryProvider)
            .sendMessage(league.id, text, replyTo: replyTo),
        onRetry: () => ref.invalidate(fantasyMessagesProvider(league.id)),
      ),
    );
  }
}
