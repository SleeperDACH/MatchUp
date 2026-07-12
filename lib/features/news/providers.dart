import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import 'models/news_item.dart';

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
