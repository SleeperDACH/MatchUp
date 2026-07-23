import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/app_avatar.dart';
import '../../friends/providers.dart';
import '../../leagues/providers.dart';
import '../../leagues/ui/join_requests_list.dart';
import '../../messaging/models/direct_message.dart';
import '../../messaging/providers.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';

/// „Spieler einladen": zeigt eigene Chats + Freunde (und eine Suche) und
/// verschickt eine tippbare Beitreten-Einladung als Direktnachricht.
class InvitePlayersScreen extends ConsumerStatefulWidget {
  const InvitePlayersScreen({super.key, required this.league});

  final FantasyLeague league;

  @override
  ConsumerState<InvitePlayersScreen> createState() =>
      _InvitePlayersScreenState();
}

class _InvitePlayersScreenState extends ConsumerState<InvitePlayersScreen> {
  final _invited = <String>{};
  String _query = '';
  List<UserRef> _results = const [];
  bool _searching = false;
  int _seq = 0;

  Future<void> _search(String q) async {
    setState(() => _query = q);
    final mySeq = ++_seq;
    if (q.trim().isEmpty) {
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    try {
      final res = await ref.read(messagingRepositoryProvider).searchUsers(q);
      if (mySeq != _seq || !mounted) return;
      setState(() {
        _results = res;
        _searching = false;
      });
    } catch (_) {
      if (mySeq != _seq || !mounted) return;
      setState(() => _searching = false);
    }
  }

  Future<void> _invite(String userId) async {
    final l = widget.league;
    try {
      await ref.read(messagingRepositoryProvider).sendMessage(
            userId,
            '🎮 Einladung zur Fantasy-Liga „${l.name}" — tritt direkt bei!',
            inviteLeagueId: l.id,
            inviteCode: l.inviteCode,
          );
      if (!mounted) return;
      setState(() => _invited.add(userId));
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Einladung gesendet')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Fehlgeschlagen: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Bereits beigetretene Mitglieder (aktiv + „pending") sollen nicht mehr als
    // Einladungsziel erscheinen.
    final memberIds = <String>{
      ...?ref
          .watch(fantasyManagersProvider(widget.league.id))
          .valueOrNull
          ?.map((m) => m.userId),
      ...?ref
          .watch(pendingMembersProvider(widget.league.id))
          .valueOrNull
          ?.map((m) => m.userId),
    };

    // Freunde zuerst, dann Chat-Partner ohne Freundschaft; Mitglieder raus.
    final friends = ref.watch(friendsProvider);
    final partners = [for (final c in ref.watch(conversationsProvider)) c.partnerId];
    final seen = <String>{};
    final ids = [
      for (final id in [...friends, ...partners])
        if (seen.add(id) && !memberIds.contains(id)) id
    ];
    final names = {
      ...?ref.watch(conversationNamesProvider).valueOrNull,
      ...?ref.watch(friendNamesProvider).valueOrNull,
    };
    final avatars = {
      ...?ref.watch(conversationAvatarsProvider).valueOrNull,
      ...?ref.watch(friendAvatarsProvider).valueOrNull,
    };

    // Offene Beitrittsanfragen (öffentlich–auf Einladung): der Admin bekommt
    // sie hier zum Annehmen/Ablehnen. Nur wenn welche vorliegen (RLS liefert
    // Nicht-Admins nichts).
    final pending =
        ref.watch(fantasyJoinRequestsProvider(widget.league.id)).valueOrNull ??
            const [];

    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('Spieler einladen')),
      body: Column(
        children: [
          if (pending.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: JoinRequestsList(
                  kind: 'fantasy',
                  id: widget.league.id,
                  leagueName: widget.league.name,
                  title: 'Beitrittsanfragen',
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Benutzername suchen',
                border: OutlineInputBorder(),
              ),
              onChanged: _search,
            ),
          ),
          if (_searching) const LinearProgressIndicator(),
          Expanded(
            child: _query.trim().isNotEmpty
                ? _searchList(memberIds)
                : (ids.isEmpty
                    ? _emptyHint()
                    : ListView(
                        padding: const EdgeInsets.only(bottom: 24),
                        children: [
                          for (final id in ids)
                            _InviteRow(
                              name: names[id] ?? '…',
                              avatar: avatars[id],
                              invited: _invited.contains(id),
                              onInvite: () => _invite(id),
                            ),
                        ],
                      )),
          ),
        ],
      ),
    );
  }

  Widget _emptyHint() => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Noch keine Chats oder Freunde — such oben nach einem Benutzernamen.',
            textAlign: TextAlign.center,
          ),
        ),
      );

  Widget _searchList(Set<String> memberIds) {
    // Bereits beigetretene Mitglieder aus den Treffern entfernen.
    final results = [
      for (final u in _results)
        if (!memberIds.contains(u.id)) u
    ];
    if (results.isEmpty && !_searching) {
      return const Center(child: Text('Keine Treffer.'));
    }
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, i) {
        final u = results[i];
        return _InviteRow(
          name: u.username,
          invited: _invited.contains(u.id),
          onInvite: () => _invite(u.id),
        );
      },
    );
  }
}

class _InviteRow extends StatelessWidget {
  const _InviteRow({
    required this.name,
    required this.invited,
    required this.onInvite,
    this.avatar,
  });

  final String name;
  final AvatarInfo? avatar;
  final bool invited;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: AppAvatar(
          imageUrl: avatar?.url,
          emoji: avatar?.emoji,
          colorHex: avatar?.color,
          fallbackText: name,
          size: 44),
      title: Text(name),
      trailing: invited
          ? const Chip(label: Text('Eingeladen'))
          : FilledButton.icon(
              onPressed: onInvite,
              icon: const Icon(Icons.send, size: 18),
              label: const Text('Einladen')),
    );
  }
}
