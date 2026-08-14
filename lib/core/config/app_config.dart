import 'package:flutter/foundation.dart' show kIsWeb;

/// Build-Zeit-Konfiguration.
///
/// Die Supabase-Zugangsdaten stehen hier fest im Code. Das ist Absicht: sonst
/// hätte jeder Build, der ohne `--dart-define` entsteht — TestFlight, ein
/// Archiv aus Xcode, ein Kollege mit frischem Checkout — keine Server-Anbindung
/// und die App fiele stumm in den lokalen Modus. Genau daran ist der erste
/// TestFlight-Build gescheitert.
///
/// Der Key ist ungefährlich: `sb_publishable_…` ist der von Supabase für
/// Clients vorgesehene Schlüssel, er steckt ohnehin in jedem ausgelieferten
/// Web- und App-Bundle. Geschützt wird die Datenbank durch RLS, nicht durch
/// Geheimhaltung dieses Werts. **Der Service-Role-Key gehört niemals hierher.**
///
/// Beide Werte lassen sich weiterhin überschreiben, etwa für ein
/// Staging-Projekt:
///
/// ```sh
/// flutter run \
///   --dart-define=SUPABASE_URL=https://xyz.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=sb_publishable_…
/// ```
abstract final class AppConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://zleuiewcydrazogkfafp.supabase.co',
  );
  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_lJBIlqeAYTILnQTInsK71Q_n2kCb7tN',
  );

  /// Deep-Link zurück in die installierte App. Registriert in
  /// `ios/Runner/Info.plist` (`CFBundleURLTypes`) und
  /// `android/app/src/main/AndroidManifest.xml` (Intent-Filter) — wer eines
  /// davon ändert, muss alle drei Stellen angleichen, sonst öffnet der Link
  /// nichts mehr. Schema = Bundle-ID, damit keine fremde App es beansprucht.
  static const appDeepLink = 'app.matchup.mobile://login-callback/';

  /// Web-Ziel für den Passwort-Reset: die Flutter-Web-Demo, die denselben
  /// Recovery-Screen zeigt.
  static const webResetRedirect = 'https://sleeperdach.github.io/MatchUp/';

  /// Datenschutzerklärung — Pflichtangabe für App Store und Google Play.
  ///
  /// Liegt bewusst **außerhalb** von `/MatchUp/`: Unter diesem Pfad hatte ein
  /// früherer Web-Demo-Build einen Service Worker registriert, der jede Anfrage
  /// darunter abfängt und den zwischengespeicherten App-Rumpf ausliefert. Auf
  /// der Nutzer-Seite (Repo `sleeperdach.github.io`) greift der nicht.
  static const privacyUrl = 'https://sleeperdach.github.io/datenschutz.html';

  /// Anleitung zur Kontolöschung — von Google Play als eigene, öffentlich
  /// erreichbare URL verlangt (Data safety → Kontolöschung).
  static const accountDeletionUrl =
      'https://sleeperdach.github.io/konto-loeschen.html';

  /// Ziel-URL, auf der der Passwort-Reset-Link landet.
  ///
  /// Auf dem Handy zeigt er in die App: Der Tester fordert das neue Passwort
  /// in der App an, tippt den Link in seiner Mail und ist wieder in der App —
  /// vorher landete er in Safari auf der Web-Demo und musste sich am Ende
  /// erneut in der App anmelden.
  ///
  /// **Beide Werte müssen in Supabase unter Authentication → URL Configuration
  /// → Redirect URLs stehen**, sonst ersetzt Supabase sie stillschweigend
  /// durch die Site-URL und der Link führt woanders hin.
  ///
  /// Per `--dart-define=PASSWORD_RESET_REDIRECT=…` überschreibbar.
  static String get passwordResetRedirect {
    const override = String.fromEnvironment('PASSWORD_RESET_REDIRECT');
    if (override.isNotEmpty) return override;
    return kIsWeb ? webResetRedirect : appDeepLink;
  }

  /// Sind überhaupt Zugangsdaten einkompiliert? (Build-Zeit)
  static bool get hasSupabaseKeys =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Hat `Supabase.initialize` tatsächlich geklappt? Wird ausschließlich in
  /// `main()` gesetzt. Ohne dieses Flag darf niemand `Supabase.instance`
  /// anfassen — die Bibliothek wirft dann eine Assertion, und zwar aus jedem
  /// Provider heraus, der den Server anspricht. Der Zustand ist real: Keys
  /// können einkompiliert sein und die Initialisierung trotzdem scheitern
  /// (kaputter Secure-Storage, Datenmüll in der gespeicherten Session).
  /// Im Widget-Test bleibt das Flag `false`, weil dort kein `main()` läuft.
  static bool supabaseInitialized = false;

  /// Ist der Server jetzt gerade benutzbar? Das ist die Frage, die die
  /// Provider und die Oberfläche wirklich stellen — deshalb prüft sie beides.
  static bool get isSupabaseConfigured =>
      hasSupabaseKeys && supabaseInitialized;

  /// API-Key für die Wettquoten (the-odds-api.com), per
  /// `--dart-define=ODDS_API_KEY=…`. Leer = Quoten werden ausgeblendet.
  static const oddsApiKey = String.fromEnvironment('ODDS_API_KEY');

  static bool get hasOdds => oddsApiKey.isNotEmpty;
}
