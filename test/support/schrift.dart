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
  await _ladeSymbole();
}

/// Lädt die Material-Symbolschrift dazu.
///
/// Ohne sie zeichnet jedes `Icon` ein leeres Kästchen — in einer Vorschau, die
/// über **Symbol neben Wort** entscheiden soll, wäre das Bild wertlos. Die
/// Datei liegt im Flutter-SDK, nicht im Projekt; findet sie sich nicht, läuft
/// der Test trotzdem weiter (Kästchen statt Symbolen ist besser als ein Test,
/// der auf einer fremden Maschine gar nicht startet).
Future<void> _ladeSymbole() async {
  final sdk = Platform.environment['FLUTTER_ROOT'] ??
      _sdkAusPfad(Platform.resolvedExecutable);
  if (sdk == null) return;
  final datei = File(
      '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (!datei.existsSync()) return;
  final loader = FontLoader('MaterialIcons')
    ..addFont(datei.readAsBytes().then((b) => ByteData.view(b.buffer)));
  await loader.load();
}

/// Der Test läuft im `flutter_tester` aus `.../bin/cache/artifacts/engine/...`
/// — von dort aus liegt das SDK vier Ebenen höher.
String? _sdkAusPfad(String exe) {
  var d = File(exe).parent;
  for (var i = 0; i < 8; i++) {
    if (Directory('${d.path}/bin/cache/artifacts/material_fonts').existsSync()) {
      return d.path;
    }
    if (d.path == d.parent.path) break;
    d = d.parent;
  }
  return null;
}
