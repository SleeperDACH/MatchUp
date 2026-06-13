import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import 'auth_repository.dart';
import 'biometric_login.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(Supabase.instance.client);
});

/// E-Mail merken + Face-ID-/Fingerabdruck-Schnellanmeldung.
final biometricLoginProvider = Provider<BiometricLoginService>((ref) {
  return BiometricLoginService();
});

/// Auth-Zustand als Stream; leer, wenn Supabase nicht konfiguriert ist
/// (lokaler Modus).
final authStateProvider = StreamProvider<AuthState>((ref) {
  if (!AppConfig.isSupabaseConfigured) return const Stream.empty();
  return Supabase.instance.client.auth.onAuthStateChange;
});

final currentUserProvider = Provider<User?>((ref) {
  if (!AppConfig.isSupabaseConfigured) return null;
  // Rebuild bei Login/Logout.
  ref.watch(authStateProvider);
  return Supabase.instance.client.auth.currentUser;
});
