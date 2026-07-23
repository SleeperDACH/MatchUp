import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import 'login_form.dart';

/// Bildschirmfüllender Login/Registrierung im MatchUp-Markenlook: dunkler
/// Grund mit grünem Schimmer, großes Logo, Formular in einer Glaskarte.
/// Wird vom Auth-Gate (main.dart) als Wurzel angezeigt, solange niemand
/// angemeldet ist; nach erfolgreicher Anmeldung wechselt das Gate selbst auf
/// die App-Shell.
///
/// Kein eigenes Auto-Schließen: Das würde sonst einen darüber gepushten Screen
/// (z. B. „Neues Passwort" beim Recovery-Link) wegpoppen, sobald die
/// Recovery-Session den Nutzer anmeldet.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Bewusst markenfest dunkel (auch im Light-Theme): der Anmeldescreen ist
    // der erste Marken-Eindruck.
    return Scaffold(
      backgroundColor: MatchUpColors.base,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF16241B), // grüner Schimmer oben
              MatchUpColors.base,
              MatchUpColors.base,
            ],
            stops: [0.0, 0.45, 1.0],
          ),
        ),
        child: const SafeArea(child: LoginForm()),
      ),
    );
  }
}
