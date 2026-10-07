import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import '../auth/providers.dart';

/// Die vier Blöcke des Einstellungsschirms (Migration 0131).
enum PushBereich {
  fantasy('Fantasy'),
  tippspiel('Tippspiel'),
  live('Live'),
  allgemein('Allgemein');

  const PushBereich(this.titel);
  final String titel;
}

/// Eine Sorte Benachrichtigung — Schlüssel, Name und der Satz darunter.
///
/// Die Schlüssel sind dieselben wie die Spalten in `push_einstellungen` und
/// die erlaubten Werte von `push_auftraege.kategorie` (Migration 0131). Wer
/// hier eine Sorte ergänzt, ergänzt dort eine Spalte und den Check — sonst
/// landet ein Auftrag mit unbekannter Kategorie im Check-Constraint.
class PushKategorie {
  const PushKategorie(this.schluessel, this.bereich, this.name, this.hinweis);

  final String schluessel;
  final PushBereich bereich;
  final String name;
  final String hinweis;

  static const alle = [
    PushKategorie('draft', PushBereich.fantasy, 'Draft',
        'Wenn du im Draft am Zug bist.'),
    PushKategorie('trades', PushBereich.fantasy, 'Trades',
        'Angebote an dich, Antworten auf deine und jeder angenommene Trade '
            'in deinen Ligen.'),
    PushKategorie('waiver', PushBereich.fantasy, 'Waiver',
        'Ob dein Antrag durchgegangen ist.'),
    PushKategorie('ausfaelle', PushBereich.fantasy, 'Ausfälle',
        'Wenn ein aufgestellter Spieler verletzt oder gesperrt ist.'),
    PushKategorie('liga_chat', PushBereich.fantasy, 'Liga-Chat',
        'Neue Nachrichten im Chat deiner Fantasy-Ligen.'),
    PushKategorie('liga_anfragen', PushBereich.fantasy, 'Beitrittsanfragen',
        'Wenn jemand in eine Liga will, die du verwaltest.'),
    PushKategorie('tipps', PushBereich.tippspiel, 'Offene Tipps',
        'Drei Stunden vor Anpfiff, falls dein Tipp noch fehlt.'),
    PushKategorie('runden_chat', PushBereich.tippspiel, 'Tipprunden-Chat',
        'Neue Nachrichten im Chat deiner Tipprunden.'),
    PushKategorie('runden_anfragen', PushBereich.tippspiel,
        'Beitrittsanfragen',
        'Wenn jemand in eine Tipprunde will, die du verwaltest.'),
    PushKategorie('live_anpfiff', PushBereich.live, 'Anpfiff',
        'Wenn ein Spiel deiner Lieblingsvereine beginnt.'),
    PushKategorie('live_tore', PushBereich.live, 'Tore',
        'Jedes Tor in den Spielen deiner Lieblingsvereine.'),
    PushKategorie('live_rote_karten', PushBereich.live, 'Rote Karten',
        'Rot und Gelb-Rot in den Spielen deiner Lieblingsvereine.'),
    PushKategorie('live_halbzeit', PushBereich.live, 'Halbzeit',
        'Der Stand zur Pause.'),
    PushKategorie('live_endstand', PushBereich.live, 'Endstand',
        'Das Ergebnis nach dem Abpfiff.'),
    PushKategorie('direktnachrichten', PushBereich.allgemein,
        'Direktnachrichten', 'Wenn dir jemand schreibt.'),
    PushKategorie('freunde', PushBereich.allgemein, 'Freundschaften',
        'Neue Anfragen und angenommene.'),
  ];

  static List<PushKategorie> imBereich(PushBereich b) =>
      [for (final k in alle) if (k.bereich == b) k];
}

/// Die Schalter eines Nutzers. **Fehlende Zeile heißt „alles an"** — dieselbe
/// Regel wie in der Datenbank, und sie steht hier ein zweites Mal, weil der
/// Schirm sonst beim ersten Öffnen lauter ausgeschaltete Schalter zeigte.
class PushEinstellungen {
  const PushEinstellungen(this._werte);

  const PushEinstellungen.allesAn() : _werte = const {};

  final Map<String, bool> _werte;

  bool an(String schluessel) => _werte[schluessel] ?? true;

  factory PushEinstellungen.fromRow(Map<String, dynamic> r) {
    return PushEinstellungen({
      for (final k in PushKategorie.alle)
        k.schluessel: (r[k.schluessel] as bool?) ?? true,
    });
  }

  PushEinstellungen kopieMit(String schluessel, bool wert) {
    return PushEinstellungen({
      for (final k in PushKategorie.alle) k.schluessel: an(k.schluessel),
      schluessel: wert,
    });
  }

  Map<String, dynamic> toRow(String userId) => {
        'user_id': userId,
        for (final k in PushKategorie.alle) k.schluessel: an(k.schluessel),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
}

class PushEinstellungenRepository {
  PushEinstellungenRepository(this._client);

  final SupabaseClient _client;

  String? get _uid => _client.auth.currentUser?.id;

  Future<PushEinstellungen> laden() async {
    final uid = _uid;
    if (uid == null) return const PushEinstellungen.allesAn();
    final row = await _client
        .from('push_einstellungen')
        .select()
        .eq('user_id', uid)
        .maybeSingle();
    if (row == null) return const PushEinstellungen.allesAn();
    return PushEinstellungen.fromRow(row);
  }

  /// Schreibt den ganzen Satz, nicht nur den einen Schalter: Die Zeile
  /// entsteht erst beim ersten Abschalten, und ein `upsert` mit nur einer
  /// Spalte ließe die übrigen auf ihren Vorgabewerten stehen — was zufällig
  /// stimmt, solange die Vorgabe „an" ist, und beim nächsten geänderten
  /// Vorgabewert still falsch wird.
  Future<void> speichern(PushEinstellungen e) async {
    final uid = _uid;
    if (uid == null) return;
    await _client
        .from('push_einstellungen')
        .upsert(e.toRow(uid), onConflict: 'user_id');
  }
}

final pushEinstellungenRepositoryProvider =
    Provider<PushEinstellungenRepository>((ref) {
  return PushEinstellungenRepository(Supabase.instance.client);
});

/// Die Schalter des angemeldeten Nutzers. Im lokalen Modus (ohne Server)
/// steht alles auf „an", ohne dass jemand gefragt wird.
final pushEinstellungenProvider =
    FutureProvider<PushEinstellungen>((ref) async {
  if (!AppConfig.isSupabaseConfigured) {
    return const PushEinstellungen.allesAn();
  }
  // Am Konto hängen: Nach einem Wechsel zeigte der Schirm sonst die Schalter
  // des Vorgängers, bis jemand die App neu startet.
  ref.watch(currentUserProvider);
  return ref.read(pushEinstellungenRepositoryProvider).laden();
});
