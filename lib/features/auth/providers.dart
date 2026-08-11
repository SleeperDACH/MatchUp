import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import 'auth_repository.dart';
import 'biometric_login.dart';
import 'user_profile.dart';

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
  final state = ref.watch(authStateProvider);
  // Den Nutzer **aus dem Ereignis** lesen, nicht bloß aus dem globalen
  // Client. Vorher lieferte der Auslöser (`ref.watch`) und der Wert
  // (`auth.currentUser`) aus zwei verschiedenen Quellen: Riverpod entschied
  // anhand des Stream-Ereignisses, *wann* neu gerechnet wird, der Wert kam
  // aber aus einem veränderlichen globalen Zustand. Takten die beiden nicht
  // exakt gleich, bleibt das Gate auf dem alten Wert stehen — der Login
  // gelingt, die Oberfläche zeigt weiter den Anmeldescreen, und erst der
  // nächste Kaltstart liest die persistierte Sitzung. Genau dieses Bild
  // haben die TestFlight-Tester gemeldet.
  //
  // `currentUser` bleibt als Rückfall stehen: Bei `signedOut` ist die Session
  // im Ereignis null und `currentUser` ebenfalls null (richtig), und solange
  // der Stream nach einem `invalidate` noch lädt, liefert der Client bereits
  // den gültigen Nutzer.
  return state.valueOrNull?.session?.user ??
      Supabase.instance.client.auth.currentUser;
});

/// Nutzername des angemeldeten Profils (für Begrüßung/Profil-Tab).
final currentUsernameProvider = FutureProvider<String?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  return ref.watch(authRepositoryProvider).fetchUsername();
});

/// Eigenes Profil inkl. Avatar (Bild oder Emoji+Farbe).
final currentProfileProvider = FutureProvider<UserProfile?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  return ref.watch(authRepositoryProvider).fetchProfile();
});
