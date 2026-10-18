import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/features/fantasy/ui/fantasy_league_screen.dart';

/// Reihenfolge der Liga-Reiter: MatchUp · Kader · Übersicht · Tabelle
/// (auf Ansage, 16.10.2026).
void main() {
  test('die Reiter stehen in der gewünschten Reihenfolge', () {
    expect(
      [LigaReiter.matchup, LigaReiter.kader, LigaReiter.uebersicht,
        LigaReiter.tabelle],
      [0, 1, 2, 3],
    );
  });

  test('nach dem Draft öffnet die Liga auf MatchUp, davor auf der Übersicht',
      () {
    expect(LigaReiter.start(DraftStatus.done), LigaReiter.matchup);
    expect(LigaReiter.start(DraftStatus.drafting), LigaReiter.uebersicht);
    expect(LigaReiter.start(DraftStatus.setup), LigaReiter.uebersicht);
  });
}
