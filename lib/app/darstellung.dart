import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'farben.dart';
import 'typografie.dart';

/// Dunkel oder hell. **Dunkel ist der Standard** — die App ist als dunkle
/// gestaltet, der helle Modus ist eine Wahl in den Einstellungen.
enum Darstellung {
  dunkel('Dunkel', ThemeMode.dark),
  hell('Hell', ThemeMode.light);

  const Darstellung(this.wort, this.modus);
  final String wort;
  final ThemeMode modus;
}

const _schluessel = 'darstellung';

/// Liest die gespeicherte Wahl. Wird in `main()` **vor** `runApp` gefragt,
/// damit die App gleich im richtigen Modus aufbaut — sonst sähe man im hellen
/// Modus beim Start erst einen Augenblick lang Schwarz.
Future<Darstellung> ladeDarstellung() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final wert = prefs.getString(_schluessel);
    return Darstellung.values.firstWhere(
      (d) => d.name == wert,
      orElse: () => Darstellung.dunkel,
    );
  } catch (_) {
    return Darstellung.dunkel;
  }
}

class DarstellungNotifier extends StateNotifier<Darstellung> {
  DarstellungNotifier(super.start);

  Future<void> setze(Darstellung d) async {
    state = d;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_schluessel, d.name);
    } catch (_) {
      // Nicht gespeichert heißt: gilt bis zum nächsten Start. Kein Grund,
      // die Umschaltung selbst scheitern zu lassen.
    }
  }
}

/// Die gewählte Darstellung. Ohne Override (Tests) dunkel.
final darstellungProvider =
    StateNotifierProvider<DarstellungNotifier, Darstellung>(
  (ref) => DarstellungNotifier(Darstellung.dunkel),
);

/// Einstellungsseite: zwei Zeilen, die gewählte trägt ein Häkchen. Die
/// Umschaltung wirkt sofort — man sieht auf der Seite selbst, was man wählt.
class DarstellungScreen extends ConsumerWidget {
  const DarstellungScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gewaehlt = ref.watch(darstellungProvider);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Darstellung')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: Abstand.s),
        children: [
          for (final d in Darstellung.values)
            ListTile(
              leading: Icon(
                d == Darstellung.dunkel
                    ? Icons.dark_mode_outlined
                    : Icons.light_mode_outlined,
                color: scheme.onSurfaceVariant,
              ),
              title: Text(
                d.wort,
                style: const TextStyle(
                  fontSize: Schrift.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: d == Darstellung.dunkel
                  ? Text(
                      'Standard',
                      style: TextStyle(
                        fontSize: Schrift.label,
                        color: scheme.onSurfaceVariant,
                      ),
                    )
                  : null,
              trailing: d == gewaehlt
                  ? Icon(Icons.check, color: context.farben.gruen)
                  : null,
              selected: d == gewaehlt,
              onTap: () => ref.read(darstellungProvider.notifier).setze(d),
            ),
        ],
      ),
    );
  }
}
