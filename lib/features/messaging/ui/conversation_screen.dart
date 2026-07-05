import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/chat_message.dart';
import '../../../core/ui/league_chat.dart';
import '../../auth/providers.dart';
import '../../fantasy/ui/trade_screen.dart';
import '../providers.dart';

/// 1:1-Direktnachrichten mit einem Nutzer. Nutzt das geteilte
/// [LeagueChat]-Widget; die eigenen Nachrichten werden aus dem globalen
/// DM-Stream nach diesem Partner gefiltert. Nachrichten mit verknüpftem
/// Trade-Angebot zeigen eine Aktionskarte (annehmen/ablehnen).
class ConversationScreen extends ConsumerStatefulWidget {
  const ConversationScreen({
    super.key,
    required this.partnerId,
    required this.partnerName,
  });

  final String partnerId;
  final String partnerName;

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  String get partnerId => widget.partnerId;
  String get partnerName => widget.partnerName;

  @override
  Widget build(BuildContext context) {
    final myId = ref.watch(currentUserProvider)?.id;
    // Solange der Chat offen ist, gilt er als gelesen (roter Punkt verschwindet).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(dmLastReadProvider(partnerId).notifier).markRead(DateTime.now());
      }
    });
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
            msg.tradeId == null ? null : TradeCard(tradeId: msg.tradeId!),
      ),
    );
  }
}
