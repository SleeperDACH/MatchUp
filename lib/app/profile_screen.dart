import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../features/auth/providers.dart';
import '../features/auth/ui/login_screen.dart';
import '../features/favorites/ui/favorites_settings_screen.dart';
import '../features/messaging/ui/conversations_screen.dart';
import '../features/tippspiel/logic/tip_stats.dart';
import '../features/tippspiel/providers.dart';
import 'theme.dart';

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
        const _StatsSection(),
        _SectionLabel('Nachrichten'),
        Card(
          child: ListTile(
            leading: Icon(Icons.forum_outlined, color: scheme.primary),
            title: const Text('Direktnachrichten'),
            subtitle: const Text('Chatte mit anderen Nutzern — ligaübergreifend'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const ConversationsScreen())),
          ),
        ),
        const SizedBox(height: 16),
        _SectionLabel('Einstellungen'),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.brightness_6_outlined, color: scheme.primary),
                    const SizedBox(width: 12),
                    const Text('Erscheinungsbild',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                          value: ThemeMode.system,
                          icon: Icon(Icons.brightness_auto, size: 18),
                          label: Text('System')),
                      ButtonSegment(
                          value: ThemeMode.light,
                          icon: Icon(Icons.light_mode, size: 18),
                          label: Text('Hell')),
                      ButtonSegment(
                          value: ThemeMode.dark,
                          icon: Icon(Icons.dark_mode, size: 18),
                          label: Text('Dunkel')),
                    ],
                    selected: {ref.watch(themeModeProvider)},
                    onSelectionChanged: (s) =>
                        ref.read(themeModeProvider.notifier).set(s.first),
                  ),
                ),
              ],
            ),
          ),
        ),
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

/// Profil-Dashboard: aggregierte Tipp-Bilanz über alle Tipprunden.
class _StatsSection extends ConsumerWidget {
  const _StatsSection();

  static const _exactColor = Color(0xFF2ECC71);
  static const _diffColor = Color(0xFF4FC3A1);
  static const _tendColor = Color(0xFFFFC83D);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(myTipStatsProvider);
    final stats = statsAsync.valueOrNull;
    // Nichts anzeigen, solange keine Mitgliedschaft/Bilanz vorliegt.
    if (stats == null || stats.rounds == 0) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    String quote(int n) =>
        stats.scored == 0 ? '–' : '${(n * 100 / stats.scored).round()}%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel('Deine Tipp-Bilanz'),
        Row(
          children: [
            _StatTile(
                label: 'Exakt',
                value: quote(stats.exact),
                accent: _exactColor),
            const SizedBox(width: 10),
            _StatTile(
                label: 'Tordifferenz',
                value: quote(stats.goalDiff),
                accent: _diffColor),
            const SizedBox(width: 10),
            _StatTile(
                label: 'Tendenz',
                value: quote(stats.tendency),
                accent: _tendColor),
          ],
        ),
        const SizedBox(height: 10),
        if (stats.scored > 0) ...[
          _BreakdownBar(stats: stats),
          const SizedBox(height: 8),
          Text(
            '${stats.points} Punkte · '
            '${stats.rounds} Tipprunde${stats.rounds == 1 ? '' : 'n'} · '
            '${stats.scored} gewertete Tipps',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant),
          ),
        ] else
          Text(
            '${stats.rounds} Tipprunde${stats.rounds == 1 ? '' : 'n'} · '
            'noch keine gewerteten Tipps',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant),
          ),
        const SizedBox(height: 20),
      ],
    );
  }
}

/// Eine Kennzahl-Kachel im Dashboard.
class _StatTile extends StatelessWidget {
  const _StatTile(
      {required this.label, required this.value, required this.accent});

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold, color: accent)),
            const SizedBox(height: 2),
            Text(label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

/// Gestapelter Balken: Anteil exakt / Tordifferenz / Tendenz / daneben.
class _BreakdownBar extends StatelessWidget {
  const _BreakdownBar({required this.stats});

  final TipStats stats;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final segments = <(int, Color, String)>[
      (stats.exact, _StatsSection._exactColor, 'Exakt'),
      (stats.goalDiff, _StatsSection._diffColor, 'Tordiff.'),
      (stats.tendency, _StatsSection._tendColor, 'Tendenz'),
      (stats.missed, scheme.surfaceContainerHighest, 'Daneben'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 12,
            child: Row(
              children: [
                for (final (count, color, _) in segments)
                  if (count > 0)
                    Expanded(flex: count, child: ColoredBox(color: color)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            for (final (count, color, label) in segments)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                        color: color, borderRadius: BorderRadius.circular(3)),
                  ),
                  const SizedBox(width: 5),
                  Text('$label $count',
                      style: Theme.of(context).textTheme.labelSmall),
                ],
              ),
          ],
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
