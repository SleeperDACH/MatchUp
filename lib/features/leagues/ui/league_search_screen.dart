import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/widgets/pill_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/league_screen.dart';
import '../../../core/ui/app_avatar.dart';
import 'join_by_code.dart';
import '../../fantasy/providers.dart';
import '../../fantasy/ui/fantasy_league_screen.dart';
import '../../tippspiel/providers.dart';
import '../models/public_league_result.dart';
import '../providers.dart';

/// Öffentliche Ligasuche: findet öffentliche Fantasy-Ligen und Tipprunden.
/// Freier Eintritt → direkt beitreten; „auf Einladung" → Beitritt anfragen.
class LeagueSearchScreen extends ConsumerStatefulWidget {
  const LeagueSearchScreen({super.key});

  @override
  ConsumerState<LeagueSearchScreen> createState() => _LeagueSearchScreenState();
}

class _LeagueSearchScreenState extends ConsumerState<LeagueSearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';
  bool _busy = false;

  /// `all` | `fantasy` | `tip`.
  String _type = 'all';

  /// Nur direkt beitretbare (freier Eintritt, nicht voll) anzeigen.
  bool _onlyJoinable = false;

  List<PublicLeagueResult> _filter(List<PublicLeagueResult> list) {
    return [
      for (final r in list)
        if ((_type == 'all' || r.kind == _type) &&
            (!_onlyJoinable || (r.joinable && !r.isFull)))
          r,
    ];
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(publicLeagueSearchProvider(_query));
    return Scaffold(
      appBar: AppBar(title: const Text('Ligen entdecken')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              controller: _controller,
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Liga oder Tipprunde suchen',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _controller.clear();
                          _onChanged('');
                        },
                      ),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          // Der Weg zu allem, was hier **nicht** steht. Die Liste zeigt nur
          // öffentliche Ligen; eine private taucht in keiner Suche auf, egal
          // wie genau man ihren Namen tippt. Wer eingeladen wurde, kam bisher
          // nur über das „+" auf dem Homescreen hierher — auf dem Schirm, der
          // „Ligen entdecken" heißt, fehlte genau diese Tür.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => joinAnyFlow(context, ref),
                icon: const Icon(Icons.vpn_key_outlined, size: 18),
                label: const Text('Mit Einladungscode beitreten'),
              ),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final (wert, text) in const [
                  ('all', 'Alle'),
                  ('fantasy', 'Fantasy'),
                  ('tip', 'Tippspiel'),
                ]) ...[
                  PillChip(
                    label: text,
                    selected: _type == wert,
                    outlined: true,
                    onTap: () => setState(() => _type = wert),
                  ),
                  const SizedBox(width: 8),
                ],
                const SizedBox(width: 4),
                PillChip(
                  label: 'Öffentlich',
                  selected: _onlyJoinable,
                  outlined: true,
                  onTap: () =>
                      setState(() => _onlyJoinable = !_onlyJoinable),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: results.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => _CenteredNote('Suche fehlgeschlagen: $e'),
              data: (all) {
                final list = _filter(all);
                return list.isEmpty
                  // Beide Leerzustände nennen den Einladungscode: Wer hier
                  // nichts findet, sucht oft eine private Liga — und die steht
                  // in keiner Suche, egal wie genau der Name stimmt.
                  ? _CenteredNote(all.isEmpty
                      ? 'Aktuell gibt es keine öffentlichen Ligen oder '
                          'Tipprunden zum Beitreten.\nHast du einen '
                          'Einladungscode, kommst du damit auch in eine private '
                          'Liga.\nOder stelle eine eigene Liga in den '
                          'Einstellungen auf „öffentlich", damit andere sie '
                          'hier finden.'
                      : 'Keine Treffer mit diesen Filtern.\nPrivate Ligen '
                          'tauchen hier nicht auf — für die brauchst du einen '
                          'Einladungscode.')
                  : RefreshIndicator(
                      onRefresh: () async =>
                          ref.invalidate(publicLeagueSearchProvider(_query)),
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) => _ResultCard(
                          result: list[i],
                          busy: _busy,
                          onAction: () => _act(list[i]),
                        ),
                      ),
                    );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _act(PublicLeagueResult r) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (r.isMember) {
        await _open(r);
      } else if (r.joinable) {
        await _join(r);
      } else if (r.isInviteOnly && !r.requested) {
        await _request(r);
      }
    } catch (e) {
      if (mounted) _snack('Fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(PublicLeagueResult r) async {
    if (r.isFantasy) {
      final league =
          await ref.read(fantasyLeagueRepositoryProvider).fetchLeague(r.id);
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => FantasyLeagueScreen(league: league)));
    } else {
      final round = await ref.read(tipRoundRepositoryProvider).fetchRound(r.id);
      if (!mounted) return;
      activateRound(ref, round);
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => LeagueScreen(round: round)));
    }
  }

  Future<void> _join(PublicLeagueResult r) async {
    if (r.isFantasy) {
      final league =
          await ref.read(fantasyLeagueRepositoryProvider).joinPublic(r.id);
      ref.invalidate(myFantasyLeaguesProvider);
      ref.invalidate(publicLeagueSearchProvider);
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => FantasyLeagueScreen(league: league)));
    } else {
      final round =
          await ref.read(tipRoundRepositoryProvider).joinPublic(r.id);
      ref.invalidate(myRoundsProvider);
      ref.invalidate(publicLeagueSearchProvider);
      if (!mounted) return;
      activateRound(ref, round);
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => LeagueScreen(round: round)));
    }
  }

  Future<void> _request(PublicLeagueResult r) async {
    if (r.isFantasy) {
      await ref.read(fantasyLeagueRepositoryProvider).requestJoin(r.id);
    } else {
      await ref.read(tipRoundRepositoryProvider).requestJoin(r.id);
    }
    ref.invalidate(publicLeagueSearchProvider);
    if (mounted) _snack('Beitritt angefragt — der Admin entscheidet.');
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));
}

