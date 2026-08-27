import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import 'auth_repository.dart';
import 'biometric_login.dart';
import 'social_auth.dart';
import 'user_profile.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(Supabase.instance.client);
});

/// Anmeldung über Google und Apple (nativ, wo möglich; sonst Browser).
final socialAuthProvider = Provider<SocialAuthService>((ref) {
  return SocialAuthService(Supabase.instance.client);
});

/// Zeigt der Anmeldescreen den Google- bzw. Apple-Knopf?
///
/// Die Antwort steckt eigentlich schon in [AppConfig] — als Provider ist sie
/// im Test überschreibbar. Sonst ließe sich das Formular mit den Knöpfen nie
/// abbilden: Ohne einkompilierte Client-IDs sind beide Werte `false`, und eine
/// Golden-Vorschau zeigte genau das, was der Nutzer später **nicht** sieht.
final googleSignInAvailableProvider =
    Provider<bool>((ref) => AppConfig.hasGoogleSignIn);
final appleSignInAvailableProvider =
    Provider<bool>((ref) => AppConfig.hasAppleSignIn);

/// E-Mail merken + Face-ID-/Fingerabdruck-Schnellanmeldung.
final biometricLoginProvider = Provider<BiometricLoginService>((ref) {
  return BiometricLoginService();
});

/// Auth-Zustand als Stream; leer, wenn Supabase nicht konfiguriert ist
/// (lokaler Modus).
final authStateProvider = StreamProvider<AuthState>((ref) {
  if (!AppConfig.isSupabaseConfigured) return const Stream.empty();
  return Supabase.instance.client.auth.onAuthStateChange.map((e) {
    if (kDebugMode) {
      debugPrint('[AUTH] Ereignis ${e.event.name} '
          'session=${e.session != null} user=${e.session?.user.email}');
    }
    return e;
  });
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
  final ausEreignis = state.valueOrNull?.session?.user;
  final ausClient = Supabase.instance.client.auth.currentUser;
  if (kDebugMode) {
    debugPrint('[AUTH] currentUserProvider neu berechnet: '
        'ausEreignis=${ausEreignis?.email} ausClient=${ausClient?.email} '
        'streamZustand=${state.runtimeType}');
  }
  return ausEreignis ?? ausClient;
});

/// Nutzername des angemeldeten Profils (für Begrüßung/Profil-Tab).
final currentUsernameProvider = FutureProvider<String?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  return ref.watch(authRepositoryProvider).fetchUsername();
});

/// Eigenes Profil inkl. Avatar (Bild oder Emoji+Farbe).
/// Profil des angemeldeten Nutzers — **und legt es an, wenn es fehlt.**
///
/// Ein Konto ohne `profiles`-Zeile ist kein theoretischer Fall: Von 25
/// Registrierungen hatten drei keine. Beim Anlegen kann der Einfügeversuch
/// scheitern (etwa weil der Nutzername schon vergeben ist), das Auth-Konto
/// bleibt aber bestehen — und danach gab es **keinen Weg zurück**:
/// `ensureProfileFromIdentity` lief nur nach Google/Apple, nie nach einer
/// E-Mail-Anmeldung. Betroffene sahen oben „Willkommen" statt ihres Namens,
/// und jeder Liga-Beitritt scheiterte an
/// `fantasy_league_members_user_id_fkey`, weil der Fremdschlüssel auf
/// `profiles` zeigt.
///
/// Die Heilung sitzt hier, weil hier jeder Weg vorbeikommt — Kaltstart,
/// E-Mail-Login, Google, Apple. Sie läuft nur, wenn wirklich kein Profil da
/// ist, und schluckt ihren Fehler: Ein Profil, das sich nicht anlegen lässt,
/// darf nicht auch noch den Start blockieren.
final currentProfileProvider = FutureProvider<UserProfile?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  final repo = ref.watch(authRepositoryProvider);
  final vorhanden = await repo.fetchProfile();
  if (vorhanden != null) return vorhanden;
  try {
    await repo.ensureProfileFromIdentity();
  } catch (_) {
    return null;
  }
  return repo.fetchProfile();
});
