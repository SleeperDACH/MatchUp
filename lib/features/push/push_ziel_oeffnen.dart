import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/league_screen.dart';
import '../fantasy/providers.dart';
import '../fantasy/ui/fantasy_league_screen.dart';
import '../messaging/ui/conversation_screen.dart';
import '../tippspiel/providers.dart';
import 'push_dienst.dart';

/// Öffnet den Schirm, auf den eine angetippte Benachrichtigung zeigt.
///
/// **Die Benachrichtigung trägt nur Art und ID**, nicht das fertige Objekt:
/// Zwischen dem Versand und dem Antippen können Stunden liegen, und ein
/// mitgeschickter Liganame wäre dann womöglich veraltet. Geholt wird beim
/// Öffnen — über dieselben Repositories, die auch die Liga-Suche benutzt.
///
/// Scheitert das Holen (Liga gelöscht, keine Verbindung), passiert nichts
/// weiter als ein kurzer Hinweis. Eine Benachrichtigung darf keinen roten
/// Schirm auslösen.
Future<void> pushZielOeffnen(
  BuildContext context,
  WidgetRef ref,
  PushZiel ziel,
) async {
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    switch (ziel.art) {
      case 'fantasy':
        final liga =
            await ref.read(fantasyLeagueRepositoryProvider).fetchLeague(ziel.id);
        if (!context.mounted) return;
        navigator.push(MaterialPageRoute(
            builder: (_) => FantasyLeagueScreen(league: liga)));

      case 'tipprunde':
        final runde =
            await ref.read(tipRoundRepositoryProvider).fetchRound(ziel.id);
        if (!context.mounted) return;
        // Wie überall beim Einstieg in eine Runde: erst aktivieren (setzt
        // Runde + Wettbewerb zusammen), dann öffnen.
        activateRound(ref, runde);
        navigator.push(MaterialPageRoute(
          builder: (_) => LeagueScreen(
            round: runde,
            // Offene Tipps führen auf den Tippen-Reiter, ein Chat auf den
            // Liga-Reiter; sonst bleibt es bei der Tabelle.
            initialTab: switch (ziel.kategorie) {
              'tipps' => 0,
              'nachrichten' => 2,
              _ => 1,
            },
          ),
        ));

      case 'nachrichten':
        // Der Name des Partners steht nicht in der Benachrichtigung — der
        // Chat-Schirm braucht ihn für seinen Kopf. Eine Zeile aus `profiles`,
        // die ohnehin öffentlich lesbar ist.
        final row = await Supabase.instance.client
            .from('profiles')
            .select('username')
            .eq('id', ziel.id)
            .maybeSingle();
        if (!context.mounted) return;
        navigator.push(MaterialPageRoute(
          builder: (_) => ConversationScreen(
            partnerId: ziel.id,
            partnerName: (row?['username'] as String?) ?? 'Nachricht',
          ),
        ));
    }
  } catch (e) {
    messenger.showSnackBar(
        SnackBar(content: Text('Konnte nicht geöffnet werden: $e')));
  }
}
