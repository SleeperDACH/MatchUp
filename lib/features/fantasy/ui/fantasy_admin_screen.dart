import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/fantasy_models.dart';
import '../providers.dart';
import 'club_badge.dart';

/// Admin-Bereich (nur Ersteller): Teilnehmer kicken, verwaiste Teams neuen
/// Nutzern zuweisen und fremde Kader bearbeiten (Commissioner).
class FantasyAdminScreen extends ConsumerWidget {
  const FantasyAdminScreen({super.key, required this.league});

  final FantasyLeague league;

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(fantasyManagersProvider(league.id));
    ref.invalidate(vacantTeamsProvider(league.id));
  }

  Future<void> _kick(
      BuildContext context, WidgetRef ref, FantasyManager m) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${m.username} kicken?'),
        content: const Text(
            'Der Teilnehmer verlässt die Liga. Sein Team bleibt als verwaister '
            'Slot bestehen und kann neu zugewiesen werden.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Abbrechen')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Kicken')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref
          .read(fantasyLeagueRepositoryProvider)
          .kickMember(league.id, m.userId);
      await _refresh(ref);
      messenger.showSnackBar(SnackBar(content: Text('${m.username} gekickt.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Fehlgeschlagen: $e')));
    }
  }

  Future<void> _assign(
      BuildContext context, WidgetRef ref, FantasyManager vacant) async {
    final messenger = ScaffoldMessenger.of(context);
    final user = await Navigator.of(context).push<({String id, String username})>(
        MaterialPageRoute(builder: (_) => _UserPickerScreen(league: league)));
    if (user == null) return;
    try {
      await ref
          .read(fantasyLeagueRepositoryProvider)
          .assignTeam(league.id, vacant.userId, user.id);
      await _refresh(ref);
      messenger.showSnackBar(
          SnackBar(content: Text('Team an ${user.username} zugewiesen.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Fehlgeschlagen: $e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final managers = ref.watch(fantasyManagersProvider(league.id)).valueOrNull ??
        const <FantasyManager>[];
    final vacants = ref.watch(vacantTeamsProvider(league.id)).valueOrNull ??
        const <FantasyManager>[];
    final roster = ref.watch(leagueRosterProvider(league.id)).valueOrNull ??
        const <RosterEntry>[];

    int rosterCount(String uid) =>
        roster.where((r) => r.managerId == uid).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Admin')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Mitglieder',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          for (final m in managers)
            Card(
              child: ListTile(
                leading: CircleAvatar(child: Text(_initial(m.username))),
                title: Text(m.username),
                subtitle: Text(m.userId == league.createdBy
                    ? 'Admin · ${rosterCount(m.userId)} Spieler'
                    : '${rosterCount(m.userId)} Spieler'),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'edit') {
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) =>
                              AdminRosterEditor(league: league, target: m)));
                    } else if (v == 'kick') {
                      _kick(context, ref, m);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'edit', child: Text('Kader bearbeiten')),
                    if (m.userId != league.createdBy)
                      PopupMenuItem(
                          value: 'kick',
                          child: Text('Kicken',
                              style: TextStyle(color: scheme.error))),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 20),
          Text('Verwaiste Teams',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          if (vacants.isEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text('Keine verwaisten Teams.',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            )
          else
            for (final v in vacants)
              Card(
                child: ListTile(
                  leading: Icon(Icons.person_off_outlined, color: scheme.error),
                  title: Text('Team von ${v.username}'),
                  subtitle: Text('verwaist · ${rosterCount(v.userId)} Spieler'),
                  trailing: FilledButton(
                    onPressed: () => _assign(context, ref, v),
                    child: const Text('Zuweisen'),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  static String _initial(String n) =>
      n.isEmpty ? '?' : n.substring(0, 1).toUpperCase();
}

/// Kader eines Teams als Admin bearbeiten: Spieler droppen (→ 24h-Waiver) oder
/// freie Spieler zuweisen.
class AdminRosterEditor extends ConsumerWidget {
  const AdminRosterEditor({super.key, required this.league, required this.target});

  final FantasyLeague league;
  final FantasyManager target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final poolAsync = ref.watch(playerPoolProvider);
    final roster = ref.watch(leagueRosterProvider(league.id)).valueOrNull ??
        const <RosterEntry>[];
    final clubIcons =
        ref.watch(clubIconsProvider).valueOrNull ?? const <String, String?>{};

    return Scaffold(
      appBar: AppBar(title: Text('Kader: ${target.username}')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Spieler hinzufügen'),
      ),
      body: poolAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (pool) {
          final byId = {for (final p in pool) p.id: p};
          final players = [
            for (final r in roster)
              if (r.managerId == target.userId && byId[r.playerId] != null)
                byId[r.playerId]!
          ]..sort((a, b) => a.position.index != b.position.index
              ? a.position.index.compareTo(b.position.index)
              : a.name.compareTo(b.name));
          if (players.isEmpty) {
            return const Center(
                child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Dieses Team hat noch keine Spieler.')));
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              for (final p in players)
                ListTile(
                  leading:
                      ClubBadge(club: p.club, iconUrl: clubIcons[p.club]),
                  title: Text(p.name),
                  subtitle: Text('${p.position.short} · ${p.club}'),
                  trailing: IconButton(
                    icon: Icon(Icons.remove_circle_outline,
                        color: Theme.of(context).colorScheme.error),
                    tooltip: 'Droppen',
                    onPressed: () => _drop(context, ref, p),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _drop(
      BuildContext context, WidgetRef ref, FantasyPlayer p) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(fantasyLeagueRepositoryProvider)
          .adminDrop(league.id, target.userId, p.id);
      messenger.showSnackBar(SnackBar(
          content: Text('${p.name} gedroppt (24h auf dem Waiver).')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Fehlgeschlagen: $e')));
    }
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final player = await Navigator.of(context).push<FantasyPlayer>(
        MaterialPageRoute(builder: (_) => _FreePlayerPicker(league: league)));
    if (player == null) return;
    try {
      await ref
          .read(fantasyLeagueRepositoryProvider)
          .adminAdd(league.id, target.userId, player.id);
      messenger.showSnackBar(
          SnackBar(content: Text('${player.name} hinzugefügt.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Fehlgeschlagen: $e')));
    }
  }
}

/// Freien Spieler (in keinem Kader) auswählen — für die Admin-Zuweisung.
class _FreePlayerPicker extends ConsumerStatefulWidget {
  const _FreePlayerPicker({required this.league});
  final FantasyLeague league;

  @override
  ConsumerState<_FreePlayerPicker> createState() => _FreePlayerPickerState();
}

class _FreePlayerPickerState extends ConsumerState<_FreePlayerPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final poolAsync = ref.watch(playerPoolProvider);
    final roster = ref.watch(leagueRosterProvider(widget.league.id)).valueOrNull ??
        const <RosterEntry>[];
    final clubIcons =
        ref.watch(clubIconsProvider).valueOrNull ?? const <String, String?>{};
    final taken = {for (final r in roster) r.playerId};

    return Scaffold(
      appBar: AppBar(title: const Text('Freien Spieler wählen')),
      body: poolAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (pool) {
          final free = [
            for (final p in pool)
              if (!taken.contains(p.id) &&
                  (_query.isEmpty ||
                      p.name.toLowerCase().contains(_query.toLowerCase()) ||
                      p.club.toLowerCase().contains(_query.toLowerCase())))
                p
          ]..sort((a, b) => a.name.compareTo(b.name));
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Spieler oder Verein suchen',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: free.length,
                  itemBuilder: (context, i) {
                    final p = free[i];
                    return ListTile(
                      leading:
                          ClubBadge(club: p.club, iconUrl: clubIcons[p.club]),
                      title: Text(p.name),
                      subtitle: Text('${p.position.short} · ${p.club}'),
                      onTap: () => Navigator.of(context).pop(p),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Nutzer per Benutzername suchen — für die Team-Zuweisung.
class _UserPickerScreen extends ConsumerStatefulWidget {
  const _UserPickerScreen({required this.league});
  final FantasyLeague league;

  @override
  ConsumerState<_UserPickerScreen> createState() => _UserPickerScreenState();
}

class _UserPickerScreenState extends ConsumerState<_UserPickerScreen> {
  String _query = '';
  List<({String id, String username})> _results = const [];
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
      final res = await ref
          .read(fantasyLeagueRepositoryProvider)
          .searchProfiles(q);
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
      appBar: AppBar(title: const Text('Nutzer zuweisen')),
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
                                child: Text(
                                    u.username.substring(0, 1).toUpperCase())),
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
