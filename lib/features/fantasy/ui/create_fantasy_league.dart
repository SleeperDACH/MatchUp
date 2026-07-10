import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/fantasy_models.dart';
import '../providers.dart';
import 'fantasy_league_screen.dart';

/// Erstellen einer Fantasy-Liga: Modus (Liga/Dynasty), Name und Pickzeit.
class CreateFantasyLeagueScreen extends ConsumerStatefulWidget {
  const CreateFantasyLeagueScreen({super.key, required this.mode});

  final FantasyMode mode;

  @override
  ConsumerState<CreateFantasyLeagueScreen> createState() =>
      _CreateFantasyLeagueScreenState();
}

class _CreateFantasyLeagueScreenState
    extends ConsumerState<CreateFantasyLeagueScreen> {
  final _name = TextEditingController();
  late FantasyMode _mode = widget.mode;
  DraftPickTime _pickTime = DraftPickTime.m1;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_name.text.trim().length < 3) {
      setState(() => _error = 'Bitte einen Namen mit mind. 3 Zeichen wählen.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final league =
          await ref.read(fantasyLeagueRepositoryProvider).createLeague(
                name: _name.text,
                mode: _mode,
                season: ref.read(fantasySeasonProvider),
                pickTime: _pickTime,
              );
      ref.invalidate(myFantasyLeaguesProvider);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => FantasyLeagueScreen(league: league)));
    } catch (e) {
      setState(() => _error = 'Liga konnte nicht erstellt werden: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fantasy-Liga erstellen')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Modus', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final mode in FantasyMode.values)
            _ModeCard(
              mode: mode,
              selected: _mode == mode,
              onTap: () => setState(() => _mode = mode),
            ),
          const SizedBox(height: 20),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Name der Liga',
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            ),
          ),
          const SizedBox(height: 20),
          Text('Pickzeit im Draft',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Wie lange jeder Manager pro Pick Zeit hat. Kurze Zeiten = '
            'Live-Draft, lange Zeiten = Slow-Draft über Tage.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<DraftPickTime>(
            initialValue: _pickTime,
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(horizontal: 12),
            ),
            items: [
              for (final t in DraftPickTime.values)
                DropdownMenuItem(
                  value: t,
                  child: Row(
                    children: [
                      Text(t.label),
                      const SizedBox(width: 8),
                      _Chip(text: t.isLive ? 'Live' : 'Slow'),
                    ],
                  ),
                ),
            ],
            onChanged: (t) => setState(() => _pickTime = t ?? _pickTime),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: const Text('Liga erstellen'),
            onPressed: _busy ? null : _create,
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final FantasyMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: selected ? scheme.primary.withValues(alpha: 0.15) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? scheme.primary : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: ListTile(
        leading: Icon(
          mode == FantasyMode.dynasty ? Icons.auto_awesome : Icons.calendar_today,
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
        ),
        title: Text(mode.label,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(mode.tagline),
        trailing: selected
            ? Icon(Icons.check_circle, color: scheme.primary)
            : const Icon(Icons.circle_outlined),
        onTap: onTap,
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
    );
  }
}

// ---------------------------------------------------------------------
// Einstiegs-Flows (vom Homescreen)
// ---------------------------------------------------------------------

void createFantasyLeagueFlow(BuildContext context, FantasyMode mode) {
  Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CreateFantasyLeagueScreen(mode: mode)));
}
