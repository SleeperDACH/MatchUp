import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/chat_message.dart';
import '../../../core/ui/league_chat.dart';
import '../../auth/providers.dart';
import '../providers.dart';

/// 1:1-Direktnachrichten mit einem Nutzer. Nutzt das geteilte
/// [LeagueChat]-Widget; die eigenen Nachrichten werden aus dem globalen
/// DM-Stream nach diesem Partner gefiltert.
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
      ),
    );
  }
}
