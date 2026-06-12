import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/home_screen.dart';
import 'app/theme.dart';
import 'core/config/app_config.dart';
import 'features/auth/providers.dart';
import 'features/auth/ui/update_password_screen.dart';

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
  }

  runApp(const ProviderScope(child: FantasyApp()));
}

class FantasyApp extends ConsumerWidget {
  const FantasyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Klickt jemand den Passwort-Reset-Link, meldet Supabase ihn in einer
    // Recovery-Session an und feuert passwordRecovery — dann öffnen wir
    // direkt den „Neues Passwort"-Screen.
    ref.listen(authStateProvider, (_, next) {
      if (next.valueOrNull?.event == AuthChangeEvent.passwordRecovery) {
        navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const UpdatePasswordScreen()),
        );
      }
    });

    return MaterialApp(
      title: 'Tippspiel',
      theme: buildAppTheme(),
      navigatorKey: navigatorKey,
      home: const HomeScreen(),
    );
  }
}

/// Globaler Navigator-Schlüssel, damit der Recovery-Handler auch ohne
/// BuildContext navigieren kann.
final navigatorKey = GlobalKey<NavigatorState>();
