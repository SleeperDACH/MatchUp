import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/home_screen.dart';
import 'app/theme.dart';
import 'core/config/app_config.dart';

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

class FantasyApp extends StatelessWidget {
  const FantasyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tippspiel',
      theme: buildAppTheme(),
      home: const HomeScreen(),
    );
  }
}
