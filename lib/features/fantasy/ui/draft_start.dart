import '../../../app/farben.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/typografie.dart';
import '../../../app/widgets/pill_selector.dart';
import '../../../core/ui/einstellungs_zeile.dart';
import '../../../core/ui/wert_stepper.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';
import 'fantasy_settings_screen.dart' show DraftOrderPage;

/// Startet den Draft — **nur nach ausdrücklicher Bestätigung.**
///
/// Der Start ist nicht rückgängig zu machen: Er friert die Reihenfolge ein und
/// setzt die ganze Liga in Gang. Deshalb steht davor immer ein Dialog, der
/// sagt, was gleich passiert.
///
/// Liegt hier und nicht im Draft-Raum, weil zwei Wege hineinführen: der Knopf
/// im Raum und der Auftrags-Kopf der Liga-Übersicht („Draft starten"). Der
/// zweite hat vorher nur den Raum geöffnet — ein Knopf, der ankündigt zu
/// starten und stattdessen navigiert, ist eine kleine Lüge, und die
/// Rückfrage stand dann nur auf dem einen Weg.
///
/// Gibt `true` zurück, wenn der Draft tatsächlich gestartet wurde.
Future<bool> draftStartenMitBestaetigung(
  BuildContext context,
  WidgetRef ref,
  FantasyLeague league,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final teams = ref
      .read(fantasyManagersProvider(league.id))
      .valueOrNull
      ?.length;
  // **Reset-Draft** (0143): Die Reihenfolge steht fest — Tabellenletzter
  // zuerst. Sie kommt aus derselben Tabelle, die die App anzeigt.
  final reset = league.draftStatus == DraftStatus.reset;
  final resetFolge = reset
      ? ref.read(resetReihenfolgeProvider(league.id))
      : null;
  if (reset && resetFolge == null) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Die Tabelle lädt noch — gleich noch einmal versuchen.'),
      ),
    );
    return false;
  }
  // **Ein Blatt statt eines Material-Dialogs** (19.10.2026), und seit
  // demselben Tag **bearbeitbar**: Zeit je Pick, Runden und Reihenfolge
  // lassen sich hier noch ändern, ohne erst in die Einstellungen zu gehen
  // (auf Ansage). Dieselben Grenzen wie dort.
  final wahl = await showModalBottomSheet<_StartWahl>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    builder: (ctx) =>
        _StartBlatt(league: league, teams: teams, resetFolge: resetFolge),
  );
  if (wahl == null) return false;

  try {
    final repo = ref.read(draftRepositoryProvider);
    // Erst die geänderten Einstellungen schreiben, dann starten — der Start
    // friert sie ein.
    if (wahl.geaendert(league)) {
      await ref
          .read(fantasyLeagueRepositoryProvider)
          .updateDraftSettings(
            league.id,
            pickTime: wahl.pickTime,
            roster: league.roster.withRounds(wahl.runden),
            pauseStart: league.pauseStart,
            pauseEnd: league.pauseEnd,
            orderMode: reset ? league.draftOrderMode : wahl.reihenfolge,
          );
    }
    if (reset) {
      await repo.startResetDraft(league.id, [
        for (final m in resetFolge!) m.userId,
      ]);
    } else {
      await repo.startDraft(league.id);
    }
    ref.invalidate(draftLeagueProvider(league.id));
    ref.invalidate(fantasyManagersProvider(league.id));
    ref.invalidate(myFantasyLeaguesProvider);
    return true;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Fehlgeschlagen: $e')));
    return false;
  }
}

/// Was im Blatt eingestellt wurde.
class _StartWahl {
  const _StartWahl({
    required this.pickTime,
    required this.runden,
    required this.reihenfolge,
  });

  final DraftPickTime pickTime;
  final int runden;

  /// `auto` oder `manual`.
  final String reihenfolge;

  bool geaendert(FantasyLeague l) =>
      pickTime != l.pickTime ||
      runden != l.rounds ||
      (l.draftStatus != DraftStatus.reset && reihenfolge != l.draftOrderMode);
}

class _StartBlatt extends StatefulWidget {
  const _StartBlatt({
    required this.league,
    required this.teams,
    this.resetFolge,
  });

  final FantasyLeague league;
  final int? teams;

  /// Gesetzt beim Reset-Draft: die feste Pick-Folge der ersten Runde.
  final List<FantasyManager>? resetFolge;

  /// Dieselben Grenzen wie `DraftSettingsPage`.
  static const minRunden = 14;
  static const maxRunden = 30;

  @override
  State<_StartBlatt> createState() => _StartBlattState();
}

