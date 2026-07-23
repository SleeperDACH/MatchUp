import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/chat_message.dart';
import '../../../core/ui/app_avatar.dart';
import '../../../core/ui/league_chat.dart';
import '../../auth/providers.dart';
import '../../fantasy/providers.dart';
import '../../fantasy/ui/trade_screen.dart';
import '../../friends/ui/user_profile_screen.dart';
import '../../tippspiel/providers.dart';
import '../models/direct_message.dart';
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
    // Liga-Einladungen dieses Gesprächs (Nachricht-ID → Einladung) für die
    // Beitreten-Karte.
    final invites = <String, DirectMessage>{
      for (final m in ref.watch(directMessagesProvider).valueOrNull ?? const [])
        if ((m.senderId == partnerId || m.recipientId == partnerId) &&
            m.isLeagueInvite)
          m.id: m
    };
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

    final partnerAvatars =
        ref.watch(conversationAvatarsProvider).valueOrNull ?? const {};
    final partnerAvatar = partnerAvatars[partnerId];

    return Scaffold(
      appBar: AppBar(
        // Kopf antippen → Profil des Partners (mit „Freund hinzufügen").
        title: InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => UserProfileScreen(
                    userId: partnerId,
                    name: partnerName,
                    avatar: partnerAvatar,
                    showMessageButton: false,
                  ))),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppAvatar(
                imageUrl: partnerAvatar?.url,
                emoji: partnerAvatar?.emoji,
                colorHex: partnerAvatar?.color,
                fallbackText: partnerName,
                size: 30,
              ),
              const SizedBox(width: 10),
              Flexible(
                  child: Text(partnerName, overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
      ),
      body: LeagueChat(
        messages: messages,
        names: {partnerId: partnerName},
        avatars: {partnerId: ?partnerAvatar},
        myId: myId,
        hintText: 'Nachricht an $partnerName …',
        emptyText: 'Noch keine Nachrichten.\nSchreib $partnerName als Erster!',
        enableReply: false,
        onSend: (text, _) =>
            ref.read(messagingRepositoryProvider).sendMessage(partnerId, text),
        onRetry: () => ref.invalidate(directMessagesProvider),
        extraBuilder: (context, msg) {
          if (msg.tradeId != null) return TradeCard(tradeId: msg.tradeId!);
          final inv = invites[msg.id];
          if (inv != null) {
            return _LeagueInviteCard(invite: inv, mine: inv.senderId == myId);
          }
          return null;
        },
      ),
    );
  }
}

/// Tippbare Beitreten-Karte für eine Liga-Einladung im Chat.
class _LeagueInviteCard extends ConsumerStatefulWidget {
  const _LeagueInviteCard({required this.invite, required this.mine});

  final DirectMessage invite;
  final bool mine;

  @override
  ConsumerState<_LeagueInviteCard> createState() => _LeagueInviteCardState();
}

class _LeagueInviteCardState extends ConsumerState<_LeagueInviteCard> {
  bool _joining = false;
  bool _joined = false;

  Future<void> _join() async {
    setState(() => _joining = true);
    final messenger = ScaffoldMessenger.of(context);
    final code = widget.invite.inviteCode!;
    // Einladung kann zu einer Fantasy-Liga ODER einer Tipprunde gehören —
    // erst Fantasy versuchen, sonst als Tipprunde beitreten.
    try {
      try {
        await ref.read(fantasyLeagueRepositoryProvider).joinLeague(code);
      } catch (e) {
        if (!e.toString().contains('Ungültiger Einladungscode')) rethrow;
        await ref.read(tipRoundRepositoryProvider).joinRound(code);
        ref.invalidate(myRoundsProvider);
      }
      if (!mounted) return;
      setState(() {
        _joining = false;
        _joined = true;
      });
      messenger
          .showSnackBar(const SnackBar(content: Text('Liga beigetreten 🎉')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _joining = false);
      messenger.showSnackBar(
          SnackBar(content: Text('Beitreten fehlgeschlagen: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Widget action;
    if (widget.mine) {
      action = const Chip(label: Text('Gesendet'));
    } else if (_joined) {
      action = const Chip(label: Text('Beigetreten'));
    } else {
      action = FilledButton(
        onPressed: _joining ? null : _join,
        child: _joining
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Text('Beitreten'),
      );
    }
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.sports_esports, color: scheme.primary),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Liga-Einladung',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          action,
        ],
      ),
    );
  }
}
