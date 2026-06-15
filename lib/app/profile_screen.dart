import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../features/auth/providers.dart';
import '../features/auth/ui/login_screen.dart';
import '../features/favorites/ui/favorites_settings_screen.dart';

/// Profil-Tab: Konto-Übersicht und -Aktionen (Abmelden, App-Info).
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('Profil')),
      body: user == null
          ? _SignedOut()
          : _Profile(
              username: ref.watch(currentUsernameProvider).valueOrNull,
              email: user.email,
            ),
    );
  }
}

class _Profile extends ConsumerWidget {
  const _Profile({required this.username, required this.email});

  final String? username;
  final String? email;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final name = username ?? '—';
    final initial = (username == null || username!.isEmpty)
        ? '?'
        : username!.characters.first.toUpperCase();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      children: [
        // Kopf: Avatar + Name + E-Mail.
        Center(
          child: Column(
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: scheme.primary.withValues(alpha: 0.18),
                child: Text(
                  initial,
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                    color: scheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(name,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              if (email != null) ...[
                const SizedBox(height: 2),
                Text(email!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 28),
        _SectionLabel('Einstellungen'),
        Card(
          child: ListTile(
            leading: Icon(Icons.star_outline, color: scheme.primary),
            title: const Text('Favoriten'),
            subtitle: const Text('Teams & Ligen für den Live-Tab'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const FavoritesSettingsScreen())),
          ),
        ),
        const SizedBox(height: 16),
        _SectionLabel('Konto'),
        Card(
          child: ListTile(
            leading: Icon(Icons.logout, color: scheme.error),
            title: Text('Abmelden', style: TextStyle(color: scheme.error)),
            onTap: () => ref.read(authRepositoryProvider).signOut(),
          ),
        ),
        const SizedBox(height: 16),
        _SectionLabel('App'),
        const Card(
          child: ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('MatchUp'),
            subtitle: Text('Tippspiel & Fantasy mit Freunden'),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(text,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
    );
  }
}

class _SignedOut extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final configured = AppConfig.isSupabaseConfigured;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_circle_outlined,
                size: 72, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              configured
                  ? 'Melde dich an, um dein Profil, deine Ligen und Tipprunden zu sehen.'
                  : 'Profile gibt es nur mit Server-Verbindung.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant),
            ),
            if (configured) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                icon: const Icon(Icons.login),
                label: const Text('Anmelden'),
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LoginScreen())),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
