import '../../../app/farben.dart';
import 'package:flutter/material.dart';
import '../../../core/ui/rueckfrage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/typografie.dart';
import '../../../core/logic/vereins_kuerzel.dart';
import '../../../core/ui/einstellungs_zeile.dart';
import '../logic/fantasy_scoring_engine.dart';
import '../logic/spieler_schnitt.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';
import 'club_badge.dart';
import 'player_profile_sheet.dart';
import 'trade_screen.dart';
import 'spieler_name.dart';

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
    // **Reset zur Winterpause** (0143): Bis der Reset-Draft fertig ist,
    // kommt niemand außer über den Draft in einen Kader — der Server lehnt
    // jeden anderen Weg ab, also gibt es hier keinen Knopf.
    if (league.imReset) {
      return breit
          ? const _WeiterChip(text: 'Reset-Draft läuft')
          : const _MiniChip(text: 'Reset');
    }
    if (ownerId != null) {
      if (ownerId == myId) {
        return breit
            ? const _WeiterChip(text: 'In deinem Kader')
            : const _MiniChip(text: 'Dein Team');
      }
      return _knopf(
        context,
        color: context.farben.rot,
        fg: Colors.white,
        icon: Icons.swap_horiz,
        label: 'Trade anbieten',
        onTap: () => _trade(context, ref),
      );
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
        color: context.farben.gold,
        fg: context.istHell ? Colors.white : Colors.black,
        icon: Icons.schedule_outlined,
        label: 'Waiver-Antrag stellen',
        onTap: () => _claim(context, ref),
      );
    }
    return _knopf(
      context,
      color: context.farben.gruen,
      fg: context.istHell ? Colors.white : Colors.black,
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
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: fg,
      ),
      onPressed: onTap,
      child: Text(label),
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
      showDragHandle: false,
      builder: (_) => _RosterMoveSheet(
        league: league,
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
      // **„Er liegt auf dem Waiver" ist keine Sackgasse.** Der Knopf sagt
      // „Holen", weil die Oberfläche den Anpfiff seines Vereins noch nicht
      // gesehen hatte — der Schirm hat dafür eine Uhr, aber ein Gerät, das
      // eine Minute nachgeht, oder ein Anpfiff, der sich verschiebt, reichen
      // aus. Statt den Nutzer mit einer Fehlermeldung stehen zu lassen, wird
      // der Wire-Stand neu geholt: Beim nächsten Aufbau steht dort der
      // Antragsknopf, und der Weg ist wieder offen.
      if (e.toString().contains('Waiver')) {
        ref.invalidate(waiverPlayersProvider(league.id));
        ref.invalidate(fantasySeasonFixturesProvider);
      }
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

    final cancel = await rueckfrage(
      context,
      titel: 'Kader ist jetzt voll',
      text:
          'Dein offener Waiver-Antrag ohne Abgang ($names) wird bei der '
          'Abarbeitung ungültig, weil kein Kaderplatz mehr frei ist. Jetzt '
          'stornieren? Für einen neuen Antrag musst du dann einen Abgang '
          'festlegen.',
      ja: 'Stornieren',
      nein: 'Behalten',
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
      showDragHandle: false,
      builder: (_) => _RosterMoveSheet(
        league: league,
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

// Hier stand `_LockedChip`: ein Schloss mit der Beschriftung „U20-Draft" an
// einem Rookie, der für den zweiten Draft reserviert war. Die Reservierung gab
// es nur in Dynasty; mit dem Modus ist sie samt Schloss entfallen.

/// Ergebnis des Roster-Move-Sheets: gewählter Abgang (oder null = kein Drop).
class _MoveConfirm {
  const _MoveConfirm(this.dropId);
  final String? dropId;
}

/// Bestätigungs-Sheet für einen Free-Agent-Move: zeigt den Neuzugang und —
/// falls der Kader voll ist — die Auswahl, wer dafür Platz macht.
/// Drop-Modus des Move-Sheets: keiner / Pflicht (Kader voll) / optional (Waiver).
enum _DropMode { none, mustDrop, mayDrop }

class _RosterMoveSheet extends ConsumerStatefulWidget {
  const _RosterMoveSheet({
    required this.league,
    required this.incoming,
    required this.myPlayers,
    required this.mode,
    required this.title,
    this.note,
  });

  final FantasyLeague league;
  final FantasyPlayer incoming;
  final List<FantasyPlayer> myPlayers;
  final _DropMode mode;
  final String title;

  /// Optionaler Hinweis unter dem Titel (z. B. „freier Platz vorhanden").
  final String? note;

  @override
  ConsumerState<_RosterMoveSheet> createState() => _RosterMoveSheetState();
}

/// **Das Blatt fürs Holen und für Waiver-Anträge** (19.10.2026, auf Ansage:
/// „man kann nicht auf das Profil des Spielers draufdrücken, sondern nur den
/// auswählen"). Jede Zeile hat jetzt zwei Ziele: ein Tipp auf die Zeile wählt
/// aus, der Pfeil rechts öffnet das Profil — über dem Blatt, das danach
/// stehen bleibt. Dazu Wappen, Position und Ø, damit man vergleichen kann,
/// wen man abgibt. Die beiden farbig gerahmten Kästen sind ruhigen Zeilen
/// unter einer schrägen Marke gewichen.
class _RosterMoveSheetState extends ConsumerState<_RosterMoveSheet> {
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
    // **Der Knopf muss stehen bleiben.** Bei vollem Kader standen „Abbrechen"
    // und „Bestätigen" einmal unter sechzehn Kaderzeilen — außerhalb des
    // Bildes, und das Blatt ging ohne einen Laut wieder zu. Kopf und Aktionen
    // stehen fest, nur die Liste scrollt.
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title.toUpperCase(),
                    style: const TextStyle(
                      fontSize: Schrift.gross,
                      fontWeight: Schrift.ueberschriftGewicht,
                      fontStyle: Schrift.ueberschriftStil,
                    ),
                  ),
                  if (widget.note != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      widget.note!,
                      style: TextStyle(
                        fontSize: Schrift.text,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(20, 6, 12, 0),
                children: [
                  _Marke(text: 'Kommt rein', farbe: context.farben.gruen),
                  _zeile(widget.incoming, auswahl: null),
                  if (widget.mode != _DropMode.none) ...[
                    _Marke(
                      text: widget.mode == _DropMode.mustDrop
                          ? 'Wer macht Platz?'
                          : 'Wer macht Platz? (optional)',
                      farbe: context.farben.rot,
                    ),
                    for (final (i, p) in sorted.indexed) ...[
                      if (i > 0) const EinstellungsTrenner(),
                      _zeile(p, auswahl: _dropId == p.id),
                    ],
                  ],
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // **Ein grauer Knopf sagt nicht, was fehlt.**
                    if (!canConfirm) ...[
                      Text(
                        'Wähle oben, wer Platz macht.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: context.farben.gold,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                      ),
                      onPressed: canConfirm
                          ? () =>
                                Navigator.of(context).pop(_MoveConfirm(_dropId))
                          : null,
                      child: const Text('Bestätigen'),
                    ),
                    const SizedBox(height: 4),
                    TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                        foregroundColor: scheme.onSurfaceVariant,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Abbrechen'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Eine Spielerzeile. [auswahl] `null` = nicht wählbar (der Neuzugang);
  /// sonst wählt ein Tipp auf die Zeile aus und der Pfeil öffnet das Profil.
  Widget _zeile(FantasyPlayer p, {required bool? auswahl}) {
    final scheme = Theme.of(context).colorScheme;
    final icons =
        ref.watch(clubIconsProvider).valueOrNull ?? const <String, String?>{};
    final saison = ref.watch(seasonStatsProvider).valueOrNull;
    final fertig = gewerteteRunden(
      ref.watch(abgepfiffeneRundenProvider),
      saison?.keys ?? const [],
    );
    final schnitt = saison == null
        ? null
        : spielerSchnitt(
            saison: {
              for (final e in saison.entries)
                if (fertig.contains(e.key)) e.key: e.value,
            },
            spielerId: p.id,
            position: p.position,
            regeln: widget.league.scoring,
          ).punkteJeEinsatz;
    final unter = [
      p.position.short,
      vereinsKuerzel(p.club),
      if (schnitt != null) 'Ø ${formatPoints(schnitt)}',
    ].join(' · ');

    void profil() => showPlayerProfile(
      context,
      league: widget.league,
      player: p,
      clubIcon: icons[p.club],
      isMine: auswahl != null,
    );

    final gewaehlt = auswahl == true;
    return Material(
      color: gewaehlt
          ? context.farben.rot.withValues(alpha: 0.12)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        // Der Neuzugang hat nichts zu wählen — dort öffnet die Zeile das
        // Profil gleich selbst.
        onTap: auswahl == null
            ? profil
            : () => setState(() => _dropId = gewaehlt ? null : p.id),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 58),
          child: Row(
            children: [
              if (auswahl != null) ...[
                Icon(
                  gewaehlt ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 22,
                  color: gewaehlt
                      ? context.farben.rot
                      : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
              ],
              ClubBadge(club: p.club, iconUrl: icons[p.club], size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestufterSpielerName(p.name),
                    Text(
                      unter,
                      style: TextStyle(
                        fontSize: Schrift.label,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Profil von ${p.name}',
                onPressed: profil,
                icon: Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Schräge Marke über einem Abschnitt des Blatts, mit Zeichen in der Farbe
/// der Richtung (rein grün, raus rot).
class _Marke extends StatelessWidget {
  const _Marke({required this.text, required this.farbe});

  final String text;
  final Color farbe;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 4),
    child: Row(
      children: [
        Icon(
          farbe == context.farben.gruen ? Icons.add : Icons.remove,
          size: 16,
          color: farbe,
        ),
        const SizedBox(width: 6),
        Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: Schrift.label,
            fontWeight: Schrift.ueberschriftGewicht,
            fontStyle: Schrift.ueberschriftStil,
            letterSpacing: 1.2,
            color: farbe,
          ),
        ),
      ],
    ),
  );
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
