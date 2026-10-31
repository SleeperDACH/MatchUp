import 'package:flutter/material.dart';

import '../../../app/live_screen.dart';

/// **Erst mal reinschauen** (29.10.2026, Punkt 6 der Nutzer-Analyse: „bevor
/// man ein Konto hat, sieht man nichts von der App").
///
/// Der Live-Tab, wie er in der App steht — Spiele, Stände, Wettbewerbe,
/// Vereinsseiten. Er braucht kein Konto: Die Edge Function `sportmonks` nimmt
/// den Publishable-Key, und was ein Konto bräuchte, fällt weg (die Glocke für
/// Live-Meldungen) oder tut ohne Nutzer nichts (Favoriten-Stern).
///
/// Unten steht dauerhaft „Konto erstellen"; der Rückgabewert `true` schaltet
/// den Anmeldeschirm auf Registrieren.
class LiveVorschauScreen extends StatelessWidget {
  const LiveVorschauScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Vorschau'), centerTitle: true),
      body: const LiveScreen(vorschau: true),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              child: const Text('Konto erstellen'),
            ),
          ),
        ),
      ),
    );
  }
}
