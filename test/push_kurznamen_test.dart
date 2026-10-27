import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Die Push-Meldungen (`supabase/functions/sync-live/kurznamen.ts`) und die
/// App (`lib/core/logic/vereins_kuerzel.dart`) benutzen **dieselbe**
/// Kurznamen-Tabelle (27.10.2026). Steht ein Verein nur in einer, heißt er in
/// der Meldung anders als in der App.
Map<String, String> _tabelle(String datei, String anfang) {
  final text = File(datei).readAsStringSync();
  final a = text.indexOf(anfang);
  expect(a, isNonNegative, reason: '$anfang fehlt in $datei');
  final b = text.indexOf('};', a);
  return {
    for (final m in RegExp(r"^\s*'([^']+)':\s*'([^']+)',", multiLine: true)
        .allMatches(text.substring(a, b)))
      m.group(1)!: m.group(2)!,
  };
}

void main() {
  test('App und Push kennen dieselben Kurznamen', () {
    final app = _tabelle(
        'lib/core/logic/vereins_kuerzel.dart', 'const _kurznamen');
    final push = _tabelle(
        'supabase/functions/sync-live/kurznamen.ts', 'export const KURZNAMEN');
    expect(app, isNotEmpty);
    expect(push, app);
  });
}
