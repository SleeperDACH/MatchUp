import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/home_screen.dart';
import 'app/theme.dart';
import 'core/config/app_config.dart';
import 'features/auth/ui/update_password_screen.dart';

/// Globaler Navigator-Schlüssel, damit der Recovery-Handler auch ohne
/// BuildContext (aus dem main-Listener) navigieren kann.
final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Intl.defaultLocale = 'de_DE';
  await initializeDateFormatting('de_DE');

  // Ohne Supabase-Konfiguration läuft die App im lokalen Modus
  // (siehe AppConfig) — praktisch für Entwicklung und das MVP.
  if (AppConfig.isSupabaseConfigured) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
    );

    // Recovery-Link: Supabase löst den Code schon beim Start ein und feuert
    // passwordRecovery. Der Listener muss deshalb so früh wie möglich (vor
    // runApp) hängen, sonst verpufft das Event auf dem Broadcast-Stream.
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        _openPasswordReset();
      }
    });
  }

  runApp(const ProviderScope(child: FantasyApp()));
}

/// Öffnet den „Neues Passwort"-Screen. Feuert das Event, bevor der Navigator
/// steht, versuchen wir es nach dem nächsten Frame erneut.
void _openPasswordReset() {
  final nav = navigatorKey.currentState;
  if (nav == null) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _openPasswordReset());
    return;
  }
  nav.push(
    MaterialPageRoute(builder: (_) => const UpdatePasswordScreen()),
  );
}

class FantasyApp extends StatelessWidget {
  const FantasyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tippspiel',
      theme: buildAppTheme(),
      navigatorKey: navigatorKey,
      home: const HomeScreen(),
    );
  }
}
