import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/fantasy_models.dart';
import '../providers.dart';
import 'club_badge.dart';
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
    this.aufWire = false,
    required this.claimed,
    required this.myPlayers,
    required this.nextRank,
    required this.myId,
    this.breit = false,
  });

  final FantasyLeague league;
  final FantasyPlayer player;

  /// Manager, der den Spieler besitzt — null, wenn frei oder auf dem Wire.
  final String? ownerId;
  final bool onWaiver;
  final bool claimed;

  /// **Er liegt auf dem Waiver**, weil sein Verein angepfiffen hat und die
  /// Frist (Montag 15:00, in englischen Wochen Donnerstag) noch nicht erreicht
  /// ist. Dann ist er nicht *direkt* holbar — der Server lehnt das ab
  /// (`fantasy_auf_dem_wire`, Migration 0107), und es brächte auch nichts: Die
  /// Aufstellung ist für ihn diesen Spieltag ohnehin gesperrt (0084).
  ///
  /// **Beantragen geht** (0095): Der Antrag sagt „ich will ihn ab nächster
  /// Woche", und zur Frist wird er in Prioritätsreihenfolge eingelöst.
  final bool aufWire;
  final List<FantasyPlayer> myPlayers;
  final int nextRank;
  final String? myId;

  /// **Breite Fassung mit Beschriftung** — für das Spielerprofil, wo eine
  /// Aktionsleiste steht und kein Listenrand. Die Entscheidung, *welche*
  /// Aktion möglich ist, bleibt dieselbe: Sie steht einmal in [build], und
  /// genau deshalb kennt das Profil den Waiver, die U20-Sperre und den
  /// Kadervoll-Fall, ohne eine Regel zu wiederholen.
  final bool breit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // **Wer die Bundesliga verlassen hat, ist für niemanden mehr zu haben** —
    // weder zu holen noch zu traden. Steht vor der Besitzfrage: Solange er
    // noch in der Elf der laufenden Runde steht, bleibt er im Kader (0117),
    // aber ein Trade auf ihn wäre schon hinfällig, wenn er angenommen wird.
    if (player.abgewandert) {
      return breit
          ? const _WeiterChip(text: 'Hat die Bundesliga verlassen')
          : const _MiniChip(text: 'Nicht mehr in der BL');
    }
    if (ownerId != null) {
      if (ownerId == myId) {
        return breit
            ? const _WeiterChip(text: 'In deinem Kader')
            : const _MiniChip(text: 'Dein Team');
      }
      return _knopf(
        context,
        color: _cTrade,
        fg: Colors.white,
        icon: Icons.swap_horiz,
        label: 'Trade anbieten',
        onTap: () => _trade(context, ref),
      );
    }
    if (player.isLockedNow(league.season)) {
      return breit
          ? const _WeiterChip(text: 'Für den U20-Draft gesperrt')
          : const _LockedChip();
    }
    // **Wire und laufendes Spiel führen zum selben Knopf.** Beides heißt
    // „jetzt nicht direkt, aber beantragen kannst du ihn" — und der Antrag
    // ist gefahrlos, weil das Waiver-Fenster zwei Tage vor dem nächsten
    // Spieltag liegt (`fantasy_next_waiver_window`): Er wird nie mitten in
    // einer laufenden Runde abgearbeitet.
    if (onWaiver || aufWire) {
      if (claimed) {
        return breit
            ? const _WeiterChip(text: 'Antrag läuft')
            : const _MiniChip(text: 'Beantragt');
      }
      return _knopf(
        context,
        color: _cWaiver,
        fg: Colors.black,
        icon: Icons.schedule,
        label: 'Waiver-Antrag stellen',
        onTap: () => _claim(context, ref),
      );
    }
    return _knopf(
      context,
      color: _cAdd,
      fg: Colors.black,
      icon: Icons.add,
      label: 'Holen',
      onTap: () => _add(context, ref),
    );
  }

  /// Rund in der Liste, breit mit Wort im Profil — dieselbe Aktion.
  Widget _knopf(
    BuildContext context, {
    required Color color,
    required Color fg,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    if (!breit) {
      return _RoundBtn(
        color: color,
        fg: fg,
        icon: icon,
        tooltip: label,
        onTap: onTap,
      );
    }
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: fg,
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final needsDrop = myPlayers.length >= league.roster.squadSize;
    // Roster-Move zur Bestätigung anzeigen (rein / ggf. raus).
    final confirm = await showModalBottomSheet<_MoveConfirm>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RosterMoveSheet(
        incoming: player,
        myPlayers: myPlayers,
        mode: needsDrop ? _DropMode.mustDrop : _DropMode.none,
        title: 'Kader-Move',
      ),
    );
    if (confirm == null || !context.mounted) return;
    try {
      await ref
          .read(fantasyLeagueRepositoryProvider)
          .addFreeAgent(league.id, player.id, dropPlayerId: confirm.dropId);
      // Realtime greift bei RPC-Moves nicht zuverlässig — Kader/Wire/Aufstellung
      // sofort neu laden, damit der Move überall konsistent sichtbar ist.
      ref.invalidate(leagueRosterProvider(league.id));
      ref.invalidate(waiverPlayersProvider(league.id));
      ref.invalidate(leagueLineupsProvider(league.id));
      if (context.mounted) _toast(context, '${player.name} aufgenommen');
      // Hat dieser Zugang den letzten freien Platz belegt (ohne eigenen Drop),
      // werden offene Waiver-Anträge ohne Abgang bei der Abarbeitung ungültig.
      // Nutzer warnen und Storno anbieten, statt sie still verfallen zu lassen.
      final filledLastSpot =
          confirm.dropId == null &&
          myPlayers.length + 1 >= league.roster.squadSize;
      if (filledLastSpot && context.mounted) {
        await _warnStaleWaiverClaims(context, ref);
      }
    } catch (e) {
      if (context.mounted) _toast(context, 'Fehlgeschlagen: $e');
    }
  }

  /// Warnt nach einem Kader-vollmachenden Zugang vor offenen Waiver-Anträgen
  /// ohne Abgang (die sonst als „Kader voll" ungültig würden) und bietet an,
  /// sie zu stornieren — damit der Nutzer sie mit Abgang neu stellen kann.
  Future<void> _warnStaleWaiverClaims(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final claims =
        ref.read(myWaiverClaimsProvider(league.id)).valueOrNull ??
        const <WaiverClaim>[];
    final stale = claims
        .where((c) => c.status.isPending && c.dropPlayerId == null)
        .toList();
    if (stale.isEmpty) return;

    final pool =
        ref.read(playerPoolProvider).valueOrNull ?? const <FantasyPlayer>[];
    final nameById = {for (final p in pool) p.id: p.name};
    final names = stale
        .map((c) => nameById[c.addPlayerId] ?? c.addPlayerId)
        .join(', ');

    final cancel = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kader ist jetzt voll'),
        content: Text(
          'Dein offener Waiver-Antrag ohne Abgang ($names) wird bei der '
          'Abarbeitung ungültig, weil kein Kaderplatz mehr frei ist. Jetzt '
          'stornieren? Für einen neuen Antrag musst du dann einen Abgang '
          'festlegen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Behalten'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Stornieren'),
          ),
        ],
      ),
    );
    if (cancel != true) return;

    final repo = ref.read(fantasyLeagueRepositoryProvider);
    for (final c in stale) {
      try {
        await repo.cancelWaiverClaim(c.id);
      } catch (_) {
        // Antrag war zwischenzeitlich schon weg — kein echter Fehler.
      }
    }
    ref.invalidate(myWaiverClaimsProvider(league.id));
    if (context.mounted) {
      _toast(context, 'Waiver-Antrag storniert — mit Abgang neu stellen.');
    }
  }

  Future<void> _claim(BuildContext context, WidgetRef ref) async {
    // Kader voll? Dann ist ein Abgang Pflicht, sonst wäre der Antrag bei der
    // Abarbeitung garantiert ungültig. Bei freiem Platz genügt der reine Claim.
    final full = myPlayers.length >= league.roster.squadSize;
    final confirm = await showModalBottomSheet<_MoveConfirm>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RosterMoveSheet(
        incoming: player,
        myPlayers: myPlayers,
        mode: full ? _DropMode.mustDrop : _DropMode.mayDrop,
        title: 'Waiver-Antrag',
        note: full
            ? 'Dein Kader ist voll — ohne Abgang wird der Antrag bei der '
                  'Abarbeitung ungültig. Wähle, wer Platz macht.'
            : 'Freier Kaderplatz vorhanden — ein Abgang ist nicht nötig.',
      ),
    );
    if (confirm == null || !context.mounted) return;
    try {
      await ref
          .read(fantasyLeagueRepositoryProvider)
          .submitWaiverClaim(
            league.id,
            player.id,
            dropPlayerId: confirm.dropId,
            rank: nextRank,
          );
      ref.invalidate(myWaiverClaimsProvider(league.id));
      ref.invalidate(waiverPlayersProvider(league.id));
      if (context.mounted) {
        _toast(context, 'Antrag für ${player.name} gestellt');
      }
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
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TradeComposeScreen(
          league: league,
          partner: owner!,
          initialRequest: {player.id},
        ),
      ),
    );
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
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
      ),
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
        Text(
          'U20-Draft',
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Ergebnis des Roster-Move-Sheets: gewählter Abgang (oder null = kein Drop).
class _MoveConfirm {
  const _MoveConfirm(this.dropId);
  final String? dropId;
}

/// Bestätigungs-Sheet für einen Free-Agent-Move: zeigt den Neuzugang und —
/// falls der Kader voll ist — die Auswahl, wer dafür Platz macht.
/// Drop-Modus des Move-Sheets: keiner / Pflicht (Kader voll) / optional (Waiver).
enum _DropMode { none, mustDrop, mayDrop }

class _RosterMoveSheet extends StatefulWidget {
  const _RosterMoveSheet({
    required this.incoming,
    required this.myPlayers,
    required this.mode,
    required this.title,
    this.note,
  });

  final FantasyPlayer incoming;
  final List<FantasyPlayer> myPlayers;
  final _DropMode mode;
  final String title;

  /// Optionaler Hinweis unter dem Titel (z. B. „freier Platz vorhanden").
  final String? note;

  @override
  State<_RosterMoveSheet> createState() => _RosterMoveSheetState();
}

class _RosterMoveSheetState extends State<_RosterMoveSheet> {
  String? _dropId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canConfirm = widget.mode != _DropMode.mustDrop || _dropId != null;
    // Nach Position sortiert (TW → ABW → MF → ST), dann Name.
    final sorted = [...widget.myPlayers]
      ..sort(
        (a, b) => a.position.index != b.position.index
            ? a.position.index.compareTo(b.position.index)
            : a.name.compareTo(b.name),
      );
    // **Der Knopf muss stehen bleiben.** Vorher lag das ganze Blatt in einem
    // `SingleChildScrollView`, und bei vollem Kader standen „Abbrechen" und
    // „Bestätigen" unter sechzehn Kaderzeilen — außerhalb des Bildes. Gemeldet
    // als „ich habe einen Antrag gestellt, er wird nicht angezeigt": Das Blatt
    // ging auf, der Abschicken-Knopf war nie zu sehen, und geschlossen wurde
    // es ohne einen Laut (`confirm == null` kehrt stumm zurück).
    //
    // Jetzt: Kopf und Aktionen fest, nur die Spielerliste scrollt.
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (widget.note != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      widget.note!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _block(
                      context,
                      icon: Icons.add,
                      label: 'Kommt rein',
                      color: _cAdd,
                      child: _playerRow(widget.incoming),
                    ),
                    if (widget.mode != _DropMode.none) ...[
                      const SizedBox(height: 8),
                      Icon(
                        Icons.arrow_downward,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 8),
                      _block(
                        context,
                        icon: Icons.remove,
                        label: widget.mode == _DropMode.mustDrop
                            ? 'Kader voll — wer macht Platz?'
                            : 'Optional: wen abgeben? (nur bei vollem Kader nötig)',
                        color: _cTrade,
                        child: Column(
                          children: [
                            for (final p in sorted)
                              _dropRow(p, _dropId == p.id),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // **Ein grauer Knopf sagt nicht, was fehlt.** Der Hinweis
                  // stand nur oben im Blatt, außer Sicht, sobald man zur Liste
                  // gescrollt hatte.
                  if (!canConfirm) ...[
                    Text(
                      'Wähle oben, wer Platz macht.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _cWaiver,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Abbrechen'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: canConfirm
                              ? () => Navigator.of(
                                  context,
                                ).pop(_MoveConfirm(_dropId))
                              : null,
                          icon: const Icon(Icons.check),
                          label: const Text('Bestätigen'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _block(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(fontWeight: FontWeight.bold, color: color),
              ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _playerRow(FantasyPlayer p) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PositionPill(pos: p.position),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            '${p.name} · ${p.club}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _dropRow(FantasyPlayer p, bool selected) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected
            ? _cTrade.withValues(alpha: 0.18)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() => _dropId = selected ? null : p.id),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? _cTrade : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                PositionPill(pos: p.position),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                Icon(
                  selected ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 20,
                  color: selected ? _cTrade : scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ein Zustand statt einer Aktion, in der breiten Fassung: „hier ist nichts zu
/// tun, und das ist der Grund". Ein Knopf, der nichts kann, wäre schlechter
/// als ein Satz.
class _WeiterChip extends StatelessWidget {
  const _WeiterChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
