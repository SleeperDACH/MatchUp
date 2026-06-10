import 'package:supabase_flutter/supabase_flutter.dart';

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

  Future<void> signOut() => _client.auth.signOut();
}

class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;

  @override
  String toString() => message;
}
