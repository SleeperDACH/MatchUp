import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import 'auth_repository.dart';

/// Anmeldung über Google und Apple.
///
/// Zwei Wege, und welcher genommen wird, entscheidet die Plattform — nicht
/// eine Einstellung:
///
/// * **Nativ** (`signInWithIdToken`), wo es das gibt: iOS und Android bei
///   Google, iOS/macOS bei Apple. Das Betriebssystem zeigt seinen eigenen
///   Auswahldialog, liefert ein ID-Token, und das reicht Supabase. Kein
///   Browserfenster, kein Deep-Link, und die Sitzung steht, wenn der Aufruf
///   zurückkommt.
/// * **Browser** (`signInWithOAuth`), wo es nichts Natives gibt: Web bei
///   beiden, Android bei Apple (Apple hat dort kein SDK). Der Aufruf kehrt
///   sofort zurück — die Sitzung entsteht erst, wenn der Deep-Link
///   `app.matchup.mobile://login-callback` wieder in der App landet. Wer
///   danach etwas erledigen will, hängt sich an `onAuthStateChange`, nicht an
///   das `await` hier. Genau deshalb sitzt die Profil-Nachsorge dort und
///   nicht hinter dem Knopf (siehe [AuthRepository.ensureProfileFromIdentity]).
///
/// Abbruch durch den Nutzer ist **kein Fehler**: Beide Wege liefern dann
/// `false` bzw. werfen einen Abbruch-Code, und die Oberfläche soll wortlos
/// zum Formular zurückkehren. Eine rote Zeile „Anmeldung fehlgeschlagen",
/// nachdem jemand selbst auf „Abbrechen" getippt hat, wäre eine Anschuldigung.
class SocialAuthService {
  SocialAuthService(this._client);

  final SupabaseClient _client;

  /// `GoogleSignIn.initialize` darf pro Prozess nur einmal laufen; ein zweiter
  /// Aufruf hängt einen weiteren Listener an den Plattform-Ereignisstrom.
  bool _googleBereit = false;

  /// Meldet mit Google an. Gibt `false` zurück, wenn der Nutzer abgebrochen
  /// hat, und `true`, wenn die Anmeldung durch ist **oder** (Browser-Weg) das
  /// Fenster geöffnet wurde.
  Future<bool> signInWithGoogle() async {
    if (!_nativeGoogleMoeglich) return _imBrowser(OAuthProvider.google);

    final google = GoogleSignIn.instance;
    if (!_googleBereit) {
      // Auf iOS zählt die iOS-Client-ID, auf Android die Web-Client-ID als
      // `serverClientId`: Android stellt das ID-Token auf den *Server*-Client
      // aus, und dessen Kennung erwartet Supabase in der `aud`-Angabe. Wer
      // hier nur `clientId` setzt, bekommt auf Android ein Token, das
      // Supabase mit „Invalid audience" ablehnt.
      await google.initialize(
        clientId: AppConfig.googleIosClientId.isEmpty
            ? null
            : AppConfig.googleIosClientId,
        serverClientId: AppConfig.googleWebClientId.isEmpty
            ? null
            : AppConfig.googleWebClientId,
      );
      _googleBereit = true;
    }

    final GoogleSignInAccount konto;
    try {
      konto = await google.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return false;
      throw AuthFailure(_googleMeldung(e));
    }

    // Seit google_sign_in 7 liefert `authentication` **nur** das ID-Token;
    // ein Access-Token gäbe es allein über den Autorisierungs-Client, und
    // Supabase braucht dafür keins.
    final idToken = konto.authentication.idToken;
    if (idToken == null) {
      throw const AuthFailure(
          'Google hat kein Anmelde-Token geliefert. Bitte versuche es erneut '
          'oder melde dich mit E-Mail und Passwort an.');
    }

    await _anSupabase(
      provider: OAuthProvider.google,
      idToken: idToken,
      anzeigename: konto.displayName,
    );
    return true;
  }

