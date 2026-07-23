import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/app_avatar.dart';
import '../../messaging/models/direct_message.dart';
import '../../messaging/providers.dart';
import '../../messaging/ui/conversation_screen.dart';
import '../providers.dart';

/// Führt eine Freundschafts-Aktion aus und zeigt Fehler als Snackbar an
/// (sonst blieben Fehlschläge — z. B. durch RLS — unbemerkt).
Future<void> _run(BuildContext context, Future<void> Function() action) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Fehlgeschlagen: $e')));
  }
}

/// Freunde-Tab: eingehende Anfragen annehmen/ablehnen, Freundesliste, und über
/// die Suche neue Freunde per Benutzername hinzufügen.
class FriendsScreen extends ConsumerWidget {
  const FriendsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final incoming = ref.watch(incomingRequestsProvider);
    final outgoing = ref.watch(outgoingRequestsProvider);
    final friends = ref.watch(friendsProvider);
    final names = ref.watch(friendNamesProvider).valueOrNull ?? const {};
    final avatars = ref.watch(friendAvatarsProvider).valueOrNull ?? const {};
    final loading = ref.watch(friendshipsProvider).isLoading;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Freunde'),
        actions: [
          IconButton(
            tooltip: 'Freund hinzufügen',
            icon: const Icon(Icons.person_add_alt_1),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const FriendSearchScreen())),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : (incoming.isEmpty && outgoing.isEmpty && friends.isEmpty)
              ? _Empty(onAdd: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const FriendSearchScreen())))
              : ListView(
                  padding: const EdgeInsets.only(bottom: 96),
                  children: [
                    if (incoming.isNotEmpty) ...[
                      const _SectionLabel('Anfragen'),
                      for (final id in incoming)
                        _RequestRow(
                          userId: id,
                          name: names[id] ?? '…',
                          avatar: avatars[id],
                          onAccept: () => _run(context,
                              () => ref.read(friendsRepositoryProvider).accept(id)),
                          onDecline: () => _run(context,
                              () => ref.read(friendsRepositoryProvider).remove(id)),
                        ),
                    ],
                    _SectionLabel('Freunde${friends.isEmpty ? '' : ' (${friends.length})'}'),
                    if (friends.isEmpty)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: Text('Noch keine Freunde — such oben nach '
                            'Benutzernamen.'),
                      ),
                    for (final id in friends)
                      _FriendRow(
                        userId: id,
                        name: names[id] ?? '…',
                        avatar: avatars[id],
                      ),
                    if (outgoing.isNotEmpty) ...[
                      const _SectionLabel('Gesendete Anfragen'),
                      for (final id in outgoing)
                        _PendingRow(
                          name: names[id] ?? '…',
                          avatar: avatars[id],
                          onCancel: () =>
                              ref.read(friendsRepositoryProvider).remove(id),
                        ),
                    ],
                  ],
                ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(text,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
    );
  }
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({
    required this.userId,
    required this.name,
    required this.onAccept,
    required this.onDecline,
    this.avatar,
  });

  final String userId;
  final String name;
  final AvatarInfo? avatar;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: AppAvatar(
          imageUrl: avatar?.url,
          emoji: avatar?.emoji,
          colorHex: avatar?.color,
          fallbackText: name,
          size: 44),
      title: Text(name),
      subtitle: const Text('möchte dich als Freund hinzufügen'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Ablehnen',
            icon: Icon(Icons.close, color: scheme.error),
            onPressed: onDecline,
          ),
          IconButton.filled(
            tooltip: 'Annehmen',
            icon: const Icon(Icons.check),
            onPressed: onAccept,
          ),
        ],
      ),
    );
  }
}

class _FriendRow extends StatelessWidget {
  const _FriendRow({required this.userId, required this.name, this.avatar});

  final String userId;
  final String name;
  final AvatarInfo? avatar;

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
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _openActions(context, userId, name),
    );
  }

  void _openActions(BuildContext context, String userId, String name) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.forum_outlined),
              title: const Text('Nachricht schreiben'),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        ConversationScreen(partnerId: userId, partnerName: name)));
              },
            ),
            Consumer(
              builder: (ctx, ref, _) => ListTile(
                leading: Icon(Icons.person_remove_outlined,
                    color: Theme.of(ctx).colorScheme.error),
                title: Text('Freund entfernen',
                    style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                onTap: () {
                  ref.read(friendsRepositoryProvider).remove(userId);
                  Navigator.of(sheetCtx).pop();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingRow extends StatelessWidget {
  const _PendingRow({required this.name, required this.onCancel, this.avatar});

  final String name;
  final AvatarInfo? avatar;
  final VoidCallback onCancel;

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
      subtitle: const Text('Anfrage gesendet'),
      trailing: TextButton(onPressed: onCancel, child: const Text('Zurückziehen')),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.group_outlined, size: 56, color: scheme.onSurfaceVariant),
            const SizedBox(height: 14),
            const Text('Noch keine Freunde',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('Füge Freunde per Benutzername hinzu — dann kannst du sie in '
                'Ligen einladen und ihnen schreiben.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Freund hinzufügen'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Nutzer per Benutzername suchen und eine Freundschaftsanfrage senden.
class FriendSearchScreen extends ConsumerStatefulWidget {
  const FriendSearchScreen({super.key});

  @override
  ConsumerState<FriendSearchScreen> createState() => _FriendSearchScreenState();
}

class _FriendSearchScreenState extends ConsumerState<FriendSearchScreen> {
  String _query = '';
  List<UserRef> _results = const [];
  bool _loading = false;
  int _seq = 0;

  Future<void> _search(String q) async {
    setState(() => _query = q);
    final mySeq = ++_seq;
    if (q.trim().isEmpty) {
      setState(() {
        _results = const [];
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final res = await ref.read(messagingRepositoryProvider).searchUsers(q);
      if (mySeq != _seq || !mounted) return;
      setState(() {
        _results = res;
        _loading = false;
      });
    } catch (_) {
      if (mySeq != _seq || !mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Freund hinzufügen')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Benutzername suchen',
                border: OutlineInputBorder(),
              ),
              onChanged: _search,
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: _query.trim().isEmpty
                ? const Center(child: Text('Nach einem Benutzernamen suchen.'))
                : _results.isEmpty && !_loading
                    ? const Center(child: Text('Keine Treffer.'))
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (context, i) =>
                            _SearchResultRow(user: _results[i]),
                      ),
          ),
        ],
      ),
    );
  }
}

/// Ergebniszeile mit Freundes-Status-Button (Hinzufügen / Annehmen / Status).
class _SearchResultRow extends ConsumerWidget {
  const _SearchResultRow({required this.user});
  final UserRef user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(friendStatusProvider(user.id));
    final repo = ref.read(friendsRepositoryProvider);
    final trailing = switch (status) {
      FriendStatus.friends => const Chip(label: Text('Befreundet')),
      FriendStatus.outgoing => const Chip(label: Text('Angefragt')),
      FriendStatus.incoming => FilledButton(
          onPressed: () => repo.accept(user.id),
          child: const Text('Annehmen')),
      FriendStatus.none => FilledButton.icon(
          onPressed: () async {
            await repo.sendRequest(user.id);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Anfrage gesendet')));
            }
          },
          icon: const Icon(Icons.person_add_alt_1, size: 18),
          label: const Text('Hinzufügen')),
    };
    return ListTile(
      leading: CircleAvatar(
          child: Text(user.username.substring(0, 1).toUpperCase())),
      title: Text(user.username),
      trailing: trailing,
    );
  }
}
