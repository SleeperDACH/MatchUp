import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/fantasy_models.dart';
import '../providers.dart';
import 'trade_screen.dart';

const _cAdd = Color(0xFF4ADE6A); // grün — freien Spieler holen
const _cWaiver = Color(0xFFFFC83D); // gelb — Waiver-Antrag
const _cTrade = Color(0xFFF23030); // rot — Trade (fremdes Team)

/// Kleiner Aktions-Button für einen Spieler (Free Agency & Spielersuche):
/// grün „Holen" (frei), gelb „Waiver" (auf dem Wire), rot „Trade" (in fremdem
/// Kader). Der eigene Kader zeigt eine dezente Markierung, gesperrte Spieler
/// (U20/Neuzugang) ein Schloss.
class PlayerActionButton extends ConsumerWidget {
  const PlayerActionButton({
    super.key,
    required this.league,
    required this.player,
    required this.ownerId,
    required this.onWaiver,
    required this.claimed,
    required this.myPlayers,
    required this.nextRank,
    required this.myId,
  });

  final FantasyLeague league;
  final FantasyPlayer player;

  /// Manager, der den Spieler besitzt — null, wenn frei oder auf dem Wire.
  final String? ownerId;
  final bool onWaiver;
  final bool claimed;
  final List<FantasyPlayer> myPlayers;
  final int nextRank;
  final String? myId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ownerId != null) {
      if (ownerId == myId) return const _MiniChip(text: 'Dein Team');
      return _RoundBtn(
        color: _cTrade,
        fg: Colors.white,
        icon: Icons.swap_horiz,
        tooltip: 'Trade anbieten',
        onTap: () => _trade(context, ref),
      );
    }
    if (player.isLockedNow(league.season)) return const _LockedChip();
    if (onWaiver) {
      if (claimed) return const _MiniChip(text: 'Beantragt');
      return _RoundBtn(
        color: _cWaiver,
        fg: Colors.black,
        icon: Icons.schedule,
        tooltip: 'Waiver beantragen',
        onTap: () => _claim(context, ref),
      );
    }
    return _RoundBtn(
      color: _cAdd,
      fg: Colors.black,
      icon: Icons.add,
      tooltip: 'Holen',
      onTap: () => _add(context, ref),
    );
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<String?> _chooseDrop(BuildContext context, {required bool optional}) {
    return showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(
            optional ? 'Wen abgeben? (optional)' : 'Kader voll — wen abgeben?'),
        children: [
          if (optional)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(''),
              child: const Text('Keinen — nur bei freiem Platz'),
            ),
          for (final p in myPlayers)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(p.id),
              child: Text('${p.position.short} · ${p.name}'),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
        ],
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    String? dropId;
    if (myPlayers.length >= league.roster.squadSize) {
      dropId = await _chooseDrop(context, optional: false);
      if (dropId == null) return;
    }
    if (!context.mounted) return;
    try {
      await ref
          .read(fantasyLeagueRepositoryProvider)
          .addFreeAgent(league.id, player.id, dropPlayerId: dropId);
      if (context.mounted) _toast(context, '${player.name} aufgenommen');
    } catch (e) {
      if (context.mounted) _toast(context, 'Fehlgeschlagen: $e');
    }
  }

  Future<void> _claim(BuildContext context, WidgetRef ref) async {
    final choice = await _chooseDrop(context, optional: true);
    if (choice == null || !context.mounted) return;
    try {
      await ref.read(fantasyLeagueRepositoryProvider).submitWaiverClaim(
            league.id,
            player.id,
            dropPlayerId: choice.isEmpty ? null : choice,
            rank: nextRank,
          );
      if (context.mounted) _toast(context, 'Antrag für ${player.name} gestellt');
    } catch (e) {
      if (context.mounted) _toast(context, 'Fehlgeschlagen: $e');
    }
  }

  void _trade(BuildContext context, WidgetRef ref) {
    final managers =
        ref.read(fantasyManagersProvider(league.id)).valueOrNull ??
            const <FantasyManager>[];
    FantasyManager? owner;
    for (final m in managers) {
      if (m.userId == ownerId) {
        owner = m;
        break;
      }
    }
    if (owner == null) {
      _toast(context, 'Trade gerade nicht möglich.');
      return;
    }
    // Ich fordere diesen Spieler; was ich gebe, wähle ich im Compose.
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TradeComposeScreen(
        league: league,
        partner: owner!,
        initialRequest: {player.id},
      ),
    ));
  }
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({
    required this.color,
    required this.fg,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final Color color;
  final Color fg;
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(icon, size: 20, color: fg),
          ),
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text,
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
    );
  }
}

class _LockedChip extends StatelessWidget {
  const _LockedChip();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.lock_outline, size: 14, color: scheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text('U20-Draft',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant)),
      ],
    );
  }
}
