import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config/app_config.dart';
import '../core/ui/app_avatar.dart';
import '../features/auth/providers.dart';
import '../features/auth/user_profile.dart';
import '../features/friends/providers.dart';
import '../features/friends/ui/friends_screen.dart';
import '../features/messaging/providers.dart';
import '../features/messaging/ui/conversations_screen.dart';
import 'impressum_screen.dart';
import 'profile_screen.dart';
import 'theme.dart';

/// Schmales Seitenmenü über das Hamburger-Symbol oben links (füllt den
/// Bildschirm nicht): Kopf mit Avatar + Name als Einstieg ins Profil, darunter
/// Profil, Freunde und Chats als Direktzugänge, unten das Rechtliche.
///
/// Die Fläche kommt aus `drawerTheme` (neutral, ohne Seed-Tönung); der Akzent
/// steckt nur noch in den Icon-Kacheln und im Ring um den Avatar. Ein feiner
/// Lichtschimmer oben links gibt dem Panel Tiefe, ohne dass die Marke die
/// ganze Fläche einfärbt.
class HomeMenuDrawer extends ConsumerWidget {
  const HomeMenuDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final username = ref.watch(currentUsernameProvider).valueOrNull;
    final requests = ref.watch(incomingRequestsCountProvider);
    final unreadDms = ref.watch(hasUnreadDmsProvider);

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
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
                child: Container(
                  height: 1,
                  color: scheme.outlineVariant.withValues(alpha: 0.7),
                ),
              ),
              _DrawerEintrag(
                icon: Icons.person_outline_rounded,
                label: 'Profil',
                onTap: () => open(const ProfileScreen()),
              ),
              _DrawerEintrag(
                icon: Icons.group_outlined,
                label: 'Freunde',
                onTap: () => open(const FriendsScreen()),
                trailing: requests > 0 ? _ZahlPille(anzahl: requests) : null,
              ),
              _DrawerEintrag(
                icon: Icons.forum_outlined,
                label: 'Chats',
                onTap: () => open(const ConversationsScreen()),
                trailing: unreadDms ? const _UngelesenPunkt() : null,
              ),
              const Spacer(),
              // Rechtliches, bewusst sehr dezent – nur der Vollständigkeit
              // halber. Der Datenschutz steht vor dem Impressum, weil beide
              // Stores ihn verlangen und er häufiger gesucht wird.
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                // `Wrap`: bei großer Schriftskalierung bricht die Zeile um,
                // statt über den Rand zu laufen.
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _RechtlichesLink(
                      label: 'Datenschutz',
                      onTap: () => launchUrl(Uri.parse(AppConfig.privacyUrl),
                          mode: LaunchMode.externalApplication),
                    ),
                    Text('  ·  ',
                        style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant
                                .withValues(alpha: 0.35))),
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

/// Kopf des Seitenmenüs: Avatar mit Akzentring, Name und ein Hinweis, dass der
/// Kopf selbst ins Profil führt. Vorher war der Kopf nur Beschriftung — der
/// naheliegendste Tipp auf den eigenen Avatar tat nichts.
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
                Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: MatchUpColors.green.withValues(alpha: 0.55),
                      width: 1.5,
                    ),
                  ),
                  child: AppAvatar(
                    imageUrl: profile?.avatarUrl,
                    emoji: profile?.avatarEmoji,
                    colorHex: profile?.avatarColor,
                    fallbackText: username,
                    size: 46,
                  ),
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
                        'Profil ansehen',
                        style: TextStyle(
                          fontSize: 12.5,
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

/// Ein Menüpunkt: Icon in einer getönten Kachel, Beschriftung, optional ein
/// Hinweis rechts. Die Kachel ersetzt das frühere nackte `ListTile` mit
/// neongrünem Icon — der Akzent sitzt jetzt in der Fläche, das Symbol selbst
/// bleibt ruhig.
class _DrawerEintrag extends StatelessWidget {
  const _DrawerEintrag({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: MatchUpColors.green.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: MatchUpColors.green.withValues(alpha: 0.20),
                      width: 0.8,
                    ),
                  ),
                  child: Icon(icon, size: 19, color: MatchUpColors.green),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Zähler-Pille (offene Freundschaftsanfragen).
class _ZahlPille extends StatelessWidget {
  const _ZahlPille({required this.anzahl});

  final int anzahl;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: MatchUpColors.red,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        anzahl > 99 ? '99+' : '$anzahl',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
      ),
    );
  }
}

/// Punkt für ungelesene Nachrichten — mit weichem Schein, damit er auf der
/// dunklen Fläche nicht wie ein Staubkorn wirkt.
class _UngelesenPunkt extends StatelessWidget {
  const _UngelesenPunkt();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      margin: const EdgeInsets.only(right: 5),
      decoration: BoxDecoration(
        color: MatchUpColors.red,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: MatchUpColors.red.withValues(alpha: 0.55),
            blurRadius: 7,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}

/// Kleiner, sehr zurückhaltender Textlink für Datenschutz und Impressum.
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
