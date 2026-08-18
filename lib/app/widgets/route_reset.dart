import 'package:flutter/material.dart';

/// Räumt beim Wechsel von [wert] alles ab, was über der ersten Route liegt.
///
/// Hintergrund: Das Gate in `main.dart` tauscht nur den **Inhalt der ersten
/// Route** (Login ⇄ App-Shell). Alles, was per `Navigator.push` darüber liegt
/// — Profil, Liga-Screens, ein zweiter Login —, bleibt beim Kontowechsel
/// stehen und verdeckt das Gate. Genau so entstand „nach dem Abmelden und
/// neu Anmelden komme ich nur durch Beenden der App auf den Homescreen":
/// abgemeldet wurde im Profil, das über dem Gate lag, und dessen
/// „Anmelden"-Knopf legte noch einen Login obendrauf.
///
/// Deshalb hängt der Reset am Gate und nicht an den einzelnen Aufrufern:
/// wer abmeldet, ist egal — sobald sich das Konto ändert, gilt wieder, was
/// das Gate zeigt.
class RouteReset<T> extends StatefulWidget {
  const RouteReset({super.key, required this.wert, required this.child});

  /// Identität des Kontos (User-ID); `null` = abgemeldet.
  final T wert;

  final Widget child;

  @override
  State<RouteReset<T>> createState() => _RouteResetState<T>();
}

class _RouteResetState<T> extends State<RouteReset<T>> {
  @override
  void didUpdateWidget(RouteReset<T> old) {
    super.didUpdateWidget(old);
    if (old.wert == widget.wert) return;
    // Nach dem Frame: währenddessen baut der Navigator gerade selbst.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final nav = Navigator.maybeOf(context);
      if (nav == null || !nav.canPop()) return;
      nav.popUntil((r) => r.isFirst);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
