import 'package:flutter/material.dart';

import 'login_form.dart';

/// Bildschirmfüllender Login/Registrierung. Wird vom Auth-Gate (main.dart)
/// als Wurzel angezeigt, solange niemand angemeldet ist; nach erfolgreicher
/// Anmeldung wechselt das Gate selbst auf die App-Shell.
///
/// Kein eigenes Auto-Schließen mehr: Das würde sonst einen darüber
/// gepushten Screen (z. B. „Neues Passwort" beim Recovery-Link) wegpoppen,
/// sobald die Recovery-Session den Nutzer anmeldet.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Anmelden')),
      body: const LoginForm(),
    );
  }
}