  /// Meldet mit Apple an.
  ///
  /// Der Name kommt **nur beim allerersten Mal**: Apple gibt Vor- und
  /// Nachnamen genau bei der Erstanmeldung heraus, danach nie wieder. Wer ihn
  /// da nicht mitnimmt, hat ihn für immer verloren — deshalb wandert er sofort
  /// ins Profil und nicht erst irgendwann später.
  Future<bool> signInWithApple() async {
    if (!await _nativeAppleMoeglich()) return _imBrowser(OAuthProvider.apple);

    // Supabase prüft, ob das ID-Token zu *dieser* Anfrage gehört: Apple bekommt
    // den SHA-256-Abdruck, Supabase das Original. Ohne das ließe sich ein
    // abgefangenes Token ein zweites Mal einlösen.
    final rohNonce = generateNonce();
    final AuthorizationCredentialAppleID zugang;
    try {
      zugang = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: sha256.convert(utf8.encode(rohNonce)).toString(),
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return false;
      throw AuthFailure('Anmeldung mit Apple fehlgeschlagen: ${e.message}');
    } on SignInWithAppleException catch (e) {
      throw AuthFailure('Anmeldung mit Apple fehlgeschlagen: $e');
    }

    final idToken = zugang.identityToken;
    if (idToken == null) {
      throw const AuthFailure(
          'Apple hat kein Anmelde-Token geliefert. Bitte versuche es erneut '
          'oder melde dich mit E-Mail und Passwort an.');
    }

    final name = [zugang.givenName, zugang.familyName]
        .whereType<String>()
        .where((t) => t.trim().isNotEmpty)
        .join(' ');

    await _anSupabase(
      provider: OAuthProvider.apple,
      idToken: idToken,
      nonce: rohNonce,
      anzeigename: name.isEmpty ? null : name,
    );
    return true;
  }

  /// Tauscht das ID-Token gegen eine Supabase-Sitzung und sorgt dafür, dass
  /// ein Profil existiert.
  Future<void> _anSupabase({
    required OAuthProvider provider,
    required String idToken,
    String? nonce,
    String? anzeigename,
  }) async {
    try {
      await _client.auth.signInWithIdToken(
        provider: provider,
        idToken: idToken,
        nonce: nonce,
      );
    } on AuthException catch (e) {
      throw AuthFailure(switch (e.code) {
        // Kommt, wenn der Anbieter im Supabase-Dashboard nicht aktiviert ist —
        // der häufigste Fehler bei der Ersteinrichtung, und die Rohmeldung
        // („Unsupported provider") sagt niemandem, wo er nachsehen soll.
        'validation_failed' || 'provider_disabled' =>
          'Diese Anmeldeart ist auf dem Server noch nicht freigeschaltet.',
        _ => 'Anmeldung fehlgeschlagen: ${e.message}',
      });
    }
    await AuthRepository(_client).ensureProfileFromIdentity(
      bevorzugterName: anzeigename,
    );
  }

  /// Öffnet den Anbieter im Browser. Rückgabe: wurde das Fenster geöffnet?
  ///
  /// Die Sitzung entsteht danach über den Deep-Link, nicht hier.
  Future<bool> _imBrowser(OAuthProvider provider) async {
    try {
      return await _client.auth.signInWithOAuth(
        provider,
        // Im Web bleibt der Nutzer im Browser; nativ muss die Rückkehr in die
        // App zeigen. Beide Adressen müssen in Supabase unter
        // Authentication → URL Configuration → Redirect URLs stehen.
        redirectTo: kIsWeb ? null : AppConfig.appDeepLink,
      );
    } on AuthException catch (e) {
      throw AuthFailure('Anmeldung fehlgeschlagen: ${e.message}');
    }
  }

  /// Google nativ: überall außer Web — und nur, wenn die Plattform-Client-ID
  /// einkompiliert ist.
  bool get _nativeGoogleMoeglich {
    if (kIsWeb) return false;
    if (!GoogleSignIn.instance.supportsAuthenticate()) return false;
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS ||
      TargetPlatform.macOS =>
        AppConfig.googleIosClientId.isNotEmpty,
      TargetPlatform.android => AppConfig.googleWebClientId.isNotEmpty,
      _ => false,
    };
  }

  /// Apple nativ: nur auf Apple-Plattformen, und erst ab iOS 13 / macOS 10.15
  /// — deshalb die Rückfrage ans System statt einer Annahme.
  Future<bool> _nativeAppleMoeglich() async {
    if (kIsWeb) return false;
    if (defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.macOS) {
      return false;
    }
    return SignInWithApple.isAvailable();
  }

  String _googleMeldung(GoogleSignInException e) =>
      switch (e.code) {
        GoogleSignInExceptionCode.canceled ||
        GoogleSignInExceptionCode.interrupted =>
          'Die Anmeldung wurde abgebrochen.',
        GoogleSignInExceptionCode.clientConfigurationError =>
          'Die Google-Anmeldung ist für diese App nicht richtig eingerichtet.',
        GoogleSignInExceptionCode.providerConfigurationError =>
          'Google-Anmeldung steht auf diesem Gerät nicht zur Verfügung.',
        _ => 'Anmeldung mit Google fehlgeschlagen: ${e.description ?? e.code}',
      };
}
