import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import 'models/news_item.dart';
import 'models/transfer_deal.dart';

/// Bundesliga-News je Thema (`transfers` oder `injuries`) über die Edge
/// Function `news` (RSS-Proxy + Cache). Leer ohne Server-Verbindung.
final newsProvider =
    FutureProvider.family<List<NewsItem>, String>((ref, topic) async {
  if (!AppConfig.isSupabaseConfigured) return const [];
  final res = await Supabase.instance.client.functions
      .invoke('news', body: {'topic': topic});
  final data = res.data;
  if (data is List) {
    final list = data
        .whereType<Map<String, dynamic>>()
        .map(NewsItem.fromJson)
        .where((n) => n.title.isNotEmpty && n.url.isNotEmpty)
        .toList();
    // Neueste zuerst; Einträge ohne Datum ans Ende.
    list.sort((a, b) {
      final ad = a.publishedAt, bd = b.publishedAt;
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return bd.compareTo(ad);
    });
    return list;
  }
  return const [];
});

/// Liga-spezifische News (kicker-RSS je Liga, Frauen-BL per Google-News-
/// Fallback) über die Edge Function `news`. Family-Key ist die App-Liga-ID.
final leagueNewsProvider =
    FutureProvider.family<List<NewsItem>, String>((ref, leagueId) async {
  if (!AppConfig.isSupabaseConfigured) return const [];
  final res = await Supabase.instance.client.functions
      .invoke('news', body: {'league': leagueId});
  final data = res.data;
  if (data is! List) return const [];
  final list = data
      .whereType<Map<String, dynamic>>()
      .map(NewsItem.fromJson)
      .where((n) => n.title.isNotEmpty && n.url.isNotEmpty)
      .toList();
  list.sort((a, b) {
    final ad = a.publishedAt, bd = b.publishedAt;
    if (ad == null && bd == null) return 0;
    if (ad == null) return 1;
    if (bd == null) return -1;
    return bd.compareTo(ad);
  });
  return list;
});

/// Team-spezifische News (kicker-Team-Feed je Sportmonks-Team-ID; ohne
/// eigenen Feed nach Team-Namen gefilterter Liga-Feed). [teamId] ist die reine
/// Sportmonks-ID, [name] der Anzeigename, [leagueId] die App-Liga (für Fallback).
final teamNewsProvider = FutureProvider.family<List<NewsItem>,
    ({String teamId, String name, String? leagueId})>((ref, args) async {
  if (!AppConfig.isSupabaseConfigured) return const [];
  final res = await Supabase.instance.client.functions.invoke('news', body: {
    'teamId': args.teamId,
    'team': args.name,
    if (args.leagueId != null) 'league': args.leagueId,
  });
  final data = res.data;
  if (data is! List) return const [];
  final list = data
      .whereType<Map<String, dynamic>>()
      .map(NewsItem.fromJson)
      .where((n) => n.title.isNotEmpty && n.url.isNotEmpty)
      .toList();
  list.sort((a, b) {
    final ad = a.publishedAt, bd = b.publishedAt;
    if (ad == null && bd == null) return 0;
    if (ad == null) return 1;
    if (bd == null) return -1;
    return bd.compareTo(ad);
  });
  return list;
});

/// Strukturierte Bundesliga-Transfers (Done Deals) über die Edge Function
/// `transfers` (Sportmonks). Leer ohne Server-Verbindung.
final doneDealsProvider = FutureProvider<List<TransferDeal>>((ref) async {
  if (!AppConfig.isSupabaseConfigured) return const [];
  final res =
      await Supabase.instance.client.functions.invoke('transfers', body: {});
  final data = res.data;
  if (data is List) {
    return data
        .whereType<Map<String, dynamic>>()
        .map(TransferDeal.fromJson)
        .toList();
  }
  return const [];
});
