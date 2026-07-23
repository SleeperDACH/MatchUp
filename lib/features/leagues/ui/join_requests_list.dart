import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/app_avatar.dart';
import '../../fantasy/providers.dart';
import '../../messaging/providers.dart';
import '../../tippspiel/providers.dart';
import '../models/join_request.dart';
import '../providers.dart';

/// Live-Liste offener Beitrittsanfragen eines Wettbewerbs mit Annehmen/Ablehnen
/// (nur der Admin bekommt per RLS Daten). Wiederverwendet in den Sichtbarkeits-
/// Einstellungen und im „Spieler einladen"-Screen.
///
/// Ist [emptyNote] `null`, rendert die Liste bei fehlenden Anfragen gar nichts
/// (inkl. [title]) — praktisch, um den Abschnitt nur bei Bedarf einzublenden.
class JoinRequestsList extends ConsumerWidget {
  const JoinRequestsList({
    super.key,
    required this.kind,
    required this.id,
    required this.leagueName,
    this.title,
    this.emptyNote,
  });

  /// `fantasy` oder `tip`.
  final String kind;
  final String id;

  /// Name des Wettbewerbs (für die Rückmeldung an Anfragende).
  final String leagueName;

  /// Optionale Überschrift über der Liste.
  final String? title;

  /// Text bei leerer Liste; `null` = Abschnitt komplett ausblenden.
  final String? emptyNote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = kind == 'fantasy'
        ? ref.watch(fantasyJoinRequestsProvider(id))
        : ref.watch(tipJoinRequestsProvider(id));
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: LinearProgressIndicator(minHeight: 2),
      ),
      error: (e, _) => Text('Anfragen konnten nicht geladen werden: $e'),
      data: (reqs) {
        if (reqs.isEmpty && emptyNote == null) return const SizedBox.shrink();

        final children = <Widget>[];
        if (title != null) {
          children.add(Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(title!,
                style: Theme.of(context).textTheme.titleMedium),
          ));
        }
        if (reqs.isEmpty) {
          children.add(Text(emptyNote!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)));
        } else {
          final idsCsv =
              (reqs.map((r) => r.userId).toList()..sort()).join(',');
          final profiles = ref.watch(joinRequestProfilesProvider(idsCsv));
          for (final r in reqs) {
            children.add(_JoinRequestRow(
              kind: kind,
              id: id,
              leagueName: leagueName,
              request: r,
              name: profiles.valueOrNull?.names[r.userId] ?? '…',
              avatar: profiles.valueOrNull?.avatars[r.userId],
            ));
          }
        }
        return Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: children);
      },
    );
  }
}

class _JoinRequestRow extends ConsumerStatefulWidget {
  const _JoinRequestRow({
    required this.kind,
    required this.id,
    required this.leagueName,
    required this.request,
    required this.name,
    required this.avatar,
  });

  final String kind;
  final String id;
  final String leagueName;
  final JoinRequest request;
  final String name;
  final AvatarInfo? avatar;

  @override
  ConsumerState<_JoinRequestRow> createState() => _JoinRequestRowState();
}

class _JoinRequestRowState extends ConsumerState<_JoinRequestRow> {
  bool _busy = false;

  Future<void> _respond(bool accept) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final uid = widget.request.userId;
      if (widget.kind == 'fantasy') {
        await ref
            .read(fantasyLeagueRepositoryProvider)
            .respondRequest(widget.id, uid, accept: accept);
        ref.invalidate(fantasyManagersProvider(widget.id));
      } else {
        await ref
            .read(tipRoundRepositoryProvider)
            .respondRequest(widget.id, uid, accept: accept);
      }
      // Rückmeldung an den Anfragenden per Chat (Best-Effort — ein Fehler hier
      // darf die bereits erfolgte Entscheidung nicht rückgängig machen).
      try {
        final body = accept
            ? '✅ Du wurdest in „${widget.leagueName}" aufgenommen!'
            : 'Deine Beitrittsanfrage für „${widget.leagueName}" wurde abgelehnt.';
        await ref.read(messagingRepositoryProvider).sendMessage(uid, body);
      } catch (_) {
        // Nachricht optional — ignorieren.
      }
      messenger.showSnackBar(SnackBar(
          content: Text(accept ? 'Aufgenommen.' : 'Anfrage abgelehnt.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Fehlgeschlagen: $e')));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: AppAvatar(
        imageUrl: widget.avatar?.url,
        emoji: widget.avatar?.emoji,
        colorHex: widget.avatar?.color,
        fallbackText: widget.name,
        size: 40,
      ),
      title: Text(widget.name, overflow: TextOverflow.ellipsis),
      trailing: _busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2))
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Annehmen',
                  icon: Icon(Icons.check_circle,
                      color: Theme.of(context).colorScheme.primary),
                  onPressed: () => _respond(true),
                ),
                IconButton(
                  tooltip: 'Ablehnen',
                  icon: Icon(Icons.cancel,
                      color: Theme.of(context).colorScheme.error),
                  onPressed: () => _respond(false),
                ),
              ],
            ),
    );
  }
}
