import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';

/// Wohin das Antippen einer Benachrichtigung führt.
///
/// Der Server schickt das Ziel als zwei Zeichenketten mit (`art`, `id`) —
/// FCM lässt in `data` nichts anderes zu als Strings. Welche Arten es gibt,
/// steht an genau dieser Stelle und in `push_anlegen` (Migration 0129);
/// kommt eine unbekannte Art an, öffnet die App einfach nichts, statt zu
/// scheitern.
class PushZiel {
  const PushZiel({required this.art, required this.id, this.kategorie = ''});

  final String art;
  final String id;

  /// Die Sorte, aus der die Benachrichtigung stammt. Sie entscheidet nicht,
  /// **wohin** es geht, sondern **worauf** — eine Tipprunde öffnet bei
  /// offenen Tipps den Tippen-Reiter, im Chatfall den Liga-Reiter.
  final String kategorie;

  static const arten = {'fantasy', 'tipprunde', 'nachrichten'};

  static PushZiel? ausDaten(Map<String, dynamic> daten) {
    final art = daten['art']?.toString() ?? '';
    final id = daten['id']?.toString() ?? '';
    if (!arten.contains(art) || id.isEmpty) return null;
    return PushZiel(
      art: art,
      id: id,
      kategorie: daten['kategorie']?.toString() ?? '',
    );
  }

  @override
  String toString() => 'PushZiel($art, $id, $kategorie)';
}

/// Meldet das Gerät für Push an, hält den Token in `push_geraete` aktuell und
/// reicht angetippte Benachrichtigungen nach oben.
///
/// **Der Token ist kein Geheimnis, aber er ist personenbezogen** (siehe
/// Datenschutzerklärung, Abschnitt 6): Er hängt am Konto, und beim Abmelden
/// muss er weg — sonst bekäme der nächste Nutzer desselben Geräts die
/// Benachrichtigungen des vorigen.
///
/// **Web bleibt außen vor.** Dafür bräuchte es ein Web-Push-Zertifikat und
/// einen Service Worker; die Demo-Seite soll nichts verschicken. Jeder
/// Einstiegspunkt prüft das zuerst.
class PushDienst {
  PushDienst(this._client);

  final SupabaseClient _client;

  bool _laeuft = false;
  String? _token;

  /// Zu welchem Konto der gemeldete Token gehört. Ohne diese Notiz bliebe er
  /// nach einem Kontowechsel beim Vorgänger stehen — der Dienst läuft ja
  /// schon, und `starten` kehrte wortlos um.
  String? _fuerNutzer;
  StreamSubscription<String>? _tokenAbo;
  StreamSubscription<RemoteMessage>? _tippAbo;

  /// Ist Push auf dieser Plattform überhaupt vorgesehen?
  static bool get moeglich =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  /// Fragt die Berechtigung ab, registriert den Token und hört auf Antippen.
  ///
  /// Mehrfach aufrufbar: Der zweite Aufruf tut nichts. Aufgerufen wird sie
  /// aus der App-Hülle, sobald ein Nutzer angemeldet ist — nicht aus `main()`.
  /// Vor der Anmeldung gäbe es kein Konto, dem der Token gehören könnte, und
  /// der Systemdialog käme zum denkbar schlechtesten Zeitpunkt: vor dem
  /// ersten Blick auf die App.
  Future<void> starten({
    required void Function(PushZiel ziel) beimAntippen,
  }) async {
    if (!moeglich) return;
    if (!AppConfig.isSupabaseConfigured) return;
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;

    if (_laeuft) {
      // Läuft schon. Hat sich aber das Konto geändert (Abmelden ohne den Weg
      // über den Profil-Schirm, abgelaufene Sitzung, zweiter Nutzer auf
      // demselben Gerät), muss der Token umziehen.
      if (_fuerNutzer != uid && _token != null) await _registriere(_token!);
      return;
    }
    _laeuft = true;

    final messaging = FirebaseMessaging.instance;
    try {
      final erlaubnis = await messaging.requestPermission();
      if (erlaubnis.authorizationStatus == AuthorizationStatus.denied) {
        // Abgelehnt ist eine Antwort, kein Fehler. Kein Token, kein Eintrag —
        // und `push_anlegen` legt für Nutzer ohne Gerät gar keine Aufträge an.
        return;
      }

      // iOS zeigt Benachrichtigungen im Vordergrund sonst gar nicht an.
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // Auf iOS kann der APNs-Token unmittelbar nach dem Start noch fehlen;
      // dann wirft `getToken`. Der Stream unten holt ihn nach.
      try {
        final token = await messaging.getToken();
        if (token != null) await _registriere(token);
      } catch (e) {
        debugPrint('Push: Token noch nicht verfügbar ($e) — warte auf Stream.');
      }

      _tokenAbo = messaging.onTokenRefresh.listen(
        _registriere,
        onError: (Object e) => debugPrint('Push: Token-Stream: $e'),
      );

      // Kaltstart aus der Benachrichtigung heraus.
      final start = await messaging.getInitialMessage();
      final startZiel =
          start == null ? null : PushZiel.ausDaten(start.data);
      if (startZiel != null) beimAntippen(startZiel);

      // App lief im Hintergrund und wurde angetippt.
      _tippAbo = FirebaseMessaging.onMessageOpenedApp.listen((nachricht) {
        final ziel = PushZiel.ausDaten(nachricht.data);
        if (ziel != null) beimAntippen(ziel);
      });
    } catch (e, s) {
      // Push ist eine Annehmlichkeit, kein Betriebsmittel: Scheitert die
      // Einrichtung, läuft die App normal weiter.
      _laeuft = false;
      debugPrint('Push-Einrichtung fehlgeschlagen: $e\n$s');
    }
  }

  /// Trägt den Token unter dem aktuellen Konto ein.
  ///
  /// **Über die Funktion, nicht per `upsert`:** Ein Gerät kann den Besitzer
  /// wechseln, und die Zeile gehört dann noch dem Vorgänger — eine
  /// RLS-`update`-Policy prüft die alte Zeile und lehnt ab. `push_geraet_melden`
  /// (Migration 0129) schreibt den Token dem aktuell Angemeldeten zu.
  Future<void> _registriere(String token) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    _token = token;
    _fuerNutzer = uid;
    try {
      await _client.rpc('push_geraet_melden', params: {
        'p_token': token,
        'p_plattform':
            defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
      });
    } catch (e) {
      debugPrint('Push: Token konnte nicht gespeichert werden: $e');
    }
  }

  /// Vor dem Abmelden: Token aus der Tabelle und aus FCM entfernen.
  ///
  /// Reihenfolge zählt — erst die Zeile löschen (dafür braucht es die noch
  /// gültige Sitzung, RLS lässt nur eigene Zeilen zu), dann den Token bei
  /// Google zurückziehen.
  Future<void> abmelden() async {
    if (!moeglich) return;
    final token = _token;
    try {
      if (token != null) {
        await _client.from('push_geraete').delete().eq('token', token);
      }
      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      debugPrint('Push: Abmelden am Gerät fehlgeschlagen: $e');
    } finally {
      await _tokenAbo?.cancel();
      await _tippAbo?.cancel();
      _tokenAbo = null;
      _tippAbo = null;
      _token = null;
      _fuerNutzer = null;
      _laeuft = false;
    }
  }
}

final pushDienstProvider = Provider<PushDienst>((ref) {
  return PushDienst(Supabase.instance.client);
});
