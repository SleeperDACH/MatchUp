import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config/app_config.dart';
import '../core/ui/app_avatar.dart';
import '../features/auth/providers.dart';
import '../features/auth/user_profile.dart';
import '../features/friends/providers.dart';
import '../features/friends/providers.dart' show incomingRequestsProvider, friendNamesProvider, friendAvatarsProvider;
import '../features/friends/ui/friends_screen.dart';
import '../features/messaging/providers.dart';
import '../features/messaging/ui/conversation_screen.dart';
import '../features/messaging/ui/conversations_screen.dart';
import 'impressum_screen.dart';
import 'profile_screen.dart';
import 'theme.dart';

/// Schmales Seitenmenü über das Hamburger-Symbol oben links.
///
/// **Es trägt Inhalt, nicht nur Links.** Vorher standen hier drei Zeilen —
/// Profil, Freunde, Chats — mit je einer grünen Icon-Kachel, und zwei Drittel
/// der Fläche blieben leer: ein bildschirmhohes Panel für drei Wörter.
/// Ausgerechnet neben den Kacheln standen die echten Signale (rote Zahl,
/// roter Punkt) und mussten gegen das Grün ankommen, obwohl Grün in dieser App
/// „hier läuft etwas" heißt und dort nichts lief.
///
/// Jetzt beantwortet das Menü beim Öffnen die Frage, für die man es aufmacht:
/// **Wer will was von mir?** Offene Freundschaftsanfragen und die letzten
/// Gespräche stehen mit Namen und Vorschautext darin. Farbe hat nur noch, was
/// wirklich offen ist.
///
/// Bleibt beides leer, fällt der Schirm auf schlichte Zeilen zurück — ein
/// Abschnitt mit einer Überschrift und nichts darunter wäre schlimmer als der
/// alte Zustand.
class HomeMenuDrawer extends ConsumerWidget {
  const HomeMenuDrawer({super.key});

  /// Wie viele Zeilen je Abschnitt höchstens stehen. Mehr macht aus dem Menü
  /// einen zweiten Chat-Screen; für alles Weitere gibt es „Alle anzeigen".
  static const _maxZeilen = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final username = ref.watch(currentUsernameProvider).valueOrNull;

    final anfragen = ref.watch(incomingRequestsProvider);
    final freundNamen = ref.watch(friendNamesProvider).valueOrNull ?? const {};
    final freundBilder =
        ref.watch(friendAvatarsProvider).valueOrNull ?? const {};

    final chats = ref.watch(conversationsProvider);
    final chatNamen =
        ref.watch(conversationNamesProvider).valueOrNull ?? const {};
    final chatBilder =
        ref.watch(conversationAvatarsProvider).valueOrNull ?? const {};

    // Drawer schließen und dann das Ziel öffnen.
    void open(Widget screen) {
      Navigator.of(context).pop();
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    }

