import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  // Schnellanmeldung per Face ID / Fingerabdruck (nur nativ).
  bool _bioSupported = false; // Gerät hat Biometrie-Hardware (Setup anbieten)
  bool _hasSavedCreds = false; // Zugangsdaten hinterlegt + nutzbar -> Button
  bool _enableBio = false; // Nutzer will Biometrie beim nächsten Login einrichten
  String _bioLabel = 'Biometrie';

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  /// Zuletzt genutzte E-Mail vorbefüllen und prüfen, ob Biometrie verfügbar
  /// bzw. schon eingerichtet ist.
  Future<void> _loadPrefs() async {
    final bio = ref.read(biometricLoginProvider);
    final email = await bio.lastEmail();
    final supported = await bio.isSupported();
    final available = await bio.isAvailable();
    final hasCreds = available && await bio.hasSavedCredentials();
    final label = supported ? await bio.label() : 'Biometrie';
    if (!mounted) return;
    setState(() {
      if (email != null && email.isNotEmpty && _email.text.isEmpty) {
        _email.text = email;
      }
      _bioSupported = supported;
      _hasSavedCreds = hasCreds;
      _bioLabel = label;
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _username.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = ref.read(authRepositoryProvider);
    final bio = ref.read(biometricLoginProvider);
    try {
      if (_registerMode) {
        await auth.signUp(
          email: email,
          password: password,
          username: _username.text,
        );
      } else {
        await auth.signIn(email: email, password: password);
      }
      // Erfolg: zuletzt genutzte E-Mail merken, dem System die Anmeldedaten
      // zum Speichern anbieten und – falls gewünscht – die Biometrie-
      // Anmeldung einrichten. Danach rebuildet currentUserProvider und der
      // Runden-Tab zeigt automatisch die Rundenliste.
      await bio.rememberEmail(email);
      TextInput.finishAutofillContext();
      if (_enableBio) {
        await bio.saveCredentials(email: email, password: password);
      } else if (_hasSavedCreds && await bio.savedEmail() != email) {
        // Manuell mit anderem Konto angemeldet -> alte Biometrie-Daten
        // wären veraltet.
        await bio.clearCredentials();
      }
    } on AuthFailure catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Unerwarteter Fehler: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Meldet per Biometrie mit den hinterlegten Zugangsdaten an.
  Future<void> _biometricLogin() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final bio = ref.read(biometricLoginProvider);
    try {
      final creds = await bio.authenticateAndRead();
      if (creds == null) {
        if (mounted) setState(() => _busy = false);
        return; // abgebrochen / fehlgeschlagen
      }
      await ref
          .read(authRepositoryProvider)
          .signIn(email: creds.email, password: creds.password);
      // Erfolg -> rebuild über currentUserProvider.
    } on AuthFailure catch (e) {
      // Passwort wurde vermutlich geändert -> hinterlegte Daten verwerfen,
      // damit der Button nicht ins Leere führt.
      await bio.clearCredentials();
      if (mounted) {
        setState(() {
          _hasSavedCreds = false;
          _error = '$e\nBitte einmal mit E-Mail und Passwort anmelden.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Unerwarteter Fehler: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Öffnet einen Dialog zum Anfordern einer Passwort-Reset-Mail. Die
  /// E-Mail aus dem Login-Feld wird vorbefüllt.
  Future<void> _forgotPassword() async {
    final email = await showDialog<String>(
      context: context,
      builder: (_) => _ForgotPasswordDialog(initialEmail: _email.text.trim()),
    );
    if (email == null || email.isEmpty || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).resetPassword(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Falls ein Konto zu dieser E-Mail existiert, ist der '
              'Reset-Link unterwegs.'),
        ));
      }
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
    // Biometrie-Login anbieten, wenn Daten hinterlegt sind und wir uns im
    // Anmelde- (nicht Registrierungs-)Modus befinden.
    final showBioButton = _hasSavedCreds && !_registerMode;
    // Einrichtung anbieten, wenn das Gerät Biometrie unterstützt, aber noch
    // nichts hinterlegt ist.
    final showBioSetup = _bioSupported && !_hasSavedCreds;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: AutofillGroup(
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
                    autofillHints: const [AutofillHints.newUsername],
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
                  autofillHints: const [
                    AutofillHints.username,
                    AutofillHints.email,
                  ],
                  decoration: const InputDecoration(
                    labelText: 'E-Mail',
                    contentPadding: EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  autofillHints: [
                    _registerMode
                        ? AutofillHints.newPassword
                        : AutofillHints.password,
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Passwort',
                    contentPadding: EdgeInsets.symmetric(horizontal: 12),
                  ),
                  onSubmitted: (_) => _busy ? null : _submit(),
                ),
                if (showBioSetup)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: CheckboxListTile(
                      value: _enableBio,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _enableBio = v ?? false),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                      title: Text('Künftig mit $_bioLabel anmelden'),
                    ),
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
                if (showBioButton) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _biometricLogin,
                    icon: const Icon(Icons.fingerprint),
                    label: Text('Mit $_bioLabel anmelden'),
                  ),
                ],
                if (!_registerMode)
                  TextButton(
                    onPressed: _busy ? null : _forgotPassword,
                    child: const Text('Passwort vergessen?'),
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
      ),
    );
  }
}

/// Dialog zum Anfordern einer Passwort-Reset-Mail. Eigenes StatefulWidget,
/// damit der TextEditingController erst beim Unmount des Dialogs sauber
/// freigegeben wird (kein manuelles dispose während der Schließ-Animation).
class _ForgotPasswordDialog extends StatefulWidget {
  const _ForgotPasswordDialog({required this.initialEmail});

  final String initialEmail;

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  late final TextEditingController _email =
      TextEditingController(text: widget.initialEmail);

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Passwort vergessen'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
              'Wir senden dir einen Link zum Zurücksetzen an deine '
              'E-Mail-Adresse.'),
          const SizedBox(height: 16),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'E-Mail'),
            onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_email.text.trim()),
          child: const Text('Link senden'),
        ),
      ],
    );
  }
}
