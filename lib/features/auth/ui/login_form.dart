import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth_repository.dart';
import '../providers.dart';

/// Login/Registrierung — eingebettet im Runden-Tab, solange niemand
/// angemeldet ist.
class LoginForm extends ConsumerStatefulWidget {
  const LoginForm({super.key});

  @override
  ConsumerState<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends ConsumerState<LoginForm> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _username = TextEditingController();
  bool _registerMode = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _username.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = ref.read(authRepositoryProvider);
    try {
      if (_registerMode) {
        await auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
          username: _username.text,
        );
      } else {
        await auth.signIn(email: _email.text.trim(), password: _password.text);
      }
      // Erfolg: currentUserProvider rebuildet, der Runden-Tab zeigt
      // automatisch die Rundenliste.
    } on AuthFailure catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Unerwarteter Fehler: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.groups,
                  size: 56, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              Text(
                _registerMode ? 'Konto erstellen' : 'Anmelden',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Tipprunden mit Freunden: erstellen, beitreten, gegeneinander tippen.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              if (_registerMode) ...[
                TextField(
                  controller: _username,
                  decoration: const InputDecoration(
                    labelText: 'Nutzername',
                    contentPadding: EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'E-Mail',
                  contentPadding: EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Passwort',
                  contentPadding: EdgeInsets.symmetric(horizontal: 12),
                ),
                onSubmitted: (_) => _busy ? null : _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_registerMode ? 'Registrieren' : 'Anmelden'),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _registerMode = !_registerMode;
                          _error = null;
                        }),
                child: Text(_registerMode
                    ? 'Schon ein Konto? Anmelden'
                    : 'Neu hier? Konto erstellen'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
