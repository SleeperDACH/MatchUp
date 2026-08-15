import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/main_shell.dart';
import 'app/theme.dart';
import 'core/config/app_config.dart';
import 'features/auth/password_recovery.dart';
import 'features/auth/providers.dart';
import 'features/auth/ui/login_screen.dart';
import 'features/auth/ui/update_password_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Intl.defaultLocale = 'de_DE';
  await initializeDateFormatting('de_DE');

  // Ohne Supabase-Konfiguration läuft die App im lokalen Modus
  // (siehe AppConfig) — praktisch für Entwicklung und das MVP.
  if (AppConfig.hasSupabaseKeys) {
    // Scheitert die Initialisierung, startet die App im lokalen Modus weiter.
    // Ein ungefangener Fehler hier würde die App vor dem ersten Frame
    // abbrechen — der Nutzer sähe nur einen Absturz.
    try {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        publishableKey: AppConfig.supabaseAnonKey,
        // Implicit-Flow: der Passwort-Reset-Link trägt die Tokens selbst im
        // URL-Fragment. So funktioniert der Reset auch geräteübergreifend
        // (in der App angefordert, im Browser geöffnet) — im Gegensatz zu PKCE,
        // das den Verifier auf dem anfordernden Gerät bräuchte.
        authOptions: const FlutterAuthClientOptions(
          authFlowType: AuthFlowType.implicit,
        ),
      );
      AppConfig.supabaseInitialized = true;

      // Recovery-Link: Supabase löst die Tokens aus der URL ein und feuert
      // passwordRecovery. Statt einen Screen zu pushen (fragil ggü.
      // Rebuilds/Auto-Navigation) setzen wir nur ein Flag — den Rest macht
      // das Gate. Fängt den Fall ab, dass die App schon läuft.
      Supabase.instance.client.auth.onAuthStateChange.listen((data) {
        if (data.event == AuthChangeEvent.passwordRecovery) {
          passwordRecoveryMode.value = true;
        }
      });

      // Der Listener allein reicht nicht: `Supabase.initialize` verarbeitet
      // den Start-Link bereits selbst, also *bevor* die Zeilen oben laufen.
      // Beim Kaltstart aus der Reset-Mail — der Normalfall auf dem Handy —
      // wäre das Event längst verpufft und der Nutzer landete auf der
      // Startseite statt beim Passwort-Screen. Deshalb lesen wir den
      // Start-Link zusätzlich selbst; `type=recovery` steht im Fragment.
      await _pruefeRecoveryStartlink();
      _beobachteRecoveryLinks();
    } catch (e, s) {
      debugPrint('Supabase-Initialisierung fehlgeschlagen: $e\n$s');
    }
  }

  runApp(const ProviderScope(child: FantasyApp()));
}

/// Implicit-Flow: `#access_token=…&type=recovery`. Das Fragment ist kein
/// Query-String, deshalb von Hand prüfen statt `queryParameters` zu nutzen.
bool _istRecoveryLink(Uri uri) => uri.fragment.contains('type=recovery');

/// Wurde die App über einen Passwort-Reset-Link **gestartet**? Dann direkt in
/// den „Neues Passwort"-Screen. Nur nativ — im Web trägt schon die Adresszeile
/// das Fragment, und dort greift der Listener rechtzeitig.
Future<void> _pruefeRecoveryStartlink() async {
  if (kIsWeb) return;
  try {
    final uri = await AppLinks().getInitialLink();
    if (uri != null && _istRecoveryLink(uri)) {
      passwordRecoveryMode.value = true;
    }
  } catch (e) {
    debugPrint('Start-Link konnte nicht gelesen werden: $e');
  }
}

/// Dasselbe für den **Warmstart**: Link kommt an, während die App schon läuft.
///
/// Das ist der häufigere Weg, nicht der Sonderfall — der Tester fordert die
/// Mail *in der App* an, wechselt zu Mail und tippt den Link; MatchUp liegt
/// dann im Hintergrund. `main()` läuft dabei nicht erneut, `getInitialLink()`
/// also auch nicht. Übrig blieb allein der `passwordRecovery`-Listener, und
/// der feuert nur, wenn Supabase den Token-Tausch in `getSessionFromUrl`
/// erfolgreich abschließt. Scheitert der (abgelaufener oder schon benutzter
/// Link, keine Verbindung), kam die App kommentarlos auf der Startseite hoch —
/// genau das haben die TestFlight-Tester gemeldet.
///
/// Die App schaut sich den Link jetzt selbst an, unabhängig davon, was
/// Supabase daraus macht. Kalt- und Warmstart verhalten sich damit gleich.
void _beobachteRecoveryLinks() {
  if (kIsWeb) return;
  // `AppLinks()` ist ein Singleton mit Broadcast-Stream — diese Anmeldung
  // kommt der internen von supabase_flutter nicht in die Quere.
  AppLinks().uriLinkStream.listen(
    (uri) {
      if (_istRecoveryLink(uri)) passwordRecoveryMode.value = true;
    },
    onError: (Object e) => debugPrint('Deep-Link-Stream: $e'),
  );
}

class FantasyApp extends ConsumerWidget {
  const FantasyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Tippspiel',
      // MatchUp ist dark-only — kein Hell-Modus.
      theme: buildAppTheme(brightness: Brightness.dark),
      themeMode: ThemeMode.dark,
      home: const _RootGate(),
    );
  }
}

/// Gate: per Recovery-Link der „Neues Passwort"-Screen; sonst ohne Anmeldung
/// der bildschirmfüllende Login, angemeldet die App-Shell. Im lokalen Modus
/// (ohne Supabase) immer die Shell.
class _RootGate extends ConsumerWidget {
  const _RootGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user =
        AppConfig.isSupabaseConfigured ? ref.watch(currentUserProvider) : null;
    return ValueListenableBuilder<bool>(
      valueListenable: passwordRecoveryMode,
      builder: (context, recovery, _) {
        if (kDebugMode) {
          debugPrint('[AUTH] Gate baut: user=${user?.email} '
              'recovery=$recovery konfiguriert=${AppConfig.isSupabaseConfigured}');
        }
        if (recovery) return const UpdatePasswordScreen();
        if (!AppConfig.isSupabaseConfigured) return const MainShell();
        return user == null ? const LoginScreen() : const MainShell();
      },
    );
  }
}
