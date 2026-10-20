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
    PushKategorie('wochenrueckblick', PushBereich.fantasy, 'Wochenrückblick',
        'Wenn der Rückblick auf den letzten Spieltag erscheint.'),
    PushKategorie('ausfaelle', PushBereich.fantasy, 'Ausfälle',
        'Wenn ein aufgestellter Spieler verletzt oder gesperrt ist.'),
    PushKategorie('liga_chat', PushBereich.fantasy, 'Liga-Chat',
        'Neue Nachrichten im Chat deiner Fantasy-Ligen.'),
    PushKategorie('liga_anfragen', PushBereich.fantasy, 'Beitrittsanfragen',
        'Wenn jemand in eine Liga will, die du verwaltest.'),
    PushKategorie('tipps', PushBereich.tippspiel, 'Offene Tipps',
        'Vor Anpfiff, falls dein Tipp noch fehlt.'),
    PushKategorie('runden_chat', PushBereich.tippspiel, 'Tipprunden-Chat',
        'Neue Nachrichten im Chat deiner Tipprunden.'),
    PushKategorie('runden_anfragen', PushBereich.tippspiel,
        'Beitrittsanfragen',
        'Wenn jemand in eine Tipprunde will, die du verwaltest.'),
    PushKategorie('live_anpfiff', PushBereich.live, 'Anpfiff',
        'Wenn ein Spiel deiner Vereine beginnt.'),
    PushKategorie('live_tore', PushBereich.live, 'Tore',
        'Jedes Tor in den Spielen deiner Vereine.'),
    PushKategorie('live_rote_karten', PushBereich.live, 'Rote Karten',
        'Rot und Gelb-Rot in den Spielen deiner Vereine.'),
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
  const PushEinstellungen(this._werte, {this.tippZeiten});

  const PushEinstellungen.allesAn()
      : _werte = const {},
        tippZeiten = null;

  final Map<String, bool> _werte;

  /// **Wann die Tipp-Erinnerung kommt** — Minuten vor Anpfiff, absteigend.
  /// `null` heißt Standard ([tippZeitenStandard]); dieselbe Regel wie in
  /// `push_tipp_erinnerungen` (Migration 0136).
  final List<int>? tippZeiten;

  /// 2 Stunden und 30 Minuten vor Anpfiff (seit 0137; davor 3 Std.).
  static const tippZeitenStandard = [120, 30];

  /// Was zur Wahl steht: 30 Minuten, 1 Stunde und 2, 4, 6 … 24 Stunden
  /// (auf Ansage, 17.10.2026: Stunden nur im 2-Stunden-Takt). Dieselbe Liste
  /// prüft die Datenbank (`push_einstellungen_tipp_zeiten_erlaubt`).
  static final tippZeitenWahl = List<int>.unmodifiable([
    30,
    60,
    for (var h = 2; h <= 24; h += 2) h * 60,
  ]);

  /// Die tatsächlich geltenden Zeitpunkte.
  List<int> get tippZeitenWirksam => tippZeiten ?? tippZeitenStandard;

  PushEinstellungen mitTippZeiten(List<int>? zeiten) => PushEinstellungen(
        _werte,
        tippZeiten: zeiten == null
            ? null
            : (zeiten.toSet().toList()..sort((a, b) => b.compareTo(a))),
      );

  /// „3 Std. und 30 Min. vorher" — für den Untertitel.
  static String zeitenText(List<int> zeiten) {
    String eins(int m) => m < 60 ? '$m Min.' : '${m ~/ 60} Std.';
    final sortiert = [...zeiten]..sort((a, b) => b.compareTo(a));
    final teile = sortiert.map(eins).toList();
    final satz = teile.length == 1
        ? teile.single
        : '${teile.sublist(0, teile.length - 1).join(', ')} und ${teile.last}';
    return '$satz vorher';
  }

  bool an(String schluessel) => _werte[schluessel] ?? true;

  factory PushEinstellungen.fromRow(Map<String, dynamic> r) {
    return PushEinstellungen({
      for (final k in PushKategorie.alle)
        k.schluessel: (r[k.schluessel] as bool?) ?? true,
    }, tippZeiten: (r['tipp_zeiten'] as List?)?.cast<int>());
  }

  PushEinstellungen kopieMit(String schluessel, bool wert) {
    return PushEinstellungen({
      for (final k in PushKategorie.alle) k.schluessel: an(k.schluessel),
      schluessel: wert,
    }, tippZeiten: tippZeiten);
  }

  Map<String, dynamic> toRow(String userId) => {
        'user_id': userId,
        for (final k in PushKategorie.alle) k.schluessel: an(k.schluessel),
        'tipp_zeiten': tippZeiten,
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
