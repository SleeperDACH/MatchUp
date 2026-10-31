import '../../../app/farben.dart';
import 'package:flutter/material.dart';

import '../../../app/typografie.dart';
import '../../../app/widgets/karte.dart';
import '../../../core/logic/vereins_kuerzel.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/ui/league_chat.dart' show ChatLigaZeichen;
import '../logic/transfer_vorgaenge.dart';
import '../models/fantasy_models.dart';
import '../models/roster_move.dart';
import 'club_badge.dart';
import 'spieler_kachel.dart';

/// **Kaderbewegungen im Liga-Chat** — nach dem Vorbild Sleeper (auf Ansage,
/// 17.10.2026): „@Name made a roster move." und darunter eine Karte mit den
/// Spielern, Zugang mit grünem Plus, Abgang mit rotem Minus. Gilt für Free
/// Agency, Waiver und Trades.
///
/// **Nicht als Text in der Datenbank.** Solche Meldungen standen bis zum
/// 06.10.2026 als Systemzeilen im Chat und flogen auf Ansage raus (Migration
/// 0106) — als reine Textzeilen füllten sie den halben Verlauf. Jetzt setzt die
/// App sie aus dem Kaderprotokoll (`fantasy_roster_moves`) zusammen, derselben
/// Quelle wie der Transfers-Bereich: Sie stehen nach Zeit zwischen den
/// Nachrichten, auch die schon vergangenen, und nichts wird doppelt
/// gespeichert. Der Draft fehlt bewusst — er erzeugte Hunderte Meldungen; dafür
/// gibt es das Board.

/// Präfix der Nachrichten-IDs, an denen [KaderMeldung] sie wiedererkennt.
const kaderMeldungPraefix = 'kader:';

/// Die Kaderbewegungen als Chat-Einträge, jeweils mit ihrem Ereignis.
Map<String, ({ChatMessage nachricht, TransferEreignis ereignis})>
kaderMeldungen(List<RosterMove> moves) {
  final out = <String, ({ChatMessage nachricht, TransferEreignis ereignis})>{};
  for (final e in ereignisseAus(moves)) {
    if (e.weg == 'draft') continue;
    final id =
        '$kaderMeldungPraefix${e.passiertAm.microsecondsSinceEpoch}'
        ':${e.seiten.map((s) => s.managerId).join('+')}';
    out[id] = (
      nachricht: ChatMessage(
        id: id,
        userId: null,
        body: '',
        createdAt: e.passiertAm,
        isSystem: true,
      ),
      ereignis: e,
    );
  }
  return out;
}

/// Eine Kaderbewegung im Chat: Liga-Zeichen, Satz, Karte mit den Spielern.
class KaderMeldung extends StatelessWidget {
  const KaderMeldung({
    super.key,
    required this.ereignis,
    required this.namen,
    required this.spieler,
    required this.clubIcons,
    this.onSpieler,
  });

  final TransferEreignis ereignis;
  final Map<String, String> namen;
  final Map<String, FantasyPlayer> spieler;
  final Map<String, String?> clubIcons;
  final void Function(FantasyPlayer)? onSpieler;

  String _satz() {
    String n(String id) => '@${namen[id] ?? '?'}';
    if (ereignis.istTrade) {
      return '${n(ereignis.seiten[0].managerId)} und '
          '${n(ereignis.seiten[1].managerId)} haben getauscht.';
    }
    final s = ereignis.seiten.single;
    return switch (s.weg) {
      'waiver' => '${n(s.managerId)} hat einen Waiver-Antrag gewonnen.',
      'trade' => '${n(s.managerId)} hat getauscht.',
      'abgewandert' =>
        'Bei ${n(s.managerId)} hat ein Spieler die '
            'Bundesliga verlassen.',
      _ =>
        s.nurAbgang
            ? '${n(s.managerId)} hat einen Spieler abgegeben.'
            : '${n(s.managerId)} hat den Kader geändert.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Je Seite die Kacheln: bei einem Trade erhält jede Seite, was die andere
    // abgibt — die Zugänge beider Seiten sagen also alles.
    final List<({String? kopf, List<(RosterMove, bool)> kacheln})> gruppen =
        ereignis.istTrade
        ? [
            for (final s in ereignis.seiten)
              (
                kopf: namen[s.managerId] ?? '?',
                kacheln: [for (final m in s.rein) (m, true)],
              ),
          ]
        : [
            (
              kopf: null,
              kacheln: [
                for (final m in ereignis.seiten.single.rein) (m, true),
                for (final m in ereignis.seiten.single.raus) (m, false),
              ],
            ),
          ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ChatLigaZeichen(),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Text(
                  _satz(),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: kartenDeko(context, radius: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (i, g) in gruppen.indexed) ...[
                        if (i > 0) const SizedBox(height: 10),
                        if (g.kopf != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              '${g.kopf} bekommt',
                              style: TextStyle(
                                fontSize: Schrift.label,
                                fontWeight: FontWeight.w700,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        Wrap(
                          spacing: 14,
                          runSpacing: 10,
                          children: [
                            for (final (m, rein) in g.kacheln)
                              _Spieler(
                                spieler: spieler[m.playerId],
                                id: m.playerId,
                                rein: rein,
                                iconUrl: clubIcons[spieler[m.playerId]?.club],
                                onTap: onSpieler,
                              ),
                          ],
                        ),
                      ],
                    ],
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

/// Ein Spieler in der Meldung: Wappen mit Plus oder Minus, Name, Position und
/// Verein.
class _Spieler extends StatelessWidget {
  const _Spieler({
    required this.spieler,
    required this.id,
    required this.rein,
    required this.iconUrl,
    required this.onTap,
  });

  final FantasyPlayer? spieler;
  final String id;
  final bool rein;
  final String? iconUrl;
  final void Function(FantasyPlayer)? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = spieler;
    final inhalt = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: p == null
                    ? Icon(Icons.person_outline, color: scheme.onSurfaceVariant)
                    : ClubBadge(club: p.club, iconUrl: iconUrl, size: 34),
              ),
              Positioned(
                right: -3,
                bottom: -3,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: rein ? context.farben.gruen : context.farben.rot,
                    border: Border.all(color: scheme.surface, width: 2),
                  ),
                  child: Icon(
                    rein ? Icons.add : Icons.remove,
                    size: 11,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              p == null ? id : SpielerKachel.kurzerName(p.name).toUpperCase(),
              style: const TextStyle(
                fontSize: Schrift.text,
                fontWeight: Schrift.ueberschriftGewicht,
                fontStyle: Schrift.ueberschriftStil,
              ),
            ),
            if (p != null)
              Text(
                '${p.position.short} · ${vereinsKuerzel(p.club)}',
                style: TextStyle(
                  fontSize: Schrift.label,
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ],
    );
    final ziel = onTap;
    if (p == null || ziel == null) return inhalt;
    return Semantics(
      button: true,
      label: '${p.name}, ${rein ? 'Zugang' : 'Abgang'}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => ziel(p),
        child: inhalt,
      ),
    );
  }
}
