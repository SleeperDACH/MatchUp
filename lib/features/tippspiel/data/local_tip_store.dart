import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/tip.dart';
import 'tip_store.dart';

/// Lokale Tipp-Ablage (SharedPreferences) — der Modus ohne Konto bzw.
/// ohne ausgewählte Tipprunde. Tipps bleiben nur auf diesem Gerät.
class LocalTipStore implements TipStore {
  LocalTipStore(this.leagueId, this.season);

  final String leagueId;
  final int season;

  String get _key => 'tips.$leagueId.$season';

  @override
  Future<Map<String, Tip>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((fixtureId, json) =>
        MapEntry(fixtureId, Tip.fromJson(json as Map<String, dynamic>)));
  }

  @override
  Future<void> save(Tip tip) async {
    final tips = await load();
    tips[tip.fixtureId] = tip;
    await _write(tips);
  }

  @override
  Future<void> remove(String fixtureId) async {
    final tips = await load();
    tips.remove(fixtureId);
    await _write(tips);
  }

  Future<void> _write(Map<String, Tip> tips) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(tips.map((id, tip) => MapEntry(id, tip.toJson()))));
  }
}
