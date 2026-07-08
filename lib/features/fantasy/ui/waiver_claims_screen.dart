import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';

/// „Meine Waiver-Anträge": offene Anträge (mit Rang & Stornierung) und die
/// bereits abgearbeiteten samt Ergebnis. Zeigt oben die eigene rollende
/// Waiver-Priorität.
class WaiverClaimsScreen extends ConsumerWidget {
  const WaiverClaimsScreen({super.key, required this.league});

  final FantasyLeague league;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final claims = ref.watch(myWaiverClaimsProvider(league.id)).valueOrNull ??
        const <WaiverClaim>[];
    final pool = ref.watch(playerPoolProvider).valueOrNull ??
        const <FantasyPlayer>[];
    final managers = ref.watch(fantasyManagersProvider(league.id)).valueOrNull ??
        const <FantasyManager>[];
    final myId = ref.watch(currentUserProvider)?.id;

    final playerById = {for (final p in pool) p.id: p};
    String? nameOf(String? id) =>
        id == null ? null : (playerById[id]?.name ?? id);

    final myPriority = managers
        .where((m) => m.userId == myId)
        .map((m) => m.waiverPriority)
        .firstOrNull;

    final pending = claims.where((c) => c.status.isPending).toList()
      ..sort((a, b) => a.rank.compareTo(b.rank));
    final history = claims.where((c) => !c.status.isPending).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Scaffold(
      appBar: AppBar(title: const Text('Meine Anträge')),
      body: ListView(
        children: [
          _PriorityHeader(priority: myPriority),
          if (pending.isEmpty && history.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'Noch keine Waiver-Anträge. Spieler auf dem Wire kannst du in '
                'der Free Agency beantragen.',
                textAlign: TextAlign.center,
              ),
            ),
          if (pending.isNotEmpty) const _SectionLabel('Offen'),
          for (final c in pending)
            _ClaimTile(
              claim: c,
              addName: nameOf(c.addPlayerId)!,
              dropName: nameOf(c.dropPlayerId),
              onCancel: () => _cancel(context, ref, c),
            ),
          if (history.isNotEmpty) const _SectionLabel('Abgearbeitet'),
          for (final c in history)
            _ClaimTile(
              claim: c,
              addName: nameOf(c.addPlayerId)!,
              dropName: nameOf(c.dropPlayerId),
            ),
        ],
      ),
    );
  }

  Future<void> _cancel(
      BuildContext context, WidgetRef ref, WaiverClaim claim) async {
    try {
      await ref.read(fantasyLeagueRepositoryProvider).cancelWaiverClaim(claim.id);
      // Realtime liefert UPDATE-Events auf Antrags-Zeilen nicht zuverlässig
      // (RPC/SECURITY DEFINER + Replica-Identity) — sonst bliebe der stornierte
      // Antrag sichtbar und wirkte, als ließe er sich nicht löschen. Darum die
      // Liste hier aktiv neu ziehen.
      ref.invalidate(myWaiverClaimsProvider(league.id));
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Antrag storniert')));
      }
    } catch (e) {
      // War der Antrag schon storniert/abgearbeitet (z. B. doppelt getippt),
      // ist das kein echter Fehler — Liste einfach frisch ziehen.
      if (e.toString().contains('nicht gefunden')) {
        ref.invalidate(myWaiverClaimsProvider(league.id));
        return;
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Fehlgeschlagen: $e')));
      }
    }
  }
}

class _PriorityHeader extends StatelessWidget {
  const _PriorityHeader({this.priority});

  final int? priority;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.primary.withValues(alpha: 0.10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        children: [
          Text(
            priority == null ? 'Waiver-Priorität: noch offen' : 'Priorität $priority',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: scheme.primary),
          ),
          const SizedBox(height: 4),
          Text(
            'Jeder gedroppte Spieler ist 24 Stunden claim-only; danach werden '
            'die Anträge in Prioritätsreihenfolge abgearbeitet. Nach einem '
            'Zuschlag rutschst du ans Ende.',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}

class _ClaimTile extends StatelessWidget {
  const _ClaimTile({
    required this.claim,
    required this.addName,
    this.dropName,
    this.onCancel,
  });

  final WaiverClaim claim;
  final String addName;
  final String? dropName;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final sub = StringBuffer('Rang ${claim.rank}');
    if (dropName != null) sub.write(' · gibt $dropName ab');
    if (claim.reason != null) sub.write(' · ${claim.reason}');

    return ListTile(
      leading: _StatusBadge(status: claim.status),
      title: Text('Holen: $addName'),
      subtitle: Text(sub.toString()),
      trailing: onCancel == null
          ? null
          : IconButton(
              tooltip: 'Antrag stornieren',
              icon: const Icon(Icons.close),
              onPressed: onCancel,
            ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final WaiverStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (IconData icon, Color color) = switch (status) {
      WaiverStatus.pending => (Icons.schedule, scheme.primary),
      WaiverStatus.won => (Icons.check_circle, Colors.green),
      WaiverStatus.lost => (Icons.cancel, scheme.error),
      WaiverStatus.invalid => (Icons.error_outline, scheme.error),
      WaiverStatus.cancelled => (Icons.block, scheme.onSurfaceVariant),
    };
    return Tooltip(
      message: status.label,
      child: Icon(icon, color: color),
    );
  }
}
