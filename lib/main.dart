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
  if (AppConfig.isSupabaseConfigured) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
    );

    // Recovery-Link: Supabase löst den `?code=` schon beim Start ein und
    // feuert passwordRecovery. Statt einen Screen zu pushen (fragil ggü.
    // Rebuilds/Auto-Navigation) setzen wir nur ein Flag — den Rest macht
    // das Gate. Listener vor runApp, damit das Event nicht verpufft.
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        passwordRecoveryMode.value = true;
      }
    });
  }

  runApp(const ProviderScope(child: FantasyApp()));
}

class FantasyApp extends ConsumerWidget {
  const FantasyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Tippspiel',
      theme: buildAppTheme(brightness: Brightness.light),
      darkTheme: buildAppTheme(brightness: Brightness.dark),
      themeMode: ref.watch(themeModeProvider),
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
        if (recovery) return const UpdatePasswordScreen();
        if (!AppConfig.isSupabaseConfigured) return const MainShell();
        return user == null ? const LoginScreen() : const MainShell();
      },
    );
  }
}
