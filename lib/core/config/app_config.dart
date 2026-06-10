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

  static bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
