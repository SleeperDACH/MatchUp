import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import 'user_profile.dart';

/// Login, Registrierung und Profil. Wirft [AuthFailure] mit
/// deutschsprachigen Meldungen für die UI.
class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  User? get currentUser => _client.auth.currentUser;

  Future<void> signIn({required String email, required String password}) async {
    try {
      await _client.auth.signInWithPassword(email: email, password: password);
    } on AuthException catch (e) {
      throw AuthFailure(switch (e.code) {
        'invalid_credentials' => 'E-Mail oder Passwort ist falsch.',
        _ => 'Anmeldung fehlgeschlagen: ${e.message}',
      });
    }
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String username,
  }) async {
    final trimmed = username.trim();
    if (trimmed.length < 3 || trimmed.length > 24) {
      throw const AuthFailure(
          'Der Nutzername muss 3–24 Zeichen lang sein.');
    }
    final AuthResponse response;
    try {
      response = await _client.auth.signUp(email: email, password: password);
    } on AuthException catch (e) {
      throw AuthFailure(switch (e.code) {
        'user_already_exists' =>
          'Für diese E-Mail existiert bereits ein Konto.',
        'weak_password' => 'Das Passwort ist zu schwach (min. 6 Zeichen).',
        _ => 'Registrierung fehlgeschlagen: ${e.message}',
      });
    }
    final user = response.user;
    if (user == null) {
      throw const AuthFailure('Registrierung fehlgeschlagen.');
    }
    try {
      await _client.from('profiles').insert({'id': user.id, 'username': trimmed});
    } on PostgrestException catch (e) {
      // 23505 = unique_violation (Nutzername vergeben). Konto existiert
      // dann schon; beim nächsten Login kann das Profil nachgeholt werden.
      throw AuthFailure(e.code == '23505'
          ? 'Der Nutzername "$trimmed" ist bereits vergeben.'
          : 'Profil konnte nicht angelegt werden: ${e.message}');
    }
  }

  /// Schickt eine „Passwort zurücksetzen"-Mail an [email]. Aus
  /// Datenschutzgründen verrät Supabase nicht, ob die Adresse existiert —
  /// die UI meldet daher immer neutralen Erfolg.
  Future<void> resetPassword(String email) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty) {
      throw const AuthFailure('Bitte gib deine E-Mail-Adresse ein.');
    }
    final redirect = AppConfig.passwordResetRedirect;
    try {
      await _client.auth.resetPasswordForEmail(
        trimmed,
        redirectTo: redirect.isEmpty ? null : redirect,
      );
    } on AuthException catch (e) {
      throw AuthFailure('Reset-Mail konnte nicht gesendet werden: ${e.message}');
    }
  }

  /// Setzt das Passwort des aktuell (per Recovery-Link) angemeldeten
  /// Nutzers neu. Wird vom „Neues Passwort"-Screen aufgerufen.
  Future<void> updatePassword(String newPassword) async {
    if (newPassword.length < 6) {
      throw const AuthFailure('Das Passwort muss mindestens 6 Zeichen haben.');
    }
    try {
      await _client.auth.updateUser(UserAttributes(password: newPassword));
    } on AuthException catch (e) {
      throw AuthFailure(switch (e.code) {
        'same_password' =>
          'Das neue Passwort darf nicht dem alten entsprechen.',
        'weak_password' => 'Das Passwort ist zu schwach (min. 6 Zeichen).',
        _ => 'Passwort konnte nicht geändert werden: ${e.message}',
      });
    }
  }

  /// Ändert den eigenen Nutzernamen (3–24 Zeichen, eindeutig). Nur die eigene
  /// Profilzeile ist per RLS änderbar.
  Future<void> updateUsername(String newName) async {
    final user = currentUser;
    if (user == null) return;
    final trimmed = newName.trim();
    if (trimmed.length < 3 || trimmed.length > 24) {
      throw const AuthFailure('Der Nutzername muss 3–24 Zeichen lang sein.');
    }
    try {
      await _client
          .from('profiles')
          .update({'username': trimmed}).eq('id', user.id);
    } on PostgrestException catch (e) {
      throw AuthFailure(e.code == '23505'
          ? 'Der Nutzername „$trimmed" ist bereits vergeben.'
          : 'Nutzername konnte nicht geändert werden: ${e.message}');
    }
  }

  /// Ändert die eigene E-Mail-Adresse. Supabase verschickt einen
  /// Bestätigungslink an die neue Adresse; erst danach ist sie aktiv.
  Future<void> updateEmail(String newEmail) async {
    final trimmed = newEmail.trim();
    if (trimmed.isEmpty || !trimmed.contains('@')) {
      throw const AuthFailure('Bitte gib eine gültige E-Mail-Adresse ein.');
    }
    try {
      await _client.auth.updateUser(UserAttributes(email: trimmed));
    } on AuthException catch (e) {
      throw AuthFailure(switch (e.code) {
        'email_exists' => 'Diese E-Mail wird bereits verwendet.',
        _ => 'E-Mail konnte nicht geändert werden: ${e.message}',
      });
    }
  }

  /// Ändert das Passwort aus dem Profil heraus: prüft zuerst das aktuelle
  /// Passwort (erneuter Login mit der bestehenden Sitzung) und setzt dann das
  /// neue. So kann niemand über eine offene Sitzung unbemerkt das Passwort
  /// austauschen.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final email = currentUser?.email;
    if (email == null) throw const AuthFailure('Nicht angemeldet.');
    if (newPassword.length < 6) {
      throw const AuthFailure(
          'Das neue Passwort muss mindestens 6 Zeichen haben.');
    }
    try {
      await _client.auth
          .signInWithPassword(email: email, password: currentPassword);
    } on AuthException {
      throw const AuthFailure('Das aktuelle Passwort ist falsch.');
    }
    try {
      await _client.auth.updateUser(UserAttributes(password: newPassword));
    } on AuthException catch (e) {
      throw AuthFailure(switch (e.code) {
        'same_password' =>
          'Das neue Passwort darf nicht dem alten entsprechen.',
        'weak_password' => 'Das Passwort ist zu schwach (min. 6 Zeichen).',
        _ => 'Passwort konnte nicht geändert werden: ${e.message}',
      });
    }
  }

  /// Legt das Profil nachträglich an, falls es bei der Registrierung
  /// fehlschlug (z. B. Nutzername vergeben).
  Future<void> ensureProfile(String username) async {
    final user = currentUser;
    if (user == null) return;
    await _client
        .from('profiles')
        .upsert({'id': user.id, 'username': username.trim()});
  }

  Future<String?> fetchUsername() async {
    final user = currentUser;
    if (user == null) return null;
    final row = await _client
        .from('profiles')
        .select('username')
        .eq('id', user.id)
        .maybeSingle();
    return row?['username'] as String?;
  }

  /// Vollständiges eigenes Profil inkl. Avatar-Felder.
  Future<UserProfile?> fetchProfile() async {
    final user = currentUser;
    if (user == null) return null;
    final row = await _client
        .from('profiles')
        .select('username, avatar_url, avatar_emoji, avatar_color')
        .eq('id', user.id)
        .maybeSingle();
    return row == null ? null : UserProfile.fromJson(row);
  }

  /// Setzt das eigene Profilbild (Bild-URL oder Emoji+Farbe; alles `null` =
  /// entfernen). Nur die eigene Zeile ist per RLS änderbar.
  Future<void> setAvatar({String? url, String? emoji, String? color}) async {
    final user = currentUser;
    if (user == null) return;
    await _client.from('profiles').update({
      'avatar_url': url,
      'avatar_emoji': emoji,
      'avatar_color': color,
    }).eq('id', user.id);
  }

  Future<void> signOut() => _client.auth.signOut();

  /// Löscht das eigene Konto endgültig (Edge Function `delete-account` mit
  /// Service-Role) und meldet danach lokal ab.
  Future<void> deleteAccount() async {
    final res = await _client.functions.invoke('delete-account');
    final data = res.data;
    if (data is Map && data['error'] != null) {
      throw AuthFailure(data['error'].toString());
    }
    await _client.auth.signOut();
  }
}

class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;

  @override
  String toString() => message;
}