class _StartBlattState extends State<_StartBlatt> {
  late DraftPickTime _pickTime = widget.league.pickTime;
  late int _runden = widget.league.rounds.clamp(
    _StartBlatt.minRunden,
    _StartBlatt.maxRunden,
  );
  late String _reihenfolge = widget.league.draftOrderMode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const hoch = Size.fromHeight(50);
    const wertStil = TextStyle(
      fontSize: Schrift.text,
      fontWeight: FontWeight.w800,
    );
    final stufen = DraftPickTime.values;
    final stufe = stufen.indexOf(_pickTime);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.resetFolge != null
                  ? 'RESET-DRAFT STARTEN?'
                  : 'DRAFT STARTEN?',
              style: TextStyle(
                fontSize: Schrift.gross,
                fontWeight: Schrift.ueberschriftGewicht,
                fontStyle: Schrift.ueberschriftStil,
              ),
            ),
            const SizedBox(height: 8),
            // Punkt 9: Der Draft ist kein Termin — das steht hier, wo
            // gestartet wird, und zieht mit der gewählten Zeit mit.
            Text(
              _pickTime.ablaufSatz,
              style: TextStyle(
                fontSize: Schrift.text,
                height: 1.35,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (widget.teams != null) ...[
              EinstellungsZeile(
                label: 'Teams',
                rechts: Text('${widget.teams}', style: wertStil),
              ),
              const EinstellungsTrenner(),
            ],
            EinstellungsZeile(
              label: 'Zeit je Pick',
              unter: _pickTime.ablauf,
              rechts: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Zeit je Pick verringern',
                    visualDensity: VisualDensity.compact,
                    onPressed: stufe > 0
                        ? () => setState(() => _pickTime = stufen[stufe - 1])
                        : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  SizedBox(
                    width: 92,
                    child: Text(
                      _pickTime.label,
                      textAlign: TextAlign.center,
                      style: wertStil,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Zeit je Pick erhöhen',
                    visualDensity: VisualDensity.compact,
                    onPressed: stufe < stufen.length - 1
                        ? () => setState(() => _pickTime = stufen[stufe + 1])
                        : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
            ),
            const EinstellungsTrenner(),
            EinstellungsZeile(
              label: 'Runden',
              unter: '11 Startelf + ${_runden - 11} Bank',
              rechts: WertStepper(
                label: 'Runden',
                value: _runden,
                min: _StartBlatt.minRunden,
                max: _StartBlatt.maxRunden,
                onChanged: (v) => setState(() => _runden = v),
              ),
            ),
            const EinstellungsTrenner(),
            if (widget.resetFolge case final folge?) ...[
              const EinstellungsZeile(
                label: 'Reihenfolge',
                unter: 'Letzter zuerst, danach Snake',
                rechts: Text('Nach Tabelle', style: wertStil),
              ),
              _ResetFolge(folge: folge),
            ] else ...[
              EinstellungsZeile(
                label: 'Reihenfolge',
                // Feste Breite: Der Umschalter teilt seinen Platz auf und
                // bekäme in der Zeile sonst keine Grenze.
                rechts: SizedBox(
                  width: 190,
                  child: PillSelector<String>(
                    options: const {'auto': 'Zufällig', 'manual': 'Manuell'},
                    value: _reihenfolge,
                    onSelect: (v) => setState(() => _reihenfolge = v),
                  ),
                ),
              ),
              if (_reihenfolge == 'manual')
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Reihenfolge festlegen',
                    style: einstellungsStil,
                  ),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: scheme.onSurfaceVariant,
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DraftOrderPage(league: widget.league),
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.lock_outline, size: 16, color: context.farben.gold),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.resetFolge != null
                        ? 'Die Tabelle bleibt. Bis zum Ende des Drafts sind '
                              'keine Transfers möglich.'
                        : 'Danach lassen sich Reihenfolge und Teams nicht mehr ändern.',
                    style: TextStyle(
                      fontSize: Schrift.label,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(
                _StartWahl(
                  pickTime: _pickTime,
                  runden: _runden,
                  reihenfolge: _reihenfolge,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: context.farben.gold,
                foregroundColor: scheme.surface,
                minimumSize: hoch,
              ),
              child: Text(
                widget.resetFolge != null
                    ? 'Reset-Draft starten'
                    : 'Draft starten',
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                minimumSize: hoch,
                foregroundColor: scheme.onSurfaceVariant,
              ),
              child: const Text('Abbrechen'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Die feste Pick-Folge der ersten Runde, nummeriert — der Tabellenletzte
/// steht oben. Höchstens so hoch, dass die Knöpfe sichtbar bleiben.
class _ResetFolge extends StatelessWidget {
  const _ResetFolge({required this.folge});

  final List<FantasyManager> folge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.28,
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 4),
        children: [
          for (final (i, m) in folge.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${i + 1}.',
                      style: TextStyle(
                        fontSize: Schrift.text,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      m.display,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: Schrift.text),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