class _ResultCard extends StatelessWidget {
  const _ResultCard(
      {required this.result, required this.busy, required this.onAction});

  final PublicLeagueResult result;
  final bool busy;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = result;
    final kindLabel = r.isFantasy ? 'Fantasy' : 'Tippspiel';
    final seasonLabel =
        '${(r.season % 100).toString().padLeft(2, '0')}/'
        '${((r.season + 1) % 100).toString().padLeft(2, '0')}';
    final members = r.maxTeams != null
        ? '${r.memberCount}/${r.maxTeams}'
        : '${r.memberCount}';

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            AppAvatar(
              imageUrl: r.logoUrl,
              emoji: r.logoEmoji,
              colorHex: r.logoColor,
              fallbackText: r.name,
              size: 44,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.name,
                      style: Theme.of(context).textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    '$kindLabel · $members Teilnehmer · Saison $seasonLabel',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _ActionButton(result: r, busy: busy, onAction: onAction),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton(
      {required this.result, required this.busy, required this.onAction});

  final PublicLeagueResult result;
  final bool busy;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final r = result;
    if (r.isMember) {
      return OutlinedButton(
        onPressed: busy ? null : onAction,
        child: const Text('Öffnen'),
      );
    }
    if (r.joinable && r.isFull) {
      return const OutlinedButton(
        onPressed: null,
        child: Text('Voll'),
      );
    }
    if (r.joinable) {
      return FilledButton(
        onPressed: busy ? null : onAction,
        child: const Text('Beitreten'),
      );
    }
    // „auf Einladung"
    if (r.requested) {
      return const OutlinedButton(
        onPressed: null,
        child: Text('Angefragt'),
      );
    }
    return FilledButton.tonal(
      onPressed: busy ? null : onAction,
      child: const Text('Anfragen'),
    );
  }
}

class _CenteredNote extends StatelessWidget {
  const _CenteredNote(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ),
    );
  }
}
