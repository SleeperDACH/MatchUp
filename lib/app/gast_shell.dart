import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'live_screen.dart';
import 'typografie.dart';
import 'widgets/matchup_chevron.dart';
import 'widgets/navi_kapsel.dart';

/// Ob jemand ohne Konto „erst mal reinschaut". Das Gate in `main.dart`
/// zeigt dann [GastShell] statt des Anmeldeschirms; mit der Anmeldung fällt
/// es von selbst zurück.
final gastModusProvider = StateProvider<bool>((ref) => false);

/// **Die App ohne Konto** (31.10.2026, auf Ansage: „den Bereich so gestalten,
/// dass man auf den Live-Tab komplett problemlos zugreifen kann … wenn man auf
/// Home und Favoriten geht, steht dort ‚Anmelden'").
///
/// Dieselbe Hülle wie angemeldet — Navileiste unten, Live in der Mitte — nur
/// dass Home und Favoriten ohne Konto nichts zu zeigen haben und das sagen.
/// Live ist der volle Tab (Spiele, Wettbewerbe, Vereinsseiten, Spieldetails);
/// nur die Glocke fehlt, Live-Meldungen brauchen ein Konto. Die Daten kommen
/// ohne Sitzung: Die Function `sportmonks` nimmt den Publishable-Key.
class GastShell extends ConsumerStatefulWidget {
  const GastShell({super.key});

  @override
  ConsumerState<GastShell> createState() => _GastShellState();
}

class _GastShellState extends ConsumerState<GastShell> {
  /// Start auf Live — deshalb ist man hier.
  int _index = 1;

  static const _tabs = [
    _AnmeldenHinweis(
      titel: 'Deine Ligen',
      text:
          'Ligen, Tippspiele und das nächste Spiel deines Vereins siehst '
          'du, sobald du angemeldet bist.',
    ),
    LiveScreen(gast: true),
    _AnmeldenHinweis(
      titel: 'Deine Favoriten',
      text:
          'Lieblingsvereine merken, ihre Spiele und News an einem Ort — '
          'dafür brauchst du ein Konto.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: NaviKapsel(
        index: _index,
        onSelected: (i) => setState(() => _index = i),
      ),
    );
  }
}

/// Home und Favoriten ohne Konto: ein Satz, wofür man sich anmeldet, und der
/// Knopf dorthin.
class _AnmeldenHinweis extends ConsumerWidget {
  const _AnmeldenHinweis({required this.titel, required this.text});

  final String titel;
  final String text;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, navBarHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const MatchUpChevron(size: 44),
              const SizedBox(height: 20),
              Text(
                titel.toUpperCase(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: Schrift.gross,
                  fontWeight: Schrift.ueberschriftGewicht,
                  fontStyle: Schrift.ueberschriftStil,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: Schrift.text,
                  height: 1.4,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () =>
                    ref.read(gastModusProvider.notifier).state = false,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
                child: const Text('Anmelden'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
