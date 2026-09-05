import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/app_avatar.dart';
import '../models/direct_message.dart';
import '../providers.dart';
import 'conversation_screen.dart';
import '../../../app/theme.dart';
import '../../../app/typografie.dart';

/// Übersicht der Direktnachrichten (ligaübergreifend), erreichbar über das
/// Profil. Pro Partner die letzte Nachricht; oben ein neues Gespräch starten.
class ConversationsScreen extends ConsumerWidget {
  const ConversationsScreen({super.key});

  Future<void> _newChat(BuildContext context, WidgetRef ref) async {
    final user = await Navigator.of(context).push<UserRef>(
        MaterialPageRoute(builder: (_) => const UserSearchScreen()));
    if (user == null || !context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            ConversationScreen(partnerId: user.id, partnerName: user.username)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dmAsync = ref.watch(directMessagesProvider);
    final ungelesen = ref.watch(unreadDmByPartnerProvider);
    final convos = ref.watch(conversationsProvider);
    final names = ref.watch(conversationNamesProvider).valueOrNull ?? const {};
    final avatars =
        ref.watch(conversationAvatarsProvider).valueOrNull ?? const {};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nachrichten'),
        actions: [
          IconButton(
            tooltip: 'Neue Nachricht',
            icon: const Icon(Icons.edit_square),
            onPressed: () => _newChat(context, ref),
          ),
        ],
      ),
      body: dmAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (_) {
          if (convos.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Noch keine Nachrichten.',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => _newChat(context, ref),
                      icon: const Icon(Icons.edit_square),
                      label: const Text('Nachricht schreiben'),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: convos.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final c = convos[i];
              final name = names[c.partnerId] ?? '…';
              final av = avatars[c.partnerId];
              // **Was ungelesen ist, sieht man der Zeile an.** Der rote
              // Zähler am Nachrichten-Symbol sagte „8", und die Liste sah
              // für gelesen und ungelesen gleich aus — man konnte nicht
              // erkennen, welche gemeint waren. Beide Zahlen kommen jetzt aus
              // derselben Regel.
              final offen = ungelesen[c.partnerId] ?? 0;
              final scheme = Theme.of(context).colorScheme;
              return ListTile(
                leading: AppAvatar(
                  imageUrl: av?.url,
                  emoji: av?.emoji,
                  colorHex: av?.color,
                  fallbackText: name,
                  size: 44,
                ),
                title: Text(
                  name,
                  style: TextStyle(
                    fontWeight: offen > 0 ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  c.lastMessage.body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // Ungelesenes steht heller als Gelesenes — dieselbe Sprache
                  // wie überall in dieser App: hell heißt „das gilt jetzt".
                  style: TextStyle(
                    color: offen > 0
                        ? scheme.onSurface
                        : scheme.onSurfaceVariant.withValues(alpha: 0.8),
                    fontWeight: offen > 0 ? FontWeight.w600 : null,
                  ),
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _time(c.lastMessage.createdAt),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: offen > 0 ? MatchUpColors.red : null,
                          ),
                    ),
                    if (offen > 0) ...[
                      const SizedBox(height: 4),
                      // **Rot und mit Zahl.** Ein Punkt sagte nur „irgendwas",
                      // die Zahl sagt, wie viel wartet — dieselbe Marke wie am
                      // Nachrichten-Symbol des Startbildschirms.
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: MatchUpColors.red,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        constraints: const BoxConstraints(minWidth: 18),
                        child: Text(
                          '$offen',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: Schrift.winzig,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ConversationScreen(
                        partnerId: c.partnerId, partnerName: name))),
              );
            },
          );
        },
      ),
    );
  }

  static String _time(DateTime dt) {
    final l = dt.toLocal();
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    if (l.year == now.year && l.month == now.month && l.day == now.day) {
      return '${two(l.hour)}:${two(l.minute)}';
    }
    return '${two(l.day)}.${two(l.month)}.';
  }
}

/// Nutzer per Benutzername suchen und ein Gespräch starten. Gibt den
/// gewählten [UserRef] per Navigator zurück.
class UserSearchScreen extends ConsumerStatefulWidget {
  const UserSearchScreen({super.key});

  @override
  ConsumerState<UserSearchScreen> createState() => _UserSearchScreenState();
}

class _UserSearchScreenState extends ConsumerState<UserSearchScreen> {
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
      if (mySeq != _seq || !mounted) return; // veraltete Antwort verwerfen
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
      appBar: AppBar(
        title: const Text('Neue Nachricht'),
      ),
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
                        itemBuilder: (context, i) {
                          final u = _results[i];
                          return ListTile(
                            leading: CircleAvatar(
                                child: Text(u.username.substring(0, 1).toUpperCase())),
                            title: Text(u.username),
                            onTap: () => Navigator.of(context).pop(u),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