    return Drawer(
      width: 292,
      child: DecoratedBox(
        // Schimmer aus der oberen linken Ecke — **neutrales** Licht, kein
        // Farbstich. Eine grüne Variante gab es; sie legte genau den Grünton
        // über die Fläche, der hier weg sollte.
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-0.9, -1.0),
            radius: 1.25,
            colors: [
              Colors.white.withValues(alpha: 0.05),
              Colors.transparent,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 6),
              _DrawerKopf(
                profile: profile,
                username: username,
                onTap: () => open(const ProfileScreen()),
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    // --- Freunde -------------------------------------------
                    _Abschnitt(
                      titel: 'Freunde',
                      hinweis: anfragen.isEmpty
                          ? null
                          : anfragen.length == 1
                          ? '1 neu'
                          : '${anfragen.length} neu',
                      onAlle: () => open(const FriendsScreen()),
                    ),
                    if (anfragen.isEmpty)
                      _SchlichteZeile(
                        label: 'Freunde verwalten',
                        onTap: () => open(const FriendsScreen()),
                      )
                    else
                      for (final id in anfragen.take(_maxZeilen))
                        _PersonZeile(
                          name: freundNamen[id] ?? 'Unbekannt',
                          avatar: freundBilder[id],
                          unterzeile: 'möchte dich hinzufügen',
                          // Rot heißt hier: wartet auf dich.
                          punkt: true,
                          onTap: () => open(const FriendsScreen()),
                        ),
                    if (anfragen.length > _maxZeilen)
                      _MehrZeile(
                        label: 'Alle Anfragen',
                        onTap: () => open(const FriendsScreen()),
                      ),

                    // --- Chats ---------------------------------------------
                    _Abschnitt(
                      titel: 'Chats',
                      onAlle: () => open(const ConversationsScreen()),
                    ),
                    if (chats.isEmpty)
                      _SchlichteZeile(
                        label: 'Nachricht schreiben',
                        onTap: () => open(const ConversationsScreen()),
                      )
                    else
                      for (final c in chats.take(_maxZeilen))
                        _ChatZeile(
                          conversation: c,
                          name: chatNamen[c.partnerId] ?? 'Unbekannt',
                          avatar: chatBilder[c.partnerId],
                          onTap: () => open(
                            ConversationScreen(
                              partnerId: c.partnerId,
                              partnerName:
                                  chatNamen[c.partnerId] ?? 'Unbekannt',
                            ),
                          ),
                        ),
                    if (chats.length > _maxZeilen)
                      _MehrZeile(
                        label: 'Alle Chats',
                        onTap: () => open(const ConversationsScreen()),
                      ),
                  ],
                ),
              ),

              // Rechtliches, bewusst sehr dezent – nur der Vollständigkeit
              // halber. Der Datenschutz steht vor dem Impressum, weil beide
              // Stores ihn verlangen und er häufiger gesucht wird.
              Container(
                height: 0.8,
                margin: const EdgeInsets.symmetric(horizontal: 20),
                color: scheme.onSurface.withValues(alpha: 0.07),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                // `Wrap`: bei großer Schriftskalierung bricht die Zeile um,
                // statt über den Rand zu laufen.
                child: Wrap(
                  spacing: 16,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _RechtlichesLink(
                      label: 'Datenschutz',
                      onTap: () => launchUrl(
                        Uri.parse(AppConfig.privacyUrl),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                    _RechtlichesLink(
                      label: 'Impressum',
                      onTap: () => open(const ImpressumScreen()),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Abschnittsmarke im Menü — Wort, Haarlinie bis an den Rand, rechts der
/// Hinweis auf Offenes. Dieselbe Kapitelmarke wie im Live- und im
/// Favoriten-Tab; ein Menü ist kein Grund für ein eigenes Gliederungsmuster.
class _Abschnitt extends StatelessWidget {
  const _Abschnitt({required this.titel, required this.onAlle, this.hinweis});

  final String titel;
  final VoidCallback onAlle;

  /// „2 neu" — steht in Rot, weil es auf jemanden wartet. Sonst `null`.
  final String? hinweis;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      header: true,
      label: [titel, ?hinweis].join(', '),
      onTap: onAlle,
      excludeSemantics: true,
      child: InkWell(
        onTap: onAlle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
          child: Row(
            children: [
              Text(
                titel.toUpperCase(),
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  height: 0.8,
                  color: scheme.onSurface.withValues(alpha: 0.12),
                ),
              ),
              if (hinweis != null) ...[
                const SizedBox(width: 10),
                Text(
                  hinweis!,
                  style: const TextStyle(
                    color: MatchUpColors.red,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Eine Person im Menü: Bild, Name, eine Zeile darunter, was ansteht.
class _PersonZeile extends StatelessWidget {
  const _PersonZeile({
    required this.name,
    required this.unterzeile,
    required this.onTap,
    this.avatar,
    this.punkt = false,
  });

  final String name;
  final String unterzeile;
  final VoidCallback onTap;
  final AvatarInfo? avatar;

  /// Roter Punkt am rechten Rand — etwas wartet.
  final bool punkt;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: '$name, $unterzeile',
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Row(
            children: [
              AppAvatar(
                imageUrl: avatar?.url,
                emoji: avatar?.emoji,
                colorHex: avatar?.color,
                fallbackText: name,
                size: 32,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      unterzeile,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (punkt) ...[
                const SizedBox(width: 8),
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: MatchUpColors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Ein Gespräch im Menü — Name und der letzte Satz daraus.
class _ChatZeile extends ConsumerWidget {
  const _ChatZeile({
    required this.conversation,
    required this.name,
    required this.onTap,
    this.avatar,
  });

  final Conversation conversation;
  final String name;
  final VoidCallback onTap;
  final AvatarInfo? avatar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final letzte = conversation.lastMessage;
    final gelesenBis = ref.watch(dmLastReadProvider(conversation.partnerId));
    // Ungelesen heißt: von der Gegenseite und neuer als die eigene Lesemarke.
    final ungelesen =
        letzte.senderId == conversation.partnerId &&
        (gelesenBis == null || letzte.createdAt.isAfter(gelesenBis));
    return _PersonZeile(
      name: name,
      avatar: avatar,
      unterzeile: letzte.body,
      punkt: ungelesen,
      onTap: onTap,
    );
  }
}

/// Zeile ohne Inhalt dahinter — steht nur, wenn ein Abschnitt leer ist.
class _SchlichteZeile extends StatelessWidget {
  const _SchlichteZeile({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    );
  }
}

/// „Alle Chats ›" am Ende eines Abschnitts, wenn mehr da ist als gezeigt wird.
class _MehrZeile extends StatelessWidget {
  const _MehrZeile({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              size: 15,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kopf des Seitenmenüs: Avatar, Name, und dass es hier ins Profil geht.
/// Vorher war der Kopf nur Beschriftung — der naheliegendste Tipp auf den
/// eigenen Avatar tat nichts. Der eigene Eintrag „Profil" darunter ist
/// entfallen: Er stand für dasselbe Ziel ein zweites Mal.
class _DrawerKopf extends StatelessWidget {
  const _DrawerKopf({
    required this.profile,
    required this.username,
    required this.onTap,
  });

  final UserProfile? profile;
  final String? username;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
            child: Row(
              children: [
                // Ohne Ring. Der grüne Reif bedeutete nichts — und Grün
                // heißt in dieser App „hier läuft etwas".
                AppAvatar(
                  imageUrl: profile?.avatarUrl,
                  emoji: profile?.avatarEmoji,
                  colorHex: profile?.avatarColor,
                  fallbackText: username,
                  size: 52,
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        username ?? 'Profil',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                          letterSpacing: -0.3,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Profil & Einstellungen',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.1,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    size: 20,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RechtlichesLink extends StatelessWidget {
  const _RechtlichesLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }
}
