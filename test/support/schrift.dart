import 'dart:io';

import 'package:flutter/services.dart';

/// Lädt die App-Schrift in eine Golden-Vorschau.
///
/// Ohne das zeichnet `flutter test` jeden Text als graue Kästchen — für
/// Abstände reicht das, für Schriftgrößen und Hierarchie nicht.
///
/// Gehört in `setUpAll`, **nicht** in den Test: `testWidgets` läuft in einer
/// Fake-Async-Zone, in der echtes Datei-I/O nie zurückkommt. Der Aufruf hängt
/// dort bis zum Timeout, statt mit einer Meldung zu scheitern.
Future<void> ladeSchrift() async {
  final loader = FontLoader('BarlowCondensed');
  const dateien = [
    'assets/fonts/BarlowCondensed-Regular.ttf',
    'assets/fonts/BarlowCondensed-Medium.ttf',
    'assets/fonts/BarlowCondensed-SemiBold.ttf',
    'assets/fonts/BarlowCondensed-Bold.ttf',
  ];
  for (final d in dateien) {
    loader.addFont(File(d).readAsBytes().then((b) => ByteData.view(b.buffer)));
  }
  await loader.load();
}
