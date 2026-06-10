import '../models/fantasy_models.dart';

/// 1-basierte Draft-Position, die beim Stand [picksMade] (0-basiert) am
/// Zug ist — Snake-Reihenfolge bei [managerCount] Managern. Muss exakt
/// der Server-Logik (fantasy_current_manager) entsprechen.
int snakeSlot(int picksMade, int managerCount) {
  if (managerCount <= 0) return 1;
  final round0 = picksMade ~/ managerCount;
  final pos = picksMade % managerCount;
  return round0.isEven ? pos + 1 : managerCount - pos;
}

/// Der Manager, der gerade am Zug ist (oder null, wenn unbestimmt).
FantasyManager? currentManager(List<FantasyManager> managers, int picksMade) {
  if (managers.isEmpty) return null;
  final slot = snakeSlot(picksMade, managers.length);
  for (final m in managers) {
    if (m.draftPosition == slot) return m;
  }
  return null;
}

/// Gesamtzahl der Picks eines abgeschlossenen Drafts.
int totalPicks(int managerCount, RosterConfig roster) =>
    managerCount * roster.squadSize;
