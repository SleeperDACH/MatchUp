import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../models/tip_round.dart';
import '../providers.dart';

/// Admin-Funktion: Tipps für Mitglieder nachtragen (auch nach Anstoß). Nur der
/// Ersteller kommt hierher; die Änderung läuft über eine SECURITY-DEFINER-RPC.
class TipBackfillScreen extends ConsumerStatefulWidget {
  const TipBackfillScreen({super.key, required this.round});

  final TipRound round;

  @override
  ConsumerState<TipBackfillScreen> createState() => _TipBackfillScreenState();
}

class _TipBackfillScreenState extends ConsumerState<TipBackfillScreen> {
  String? _memberId;
  int? _matchday;

  Future<void> _save(String fixtureId, int home, int away) async {
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(tipRoundRepositoryProvider).adminSetTip(
        widget.round.id, _memberId!, fixtureId, home, away);
    ref.invalidate(allRoundTipsProvider(widget.round.id));
    messenger.showSnackBar(const SnackBar(content: Text('Tipp nachgetragen.')));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final members = ref.watch(roundMembersProvider(widget.round.id)).valueOrNull ??
        const <RoundMember>[];
    final current = ref.watch(currentRoundProvider).valueOrNull ?? 1;
    final rounds = ref.watch(availableRoundsProvider).valueOrNull ??
        const <RoundInfo>[];
    final minRound =
        rounds.isEmpty ? 1 : rounds.map((r) => r.number).reduce(math.min);
    final maxRound =
        rounds.isEmpty ? 34 : rounds.map((r) => r.number).reduce(math.max);
    final md = (_matchday ?? current).clamp(minRound, maxRound);

    final fixtures =
        ref.watch(roundFixturesProvider(md)).valueOrNull ?? const <Fixture>[];
    final allTips = ref.watch(allRoundTipsProvider(widget.round.id)).valueOrNull ??
        const <MemberTip>[];
    final memberTips = {
      for (final t in allTips)
        if (t.userId == _memberId) t.fixtureId: t
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Tipps nachtragen')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          Text(
            'Trage Tipps für ein Mitglied nach — auch nach Anstoß. Praktisch, '
            'wenn jemand das Tippen vergessen hat.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _memberId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Mitglied',
              contentPadding: EdgeInsets.symmetric(horizontal: 12),
            ),
            hint: const Text('Mitglied wählen'),
            items: [
              for (final m in members)
                DropdownMenuItem(value: m.userId, child: Text(m.display)),
            ],
            onChanged: (v) => setState(() => _memberId = v),
          ),
          const SizedBox(height: 12),
          // Spieltag-Auswahl.
          Row(
            children: [
              Text('Spieltag',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed:
                    md > minRound ? () => setState(() => _matchday = md - 1) : null,
              ),
              Container(
                width: 44,
                alignment: Alignment.center,
                child: Text('$md',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed:
                    md < maxRound ? () => setState(() => _matchday = md + 1) : null,
              ),
            ],
          ),
          const Divider(),
          if (_memberId == null)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Wähle oben ein Mitglied, um Tipps nachzutragen.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            )
          else if (fixtures.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            for (final f in fixtures)
              _BackfillRow(
                key: ValueKey('$_memberId:${f.id}'),
                fixture: f,
                initialHome: memberTips[f.id]?.homeGoals,
                initialAway: memberTips[f.id]?.awayGoals,
                onSave: (h, a) => _save(f.id, h, a),
              ),
        ],
      ),
    );
  }
}

/// Eine Nachtrag-Zeile: Teams, zwei Ergebnisfelder und Speichern. Eigener
/// State (Controller), damit sie bei Mitgliederwechsel per Key frisch startet.
class _BackfillRow extends StatefulWidget {
  const _BackfillRow({
    super.key,
    required this.fixture,
    required this.onSave,
    this.initialHome,
    this.initialAway,
  });

  final Fixture fixture;
  final int? initialHome;
  final int? initialAway;
  final Future<void> Function(int home, int away) onSave;

  @override
  State<_BackfillRow> createState() => _BackfillRowState();
}

class _BackfillRowState extends State<_BackfillRow> {
  late final _homeCtrl =
      TextEditingController(text: widget.initialHome?.toString() ?? '');
  late final _awayCtrl =
      TextEditingController(text: widget.initialAway?.toString() ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _homeCtrl.dispose();
    _awayCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final h = int.tryParse(_homeCtrl.text.trim());
    final a = int.tryParse(_awayCtrl.text.trim());
    if (h == null || a == null) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Bitte ein Ergebnis eingeben.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onSave(h, a);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Fehlgeschlagen: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final f = widget.fixture;
    final info = f.hasScore
        ? 'Endstand ${f.homeScore}:${f.awayScore}'
        : (f.hasStarted ? 'läuft / beendet' : _kickoff(f.kickoff));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(f.home.shortName,
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              _numField(_homeCtrl),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text(':', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              _numField(_awayCtrl),
              const SizedBox(width: 8),
              Expanded(
                child: Text(f.away.shortName,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(info,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
              const Spacer(),
              _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : TextButton.icon(
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: const Text('Speichern'),
                      onPressed: _save,
                    ),
            ],
          ),
          const Divider(height: 8),
        ],
      ),
    );
  }

  Widget _numField(TextEditingController c) => SizedBox(
        width: 44,
        child: TextField(
          controller: c,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          maxLength: 2,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            counterText: '',
            contentPadding: EdgeInsets.symmetric(vertical: 8),
          ),
        ),
      );

  static String _kickoff(DateTime k) {
    final l = k.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}.${two(l.month)}. ${two(l.hour)}:${two(l.minute)}';
  }
}
