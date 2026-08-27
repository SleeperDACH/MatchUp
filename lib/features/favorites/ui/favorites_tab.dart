import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/widgets/team_fixture_list.dart';
import '../../../core/models/models.dart';
import '../../../core/models/team_fixture.dart';
import '../../news/models/news_item.dart';
import '../../news/providers.dart';
import '../../news/ui/news_tile.dart';
import '../../tippspiel/ui/team_badge.dart';
import '../../tippspiel/providers.dart';
import '../../../app/widgets/leise_reiter.dart';
import '../favorites.dart';
import '../logic/favorite_order.dart';
import 'favorites_manage_screen.dart';

/// Reine Sportmonks-Team-ID aus dem Favoriten-Key (`sportmonks:503` → `503`).
/// Favoriten-Tab: Auswahl der favorisierten Teams oben, darunter je Team der
/// wettbewerbsübergreifende Spielplan und ein teamspezifischer News-Feed.
/// Teams favorisiert man über den Button oben rechts.
class FavoritesTab extends ConsumerStatefulWidget {
  const FavoritesTab({super.key});

  @override
  ConsumerState<FavoritesTab> createState() => _FavoritesTabState();
}

class _FavoritesTabState extends ConsumerState<FavoritesTab> {
  int _selected = 0;

  void _openManage() => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const FavoritesManageScreen()));

  void _openReorder() => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const FavoritesReorderScreen()));

  @override
  Widget build(BuildContext context) {
    // Nur Teams aus den aktuellen Ligen; veraltete Favoriten (z. B. WM-2026-
    // Nationalmannschaften) werden ausgeblendet.
    final favTeams = ref
        .watch(favoritesProvider)
        .where((f) =>
            f.type == FavoriteType.team &&
            ligaRang(f.leagueId) < 4 &&
            isResolvableTeamFavorite(f))
        .toList();
    // Männer- und Frauen-Team desselben Vereins teilen sich einen Tab.
    final groups = groupFavorites(favTeams);

    // Kein AppBar-Titel: „Favoriten" war die größte Schrift des Schirms für
    // eine Auskunft, die die Navileiste gibt — dieselbe Sache wie „Live" und
    // „Hallo, SFV03". Den Kopf bildet jetzt die Wappenreihe selbst; die beiden
    // Aktionen sitzen an ihrem Ende.
    return Scaffold(
      body: groups.isEmpty
          ? const _LeerHinweis(
              icon: Icons.star_border,
              titel: 'Keine Favoriten ausgewählt',
              text: _keineFavoriten,
              betont: true,
            )
          : SafeArea(
              bottom: false,
              child: _Body(
                groups: groups,
                selected: _selected.clamp(0, groups.length - 1),
                onSelect: (i) => setState(() => _selected = i),
                onManage: _openManage,
                onReorder: groups.length > 1 ? _openReorder : null,
              ),
            ),
    );
  }
}

