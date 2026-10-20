import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/widgets/competition_emblem.dart';
import '../../../app/widgets/kapitelmarke.dart';
import '../../../app/widgets/league_logo.dart';
import '../../../app/widgets/skelett.dart';
import '../../../core/models/models.dart';
import '../../../core/ui/einstellungs_zeile.dart';
import '../../favorites/favorites.dart';
import '../../tippspiel/ui/team_badge.dart';
import '../live_abos.dart';

/// Der Stand, den der Schirm gerade zeigt — vor der Serverantwort.
///
/// Ein Schalter, der erst nach der Antwort umspringt, fühlt sich kaputt an
/// (dieselbe Regel wie bei den übrigen Push-Schaltern). Übersicht und
/// Ligaschirm lesen denselben Stand, damit „3 Vereine" beim Zurückgehen
/// schon stimmt.
final _lokalProvider = StateProvider<LiveAbos?>((ref) => null);

LiveAbos? _stand(WidgetRef ref) =>
    ref.watch(_lokalProvider) ?? ref.watch(liveAbosProvider).valueOrNull;

Future<void> _setzen(
  BuildContext context,
  WidgetRef ref, {
  String? verein,
  String? liga,
  required bool an,
}) async {
  final vorher = ref.read(_lokalProvider) ??
      ref.read(liveAbosProvider).valueOrNull ??
      const LiveAbos();
  final nachher = verein != null
      ? vorher.mitVerein(verein, an)
      : vorher.mitLiga(liga!, an);
  ref.read(_lokalProvider.notifier).state = nachher;
  try {
    await ref.read(liveAbosRepositoryProvider).setzen(
        verein != null ? 'verein' : 'liga', verein ?? liga!, an);
    ref.invalidate(liveAbosProvider);
  } catch (e) {
    ref.read(_lokalProvider.notifier).state = vorher;
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Konnte nicht gespeichert werden: $e')));
    }
  }
}

/// **Live-Meldungen für Vereine und Ligen** (20.10.2026, auf Ansage).
///
/// Je Wettbewerb eine Zeile mit dem Stand; dahinter der ganze Wettbewerb als
/// Schalter und jeder Verein einzeln. Erreichbar über Benachrichtigungen ›
/// Live und über die Glocke im Live-Tab.
class LiveAbosScreen extends ConsumerWidget {
  const LiveAbosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final geladen = ref.watch(liveAbosProvider);
    final stand = _stand(ref);

    return Scaffold(
      appBar: AppBar(title: const Text('Vereine & Ligen')),
      body: stand == null
          ? (geladen.hasError
              ? const Center(child: Text('Abos konnten nicht geladen werden.'))
              : const Skelett())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                Text(
                  'Live-Meldungen auch für Vereine, die keine Favoriten sind '
                  '— oder für eine ganze Liga.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                for (final (i, l) in LiveAbos.wettbewerbe.indexed) ...[
                  if (i > 0) const EinstellungsTrenner(),
                  _WettbewerbZeile(liga: l, stand: stand),
                ],
              ],
            ),
    );
  }
}

class _WettbewerbZeile extends ConsumerWidget {
  const _WettbewerbZeile({required this.liga, required this.stand});

  final LeagueInfo liga;
  final LiveAbos stand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final teams = ref.watch(leagueTeamsProvider(liga.id)).valueOrNull;
    final ganz = stand.ligen.contains(liga.id);
    final einzeln = teams == null
        ? 0
        : teams.where((t) => stand.vereine.contains(t.id)).length;
    final text = ganz
        ? 'Alle Vereine'
        : einzeln == 0
            ? 'Aus'
            : einzeln == 1
                ? '1 Verein'
                : '$einzeln Vereine';
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => LiveAboLigaScreen(liga: liga))),
      child: EinstellungsZeile(
        vorne: LeagueLogo(
          leagueId: liga.id,
          size: 28,
          fallback: CompetitionEmblem(leagueId: liga.id, size: 28),
        ),
        label: liga.name,
        rechts: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(text,
              style: TextStyle(
                  color: ganz || einzeln > 0
                      ? scheme.onSurface
                      : scheme.onSurfaceVariant)),
          Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
        ]),
      ),
    );
  }
}

/// Ein Wettbewerb: oben der Schalter für alle Vereine, darunter jeder einzeln.
///
/// Favoriten melden ohnehin und stehen deshalb an und gesperrt da; ist die
/// ganze Liga an, gilt das für jeden Verein darin. Ein Verein, der in zwei
/// Wettbewerben spielt (Bundesliga und Pokal), ist **ein** Abo — der Schalter
/// steht in beiden Listen gleich, und die Meldung kommt für alle seine Spiele.
class LiveAboLigaScreen extends ConsumerWidget {
  const LiveAboLigaScreen({super.key, required this.liga});

  final LeagueInfo liga;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final stand = _stand(ref) ?? const LiveAbos();
    final teamsAsync = ref.watch(leagueTeamsProvider(liga.id));
    final favoriten = ref.watch(favoritesProvider);
    final ganz = stand.ligen.contains(liga.id);

    return Scaffold(
      appBar: AppBar(title: Text(liga.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          EinstellungsSchalter(
            label: 'Alle Vereine',
            unter: 'Jedes Spiel im Wettbewerb',
            wert: ganz,
            onChanged: (v) => _setzen(context, ref, liga: liga.id, an: v),
          ),
          const Kapitelmarke('Vereine'),
          ...teamsAsync.when(
            loading: () => const [SizedBox(height: 240, child: Skelett())],
            error: (_, _) => [
              Text('Vereine konnten nicht geladen werden.',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            ],
            data: (teams) => teams.isEmpty
                ? [
                    Text('Noch keine Vereine (Spielplan nicht veröffentlicht).',
                        style: TextStyle(color: scheme.onSurfaceVariant)),
                  ]
                : [
                    for (final (i, t) in teams.indexed) ...[
                      if (i > 0) const EinstellungsTrenner(),
                      _VereinZeile(
                        team: t,
                        favorit: isTeamFavorited(favoriten, t.id),
                        ganzeLiga: ganz,
                        abo: stand.vereine.contains(t.id),
                      ),
                    ],
                  ],
          ),
        ],
      ),
    );
  }
}

class _VereinZeile extends ConsumerWidget {
  const _VereinZeile({
    required this.team,
    required this.favorit,
    required this.ganzeLiga,
    required this.abo,
  });

  final TeamRef team;
  final bool favorit;
  final bool ganzeLiga;
  final bool abo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fest = favorit || ganzeLiga;
    return EinstellungsZeile(
      vorne: TeamBadge(team: team, size: 26),
      label: team.name,
      unter: favorit
          ? 'Favorit'
          : ganzeLiga
              ? 'Über die ganze Liga'
              : null,
      // Fest an heißt ein Häkchen, kein gesperrter Schalter: Der las sich in
      // der Vorschau wie „aus".
      rechts: fest
          ? SizedBox(
              width: 60,
              child: Icon(Icons.check,
                  semanticLabel: 'Meldet immer',
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            )
          : Switch(
              value: abo,
              onChanged: (v) =>
                  _setzen(context, ref, verein: team.id, an: v),
            ),
    );
  }
}
