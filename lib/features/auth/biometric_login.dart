import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Merkt die zuletzt genutzte E-Mail (alle Plattformen) und verwaltet die
/// optionale Schnellanmeldung per Face ID / Fingerabdruck.
///
/// Die Zugangsdaten liegen verschlüsselt im Geräte-Schlüsselbund (iOS
/// Keychain / Android Keystore), freigeschaltet durch die Biometrie. Im Web
/// gibt es keine Biometrie — alle Biometrie-/Schlüsselbund-Aufrufe sind dort
/// No-Ops (`kIsWeb`-Guard); das E-Mail-Merken funktioniert trotzdem (der
/// Browser-Passwortmanager übernimmt das Speichern der Zugangsdaten).
class BiometricLoginService {
  BiometricLoginService({
    LocalAuthentication? auth,
    FlutterSecureStorage? storage,
  })  : _auth = auth ?? LocalAuthentication(),
        _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  final LocalAuthentication _auth;
  final FlutterSecureStorage _storage;

  static const _kLastEmail = 'auth_last_email'; // SharedPreferences
  static const _kSecEmail = 'biometric_email'; // Schlüsselbund
  static const _kSecPassword = 'biometric_password';

  // --- Zuletzt genutzte E-Mail (alle Plattformen) ------------------------

  Future<String?> lastEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kLastEmail);
  }

  Future<void> rememberEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastEmail, email.trim());
  }

  // --- Biometrie-Verfügbarkeit (nur nativ) -------------------------------

  /// True, wenn das Gerät Biometrie kann und mindestens eine Methode
  /// eingerichtet ist. Im Web immer false.
  Future<bool> isAvailable() async {
    if (kIsWeb) return false;
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  /// Lesbarer Name der primären Methode für Button-Texte.
  Future<String> label() async {
    if (kIsWeb) return 'Biometrie';
    try {
      final types = await _auth.getAvailableBiometrics();
      if (types.contains(BiometricType.face)) return 'Face ID';
      if (types.contains(BiometricType.fingerprint)) return 'Fingerabdruck';
      if (types.contains(BiometricType.iris)) return 'Iris-Scan';
    } catch (_) {/* fällt unten durch */}
    return 'Biometrie';
  }

  // --- Gespeicherte Zugangsdaten -----------------------------------------

  Future<bool> hasSavedCredentials() async {
    if (kIsWeb) return false;
    try {
      return await _storage.containsKey(key: _kSecEmail) &&
          await _storage.containsKey(key: _kSecPassword);
    } catch (_) {
      return false;
    }
  }

  Future<String?> savedEmail() async {
    if (kIsWeb) return null;
    try {
      return await _storage.read(key: _kSecEmail);
    } catch (_) {
      return null;
    }
  }

  /// Speichert (bzw. überschreibt) die Zugangsdaten für die Biometrie-Anmeldung.
  Future<void> saveCredentials({
    required String email,
    required String password,
  }) async {
    if (kIsWeb) return;
    await _storage.write(key: _kSecEmail, value: email.trim());
    await _storage.write(key: _kSecPassword, value: password);
  }

  Future<void> clearCredentials() async {
    if (kIsWeb) return;
    try {
      await _storage.delete(key: _kSecEmail);
      await _storage.delete(key: _kSecPassword);
    } catch (_) {/* nichts zu tun */}
  }

  /// Fordert die Biometrie an und gibt bei Erfolg die hinterlegten
  /// Zugangsdaten zurück, sonst null (abgebrochen, fehlgeschlagen oder nichts
  /// gespeichert).
  Future<({String email, String password})?> authenticateAndRead() async {
    if (kIsWeb || !await hasSavedCredentials()) return null;
    bool ok;
    try {
      ok = await _auth.authenticate(
        localizedReason: 'Zum Anmelden bei MatchUp bestätigen',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return null;
    }
    if (!ok) return null;
    final email = await _storage.read(key: _kSecEmail);
    final password = await _storage.read(key: _kSecPassword);
    if (email == null || password == null) return null;
    return (email: email, password: password);
  }
}
