import '../favorites.dart';

/// Die Reihenfolge, in der der Nutzer seine Favoriten sieht — **eine** Regel
/// für alle, die sie brauchen.
///
/// Sie stand als privater Block im Favoriten-Tab, bis der Homescreen dieselbe
/// Frage stellte: Welches Spiel gehört auf die Kopfkarte, wenn an einem
/// Samstag vier Favoriten spielen? Die Antwort ist „das des obersten
/// Favoriten", und dafür muss „oben" an beiden Stellen dasselbe heißen. Zwei
/// Sortierungen, die beide behaupten, die Favoritenreihenfolge zu sein, wären
/// genau die Sorte Widerspruch, die man erst bemerkt, wenn sie auseinander
/// laufen.

/// Sortierreihenfolge der Ligen: 1. Bundesliga … 3. Liga, Frauen zuletzt.
int ligaRang(String? id) => switch (id) {
  'bundesliga' => 0,
  'bundesliga2' => 1,
  'liga3' => 2,
  'frauen_bundesliga' => 3,
  _ => 4,
};

/// Basisname eines Teams ohne Frauen-Suffix („Hamburger SV W" → „Hamburger SV").
String clubBase(String label) {
  final m = RegExp(
    r'^(.*?)\s+(W|Women|Frauen)$',
    caseSensitive: false,
  ).firstMatch(label.trim());
  return (m != null ? m.group(1)! : label).trim();
}

/// Fasst Favoriten desselben Vereins zu einem gemeinsamen Tab zusammen — etwa
/// Männer- und Frauen-Team (Spielplan und News laufen dann zusammen).
class FavGroup {
  FavGroup(this.base);
  final String base;
  final List<Favorite> members = [];

  /// Anzeigename: bei einem einzelnen Team dessen voller Name, sonst der Basis-
  /// Vereinsname (ohne „W").
  String get label => members.length == 1 ? members.first.label : base;
  String? get iconUrl => members
      .firstWhere((f) => f.iconUrl != null, orElse: () => members.first)
      .iconUrl;
  String? get shortName => members.first.shortName;
  String get key => members.map((f) => f.key).join('+');

  /// Beste (niedrigste) Liga-Reihenfolge über alle Team-Teile — für die
  /// Sortierung der Auswahl (Männer-Team bestimmt die Einordnung).
  int get leagueOrder =>
      members.map((f) => ligaRang(f.leagueId)).fold(9, (a, b) => a < b ? a : b);

  /// Manuelle Sortierposition (kleinste über die Team-Teile); null = keine.
  int? get manualOrder {
    int? m;
    for (final f in members) {
      final s = f.sortOrder;
      if (s != null && (m == null || s < m)) m = s;
    }
    return m;
  }

  List<String> get teamIds => [for (final f in members) teamIdOf(f.key)];
  List<({String teamId, String name, String? leagueId})> get newsArgs => [
    for (final f in members)
      (teamId: teamIdOf(f.key), name: f.label, leagueId: f.leagueId),
  ];
}

/// Gruppiert die Favoriten nach Basis-Vereinsnamen (Reihenfolge erhalten).
List<FavGroup> groupFavorites(List<Favorite> favs) {
  final groups = <String, FavGroup>{};
  final order = <String>[];
  for (final f in favs) {
    final base = clubBase(f.label).toLowerCase();
    final g = groups.putIfAbsent(base, () {
      order.add(base);
      return FavGroup(clubBase(f.label));
    });
    g.members.add(f);
  }
  // Manuelle Reihenfolge hat Vorrang; sonst nach Liga (1. → 2. → 3. → Frauen).
  // Innerhalb stabil (ursprüngliche Reihenfolge).
  final list = [for (final b in order) groups[b]!];
  final anyManual = list.any((g) => g.manualOrder != null);
  final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
  indexed.sort((a, b) {
    final int c;
    if (anyManual) {
      final ao = a.$2.manualOrder ?? (1 << 30);
      final bo = b.$2.manualOrder ?? (1 << 30);
      c = ao.compareTo(bo);
    } else {
      c = a.$2.leagueOrder.compareTo(b.$2.leagueOrder);
    }
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

/// Rang je Verein für die Zuordnung von Spielen: reine Team-ID
/// ([teamIdOf]) → Position in der Favoritenreihenfolge, 0 ist oben.
///
/// Ein Verein kann mehrere Zeilen haben (Männer und Frauen, alte
/// Schlüssel-Präfixe); alle zeigen auf den Rang **ihrer Gruppe**, damit die
/// Frauenmannschaft nicht hinter den Rest rutscht, nur weil sie in einer
/// später einsortierten Liga spielt.
Map<String, int> favoritenRaenge(List<Favorite> favs) {
  // Dieselbe Vorauswahl wie im Favoriten-Tab. `isResolvableTeamFavorite` ist
  // dabei nicht Kosmetik: Ein Schlüssel aus einer früheren Quelle
  // (`openligadb:100`) wird von [teamIdOf] auf `100` gekürzt — und diese ID
  // gibt es bei Sportmonks auch, nur gehört sie einem **fremden** Verein. Ohne
  // den Filter bekäme der einen Rang und könnte die Kopfkarte an sich reißen.
  final gruppen = groupFavorites([
    for (final f in favs)
      if (f.type == FavoriteType.team &&
          ligaRang(f.leagueId) < 4 &&
          isResolvableTeamFavorite(f))
        f,
  ]);
  return {
    for (var i = 0; i < gruppen.length; i++)
      for (final m in gruppen[i].members) teamIdOf(m.key): i,
  };
}