/// Manuelles Sortieren der Favoriten-Reihenfolge (Chips oben) per Ziehen.
/// Liest die Gruppen direkt aus dem Provider (der die Reihenfolge bereits
/// gemäß sort_order liefert); Ziehen speichert die neue Reihenfolge.
class FavoritesReorderScreen extends ConsumerWidget {
  const FavoritesReorderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final favs = ref
        .watch(favoritesProvider)
        .where((f) =>
            f.type == FavoriteType.team &&
            ligaRang(f.leagueId) < 4 &&
            isResolvableTeamFavorite(f))
        .toList();
    final groups = groupFavorites(favs);
    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('Reihenfolge')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Ziehe die Teams in deine Wunschreihenfolge — so erscheinen sie '
              'oben im Favoriten-Tab.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 32),
              itemCount: groups.length,
              // newIndex ist bereits um das entfernte Element korrigiert.
              onReorderItem: (oldIndex, newIndex) {
                final reordered = [...groups];
                final g = reordered.removeAt(oldIndex);
                reordered.insert(newIndex, g);
                final flat = [for (final g in reordered) ...g.members];
                ref.read(favoritesProvider.notifier).setManualOrder(flat);
              },
              itemBuilder: (context, i) {
                final g = groups[i];
                return Card(
                  key: ValueKey(g.key),
                  child: ListTile(
                    leading: TeamBadge(
                      team: TeamRef(
                        id: g.key,
                        name: g.label,
                        shortName: g.shortName ?? g.label,
                        iconUrl: g.iconUrl,
                      ),
                      size: 34,
                    ),
                    title: Text(g.label,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: ReorderableDragStartListener(
                      index: i,
                      child: Icon(Icons.drag_handle,
                          color: scheme.onSurfaceVariant),
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
}

/// Satz für den Fall, dass **gar kein** Favorit gewählt ist. Bewusst nur
/// dort: steht oben das Wappen eines Vereins, wäre „keine Favoriten
/// ausgewählt" sichtbar falsch — dann nennt der Leerzustand den Verein.
const _keineFavoriten = 'Du hast aktuell keine Favoriten ausgewählt. Füge '
    'Vereine hinzu — dann stehen hier ihre Spiele und ihre News.';

/// Leerzustand mit Weg heraus: Symbol, ein Satz und ein Knopf, der zur
/// Favoritenauswahl führt — bei einem Ladefehler zusätzlich „Erneut laden".
///
/// Steht an **vier** Stellen: kein Favorit gewählt, kein Spielplan, keine
/// News, Laden fehlgeschlagen. Vorher war nur der erste Fall bedacht; in den
/// Tabs stand ein nackter Satz bzw. allein „Erneut laden" — wer dort landete,
/// kam nicht auf den Gedanken, dass ein weiterer Favorit hilft.
class _LeerHinweis extends StatelessWidget {
  const _LeerHinweis({
    required this.icon,
    required this.titel,
    required this.text,
    this.betont = false,
    this.onRetry,
  });

  final IconData icon;
  final String titel;
  final String text;

  /// Als Hauptknopf (gefüllt) statt als Nebenweg (umrandet).
  final bool betont;

  /// Nur beim Ladefehler: Wiederholen steht dann vorn.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    void oeffneAuswahl() => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const FavoritesManageScreen()));

    final zurAuswahl = OutlinedButton.icon(
      onPressed: oeffneAuswahl,
      icon: const Icon(Icons.star_border, size: 18),
      label: const Text('Favoriten hinzufügen'),
    );

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: scheme.onSurfaceVariant),
            const SizedBox(height: 14),
            Text(titel,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.35),
            ),
            const SizedBox(height: 20),
            if (onRetry != null) ...[
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Erneut laden'),
              ),
              const SizedBox(height: 10),
              zurAuswahl,
            ] else if (betont)
              FilledButton.icon(
                onPressed: oeffneAuswahl,
                icon: const Icon(Icons.add),
                label: const Text('Favoriten hinzufügen'),
              )
            else
              zurAuswahl,
          ],
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.groups,
    required this.selected,
    required this.onSelect,
    required this.onManage,
    this.onReorder,
  });

  final List<FavGroup> groups;
  final int selected;
  final ValueChanged<int> onSelect;
  final VoidCallback onManage;

  /// Reihenfolge ändern — erst ab zwei Favoriten sinnvoll, sonst `null`.
  final VoidCallback? onReorder;

  @override
  Widget build(BuildContext context) {
    final group = groups[selected];
    return Column(
      // `stretch`: Sonst schrumpft der Vereinskopf auf seine Textbreite und
      // die äußere Column zentriert ihn — der Name stünde mittig statt links
      // an derselben Kante wie alles darunter.
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WappenReihe(
          groups: groups,
          selected: selected,
          onSelect: onSelect,
          onManage: onManage,
          onReorder: onReorder,
        ),
        _VereinsKopf(group: group),
        Expanded(
          child: DefaultTabController(
            // Key: bei Gruppen-Wechsel neu aufbauen (Tab-Zustand + Provider).
            key: ValueKey(group.key),
            length: 2,
            child: Column(
              children: [
                const LeiseReiter(titel: ['Spielplan', 'News']),
                Expanded(
                  child: TabBarView(
                    children: [
                      _FixturesTab(teamIds: group.teamIds, name: group.label),
                      _NewsTab(args: group.newsArgs, name: group.label),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Die Wappen der Favoriten als Kopf des Schirms — **ohne Beschriftung**.
///
/// Vorher war das der Kleinkram des Schirms: 32-Punkte-Wappen mit
/// 9,5-Punkte-Text darunter, bei dem „Borussia Dortmund" zweizeilig umbrach.
/// Ausgerechnet die wichtigste Auswahl hier war das Kleinste darauf. Jetzt
/// trägt das Wappen allein — es ist das, woran man einen Verein erkennt, und
/// wie der Gewählte heißt, steht direkt darunter als Überschrift. Der Gewählte
/// ist größer und voll deckend, die übrigen kleiner und zurückgenommen.
class _WappenReihe extends StatelessWidget {
  const _WappenReihe({
    required this.groups,
    required this.selected,
    required this.onSelect,
    required this.onManage,
    this.onReorder,
  });

  final List<FavGroup> groups;
  final int selected;
  final ValueChanged<int> onSelect;
  final VoidCallback onManage;
  final VoidCallback? onReorder;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 74,
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
              itemCount: groups.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final g = groups[i];
                final sel = i == selected;
                final groesse = sel ? 52.0 : 40.0;
                return Semantics(
                  button: true,
                  selected: sel,
                  label: g.label,
                  excludeSemantics: true,
                  child: GestureDetector(
                    onTap: () => onSelect(i),
                    behavior: HitTestBehavior.opaque,
                    child: Center(
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 160),
                        // Nicht Gewählte treten zurück, statt zu verschwinden:
                        // Man soll sehen, dass es sie gibt.
                        opacity: sel ? 1 : 0.55,
                        child: TeamBadge(
                          team: TeamRef(
                            id: g.key,
                            name: g.label,
                            shortName: g.shortName ?? g.label,
                            iconUrl: g.iconUrl,
                          ),
                          size: groesse,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (onReorder != null)
            _RundKnopf(
              icon: Icons.swap_vert,
              tooltip: 'Reihenfolge sortieren',
              onTap: onReorder!,
            ),
          const SizedBox(width: 8),
          _RundKnopf(
            icon: Icons.add,
            tooltip: 'Teams favorisieren',
            onTap: onManage,
            farbe: scheme.onSurface,
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}

/// Runder Knopf am Ende der Wappenreihe — gestrichelt, damit er als Platz für
/// etwas Neues liest und nicht als weiterer Verein.
class _RundKnopf extends StatelessWidget {
  const _RundKnopf({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.farbe,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? farbe;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ton = farbe ?? scheme.onSurfaceVariant;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: scheme.onSurface.withValues(alpha: 0.18),
                width: 0.8,
              ),
            ),
            child: Icon(icon, size: 19, color: ton),
          ),
        ),
      ),
    );
  }
}

/// Name des gewählten Vereins als Überschrift, darunter Wettbewerb und — wenn
/// die Tabelle geladen ist — der Tabellenplatz.
///
/// Der Platz kommt über die **Team-ID** aus der Tabelle, nicht über den Namen:
/// „1. FC Köln" und „FC Köln" stehen in denselben Daten nebeneinander, ein
/// Namensvergleich träfe mal und mal nicht. Lädt die Tabelle noch oder gibt es
/// sie nicht (Pokal, Saisonstart), bleibt es beim Wettbewerb allein — eine
/// Zeile, die auf Daten wartet, soll nicht wackeln.
class _VereinsKopf extends ConsumerWidget {
  const _VereinsKopf({required this.group});

  final FavGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final ligaId = group.members.first.leagueId;
    final liga = ligaId == null ? null : Leagues.byId(ligaId);

    int? platz;
    if (liga != null) {
      final tabelle = ref.watch(leagueTableProvider(liga.id)).valueOrNull;
      if (tabelle != null) {
        final meine = group.teamIds.toSet();
        platz = tabelle
            .where((r) => meine.contains(teamIdOf(r.team.id)))
            .map((r) => r.rank)
            .firstOrNull;
      }
    }

    final unterzeile = [
      if (liga != null) liga.name,
      if (platz != null) 'Platz $platz',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            group.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          if (unterzeile.isNotEmpty)
            Text(
              unterzeile,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Spielplan (wettbewerbsübergreifend)
// ---------------------------------------------------------------------
class _FixturesTab extends ConsumerWidget {
  const _FixturesTab({required this.teamIds, required this.name});
  final List<String> teamIds;

  /// Anzeigename des gewählten Favoriten — der Leerzustand nennt ihn.
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncs = [for (final id in teamIds) ref.watch(teamFixturesProvider(id))];
    final anyLoading = asyncs.any((a) => a.isLoading);
    // Spielpläne aller Team-Teile (z. B. Männer + Frauen) zusammenführen.
    final seen = <String>{};
    final fixtures = <TeamFixture>[
      for (final a in asyncs)
        for (final f in (a.valueOrNull ?? const <TeamFixture>[]))
          if (seen.add(f.id)) f
    ];

    if (fixtures.isEmpty) {
      if (anyLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      if (asyncs.every((a) => a.hasError)) {
        return _LeerHinweis(
          icon: Icons.cloud_off,
          titel: 'Spielplan nicht geladen',
          text: 'Die Spiele deiner Favoriten konnten nicht abgerufen werden.',
          onRetry: () {
            for (final id in teamIds) {
              ref.invalidate(teamFixturesProvider(id));
            }
          },
        );
      }
      return _LeerHinweis(
        icon: Icons.event_busy,
        titel: 'Keine Spiele',
        text: 'Für $name ist gerade kein Spielplan hinterlegt.',
      );
    }

    final upcoming = [
      for (final f in fixtures)
        if (f.status != FixtureStatus.finished) f
    ]..sort((a, b) => a.kickoff.compareTo(b.kickoff));
    final results = [
      for (final f in fixtures)
        if (f.status == FixtureStatus.finished) f
    ]..sort((a, b) => b.kickoff.compareTo(a.kickoff));
    return RefreshIndicator(
      onRefresh: () async {
        for (final id in teamIds) {
          ref.invalidate(teamFixturesProvider(id));
        }
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (upcoming.isNotEmpty) ...[
            const FixtureSectionLabel('Nächste Spiele'),
            ...fixturesWithDateHeaders(upcoming),
          ],
          if (results.isNotEmpty) ...[
            const FixtureSectionLabel('Ergebnisse'),
            ...fixturesWithDateHeaders(results),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Team-News
// ---------------------------------------------------------------------
class _NewsTab extends ConsumerWidget {
  const _NewsTab({required this.args, required this.name});
  final List<({String teamId, String name, String? leagueId})> args;

  /// Anzeigename des gewählten Favoriten — der Leerzustand nennt ihn.
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncs = [for (final a in args) ref.watch(teamNewsProvider(a))];
    final anyLoading = asyncs.any((a) => a.isLoading);
    // News aller Team-Teile zusammenführen, nach URL entdoppeln, neueste zuerst.
    final seen = <String>{};
    final items = <NewsItem>[
      for (final a in asyncs)
        for (final n in (a.valueOrNull ?? const <NewsItem>[]))
          if (seen.add(n.url)) n
    ]..sort((x, y) {
        final xd = x.publishedAt, yd = y.publishedAt;
        if (xd == null && yd == null) return 0;
        if (xd == null) return 1;
        if (yd == null) return -1;
        return yd.compareTo(xd);
      });

    if (items.isEmpty) {
      if (anyLoading) return const Center(child: CircularProgressIndicator());
      if (asyncs.every((a) => a.hasError)) {
        return _LeerHinweis(
          icon: Icons.cloud_off,
          titel: 'News nicht geladen',
          text: 'Die Meldungen zu deinen Favoriten konnten nicht abgerufen '
              'werden.',
          onRetry: () {
            for (final a in args) {
              ref.invalidate(teamNewsProvider(a));
            }
          },
        );
      }
      return _LeerHinweis(
        icon: Icons.newspaper,
        titel: 'Keine News',
        text: 'Zu $name gibt es gerade nichts zu lesen.',
      );
    }
    return RefreshIndicator(
      onRefresh: () async {
        for (final a in args) {
          ref.invalidate(teamNewsProvider(a));
        }
      },
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 96),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) => NewsTile(item: items[i]),
      ),
    );
  }
}
