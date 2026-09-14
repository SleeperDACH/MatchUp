import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../models/tip_round.dart';
import '../logic/nachtrag.dart';
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
  bool _speichert = false;

  /// **Die Eingabefelder gehören dem Schirm, nicht der Zeile.**
  ///
  /// Solange jede Zeile ihren eigenen Speichern-Knopf trug, konnte sie ihre
  /// Controller auch selbst halten. Ein Knopf für den ganzen Spieltag muss
  /// aber alle neun Felder gleichzeitig lesen können.
  ///
  /// Der Schlüssel trägt Mitglied **und** Spiel: Beim Wechsel des Mitglieds
  /// sind es andere Tipps, und ein stehen gebliebener Controller schriebe die
  /// Zahlen des Vorgängers in den nächsten Nachtrag.
  final _felder = <String, ({TextEditingController heim, TextEditingController gast})>{};

  ({TextEditingController heim, TextEditingController gast}) _feld(
      String fixtureId, int? vorherHeim, int? vorherGast) {
    final key = '$_memberId:$fixtureId';
    return _felder.putIfAbsent(
      key,
      () => (
        heim: TextEditingController(text: vorherHeim?.toString() ?? ''),
        gast: TextEditingController(text: vorherGast?.toString() ?? ''),
      ),
    );
  }

  @override
  void dispose() {
    for (final f in _felder.values) {
      f.heim.dispose();
      f.gast.dispose();
    }
    super.dispose();
  }

  /// Ein Speichern für den ganzen Spieltag.
  Future<void> _speichern(List<Fixture> fixtures,
      Map<String, MemberTip> memberTips) async {
    final messenger = ScaffoldMessenger.of(context);
    final pruefung = pruefeNachtrag([
      for (final f in fixtures)
        NachtragZeile(
          fixtureId: f.id,
          heim: _feld(f.id, memberTips[f.id]?.homeGoals,
                  memberTips[f.id]?.awayGoals)
              .heim
              .text,
          gast: _feld(f.id, memberTips[f.id]?.homeGoals,
                  memberTips[f.id]?.awayGoals)
              .gast
              .text,
          vorherHeim: memberTips[f.id]?.homeGoals,
          vorherGast: memberTips[f.id]?.awayGoals,
        ),
    ]);

    // **Eine halbe Zeile ist ein Fehler, kein Überspringen.** Wer neun Spiele
    // tippt und bei einem die zweite Zahl vergisst, bekäme sonst ein stilles
    // „gespeichert" und einen fehlenden Tipp.
    if (pruefung.hatFehler) {
      messenger.showSnackBar(SnackBar(
          content: Text(pruefung.halbeZeilen.length == 1
              ? 'Ein Spiel hat nur eine Zahl — bitte beide eintragen.'
              : '${pruefung.halbeZeilen.length} Spiele haben nur eine Zahl '
                  '— bitte beide eintragen.')));
      return;
    }
    if (!pruefung.gibtEsWasZuTun) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Nichts geändert.')));
      return;
    }

    setState(() => _speichert = true);
    try {
      final n = await ref.read(tipRoundRepositoryProvider).adminSetTips(
          widget.round.id, _memberId!, pruefung.zuSpeichern);
      ref.invalidate(allRoundTipsProvider(widget.round.id));
      messenger.showSnackBar(SnackBar(
          content: Text(n == 1
              ? 'Ein Tipp nachgetragen.'
              : '$n Tipps nachgetragen.')));
    } catch (e) {
      // Der Server schreibt alles oder nichts — es steht also nichts halb da.
      messenger.showSnackBar(
          SnackBar(content: Text('Nichts gespeichert: $e')));
    } finally {
      if (mounted) setState(() => _speichert = false);
    }
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
                // Die „Spieltag"-Beschriftung steht links in der Zeile, die
                // Zahl zwischen den Pfeilen — vorgelesen ergab das drei
                // Stationen, von denen keine sagte, wohin ein Pfeil führt.
                tooltip:
                    md > minRound ? 'Zurück zu Spieltag ${md - 1}' : 'Zurück',
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
                tooltip:
                    md < maxRound ? 'Weiter zu Spieltag ${md + 1}' : 'Weiter',
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
                fixture: f,
                felder: _feld(f.id, memberTips[f.id]?.homeGoals,
                    memberTips[f.id]?.awayGoals),
              ),
        ],
      ),
      // **Ein Knopf für den ganzen Spieltag**, und er steht unten statt am
      // Ende der Liste — dieselbe Stelle wie in allen Formularen dieser App
      // (`FormActionBar`). Bei neun Spielen ist das Ende der Liste weit weg.
      bottomNavigationBar: _memberId == null || fixtures.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                child: FilledButton.icon(
                  icon: _speichert
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save_outlined, size: 18),
                  label: Text(_speichert
                      ? 'Speichere …'
                      : 'Spieltag $md speichern'),
                  onPressed: _speichert
                      ? null
                      : () => _speichern(fixtures, memberTips),
                ),
              ),
            ),
    );
  }
}

/// Eine Nachtrag-Zeile: Teams, zwei Ergebnisfelder, Anstoß bzw. Endstand.
///
/// **Ohne eigenen Speichern-Knopf und ohne eigenen State.** Beides lag hier,
/// solange jede Zeile für sich gespeichert wurde; seit es einen Knopf für den
/// ganzen Spieltag gibt, gehören die Controller dem Schirm — er muss alle
/// neun Felder auf einmal lesen können.
class _BackfillRow extends StatelessWidget {
  const _BackfillRow({required this.fixture, required this.felder});

  final Fixture fixture;
  final ({TextEditingController heim, TextEditingController gast}) felder;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final f = fixture;
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
              _numField(felder.heim),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text(':', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              _numField(felder.gast),
              const SizedBox(width: 8),
              Expanded(
                child: Text(f.away.shortName,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(info,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
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
