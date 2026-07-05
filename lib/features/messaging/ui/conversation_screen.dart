import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/chat_message.dart';
import '../../../core/ui/league_chat.dart';
import '../../auth/providers.dart';
import '../../fantasy/models/fantasy_models.dart';
import '../../fantasy/models/trade.dart';
import '../../fantasy/providers.dart';
import '../providers.dart';

/// 1:1-Direktnachrichten mit einem Nutzer. Nutzt das geteilte
/// [LeagueChat]-Widget; die eigenen Nachrichten werden aus dem globalen
/// DM-Stream nach diesem Partner gefiltert. Nachrichten mit verknüpftem
/// Trade-Angebot zeigen eine Aktionskarte (annehmen/ablehnen).
class ConversationScreen extends ConsumerWidget {
  const ConversationScreen({
    super.key,
    required this.partnerId,
    required this.partnerName,
  });

  final String partnerId;
  final String partnerName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myId = ref.watch(currentUserProvider)?.id;
    final messages = ref.watch(directMessagesProvider).whenData((all) => [
          for (final m in all)
            if (m.senderId == partnerId || m.recipientId == partnerId)
              ChatMessage(
                id: m.id,
                userId: m.senderId,
                body: m.body,
                createdAt: m.createdAt,
                tradeId: m.tradeId,
              ),
        ]);

    return Scaffold(
      appBar: AppBar(title: Text(partnerName)),
      body: LeagueChat(
        messages: messages,
        names: {partnerId: partnerName},
        myId: myId,
        hintText: 'Nachricht an $partnerName …',
        emptyText: 'Noch keine Nachrichten.\nSchreib $partnerName als Erster!',
        onSend: (text) =>
            ref.read(messagingRepositoryProvider).sendMessage(partnerId, text),
        onRetry: () => ref.invalidate(directMessagesProvider),
        extraBuilder: (context, msg) =>
            msg.tradeId == null ? null : _TradeActionCard(tradeId: msg.tradeId!),
      ),
    );
  }
}

/// Aktionskarte für ein im Chat verknüpftes Trade-Angebot: der Empfänger kann
/// direkt annehmen/ablehnen, sonst wird der Status angezeigt.
class _TradeActionCard extends ConsumerWidget {
  const _TradeActionCard({required this.tradeId});

  final String tradeId;

  Future<void> _respond(
      BuildContext context, WidgetRef ref, TradeOffer trade, bool accept) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(fantasyLeagueRepositoryProvider)
          .respondTrade(tradeId, accept);
      ref.invalidate(tradeDetailProvider(tradeId));
      ref.invalidate(leagueTradesProvider(trade.leagueId));
      messenger.showSnackBar(SnackBar(
          content: Text(accept ? 'Trade angenommen.' : 'Angebot abgelehnt.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Fehlgeschlagen: $e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final myId = ref.watch(currentUserProvider)?.id;
    final detailAsync = ref.watch(tradeDetailProvider(tradeId));
    final pool =
        ref.watch(playerPoolProvider).valueOrNull ?? const <FantasyPlayer>[];
    final nameById = {for (final p in pool) p.id: p.name};

    return detailAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => const SizedBox.shrink(),
      data: (d) {
        if (d == null) {
          return _shell(context,
              child: Text('Angebot nicht mehr verfügbar.',
                  style: TextStyle(color: scheme.onSurfaceVariant)));
        }
        final trade = d.trade;
        final offered = [
          for (final it in d.items)
            if (it.giver == trade.fromManager)
              nameById[it.playerId] ?? it.playerId
        ];
        final requested = [
          for (final it in d.items)
            if (it.giver == trade.toManager)
              nameById[it.playerId] ?? it.playerId
        ];
        final incoming = trade.toManager == myId;

        return _shell(
          context,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.swap_horiz, size: 18, color: scheme.primary),
                  const SizedBox(width: 6),
                  const Text('Trade-Angebot',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  _statusChip(context, trade.status),
                ],
              ),
              const SizedBox(height: 8),
              _line(context, 'Du bekommst',
                  incoming ? offered : requested, scheme.primary),
              const SizedBox(height: 2),
              _line(context, 'Du gibst',
                  incoming ? requested : offered, scheme.tertiary),
              if (trade.status.isPending && incoming) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _respond(context, ref, trade, false),
                        child: const Text('Ablehnen'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => _respond(context, ref, trade, true),
                        child: const Text('Annehmen'),
                      ),
                    ),
                  ],
                ),
              ] else if (trade.status.isPending) ...[
                const SizedBox(height: 8),
                Text('Warten auf Antwort …',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant)),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _shell(BuildContext context, {required Widget child}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82),
      margin: const EdgeInsets.only(top: 2, bottom: 6, left: 4, right: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.25)),
      ),
      child: child,
    );
  }

  Widget _line(
      BuildContext context, String label, List<String> players, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 82,
          child: Text(label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
        Expanded(
          child: Text(players.isEmpty ? '—' : players.join(', '),
              style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  Widget _statusChip(BuildContext context, TradeStatus status) {
    final scheme = Theme.of(context).colorScheme;
    final (Color bg, Color fg) = switch (status) {
      TradeStatus.pending => (scheme.secondaryContainer, scheme.onSecondaryContainer),
      TradeStatus.accepted => (scheme.primaryContainer, scheme.onPrimaryContainer),
      TradeStatus.rejected => (scheme.errorContainer, scheme.onErrorContainer),
      TradeStatus.cancelled => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Text(status.label,
          style:
              TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}
