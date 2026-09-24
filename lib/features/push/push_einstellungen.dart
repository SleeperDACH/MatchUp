import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import '../auth/providers.dart';

/// Eine Sorte Benachrichtigung — Schlüssel, Name und der Satz darunter.
///
/// Die Schlüssel sind dieselben wie die Spalten in `push_einstellungen` und
/// die erlaubten Werte von `push_auftraege.kategorie` (Migration 0129). Wer
/// hier eine Sorte ergänzt, ergänzt dort eine Spalte — sonst landet ein
/// Auftrag mit unbekannter Kategorie im Check-Constraint.
class PushKategorie {
  const PushKategorie(this.schluessel, this.name, this.hinweis);

  final String schluessel;
  final String name;
  final String hinweis;

  static const alle = [
    PushKategorie('draft', 'Draft',
        'Wenn du im Draft am Zug bist.'),
    PushKategorie('trades', 'Trades',
        'Neue Angebote und ob deines angenommen wurde.'),
    PushKategorie('waiver', 'Waiver',
        'Ob dein Antrag durchgegangen ist.'),
    PushKategorie('nachrichten', 'Nachrichten',
        'Direktnachrichten sowie Liga- und Tipprunden-Chat.'),
    PushKategorie('ausfaelle', 'Ausfälle',
        'Wenn ein aufgestellter Spieler verletzt oder gesperrt ist.'),
    PushKategorie('tipps', 'Offene Tipps',
        'Erinnerung, solange vor Anstoß noch Tipps fehlen.'),
    PushKategorie('anfragen', 'Anfragen',
        'Beitritts- und Freundschaftsanfragen.'),
  ];
}

/// Die Schalter eines Nutzers. **Fehlende Zeile heißt „alles an"** — dieselbe
/// Regel wie in der Datenbank, und sie steht hier ein zweites Mal, weil der
/// Schirm sonst beim ersten Öffnen sieben ausgeschaltete Schalter zeigte.
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
