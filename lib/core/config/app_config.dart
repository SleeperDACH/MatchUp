/// Build-Zeit-Konfiguration.
///
/// Supabase-Zugangsdaten werden per `--dart-define` gesetzt, damit keine
/// Keys im Repo landen:
///
/// ```sh
/// flutter run \
///   --dart-define=SUPABASE_URL=https://xyz.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=eyJ...
/// ```
///
/// Ohne Konfiguration läuft die App im lokalen Modus (Tipps nur auf dem
/// Gerät, keine Tipprunden mit Freunden).
abstract final class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Ziel-URL, auf der der Passwort-Reset-Link landet. Standard: die Web-Demo
  /// (dort läuft die Flutter-Web-App und setzt den Recovery-Screen). Per
  /// `--dart-define=PASSWORD_RESET_REDIRECT=…` überschreibbar. Muss in Supabase
  /// unter den erlaubten Redirect-URLs eingetragen sein. Die App (Handy) hat
  /// keinen Deep-Link, daher zeigt der Link bewusst auf die Web-Demo.
  static const passwordResetRedirect = String.fromEnvironment(
    'PASSWORD_RESET_REDIRECT',
    defaultValue: 'https://sleeperdach.github.io/MatchUp/',
  );

  static bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// API-Key für die Wettquoten (the-odds-api.com), per
  /// `--dart-define=ODDS_API_KEY=…`. Leer = Quoten werden ausgeblendet.
  static const oddsApiKey = String.fromEnvironment('ODDS_API_KEY');

  static bool get hasOdds => oddsApiKey.isNotEmpty;
}
