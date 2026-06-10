import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'login_form.dart';

/// Eigener Screen für Login/Registrierung; schließt sich nach
/// erfolgreicher Anmeldung von selbst.
class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(currentUserProvider, (_, user) {
      if (user != null && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
    return Scaffold(
      appBar: AppBar(title: const Text('Anmelden')),
      body: const LoginForm(),
    );
  }
}
