import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/ui/app_avatar.dart';
import '../features/auth/providers.dart';
import '../features/auth/user_profile.dart';
import '../features/auth/ui/login_screen.dart';
import '../features/favorites/ui/favorites_manage_screen.dart';
import '../features/tippspiel/logic/tip_stats.dart';
import '../features/tippspiel/providers.dart';

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

  Future<void> _editAvatar(
      BuildContext context, WidgetRef ref, UserProfile? profile) async {
    final uid = ref.read(currentUserProvider)?.id;
    if (uid == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final value = await showAvatarEditor(
      context,
      storagePath: 'profiles/$uid.jpg',
      title: 'Profilbild',
      circle: true,
      currentUrl: profile?.avatarUrl,
      currentEmoji: profile?.avatarEmoji,
      currentColor: profile?.avatarColor,
    );
    if (value == null) return;
    try {
      await ref.read(authRepositoryProvider).setAvatar(
          url: value.url, emoji: value.emoji, color: value.color);
      ref.invalidate(currentProfileProvider);
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Speichern fehlgeschlagen: $e')));
    }
  }

  /// Ändert den Nutzernamen (Kurz-Dialog).
  Future<void> _editName(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final value = await _showTextDialog(context,
        title: 'Name ändern', label: 'Nutzername', initial: username);
    if (value == null || value.isEmpty) return;
    try {
      await ref.read(authRepositoryProvider).updateUsername(value);
      ref.invalidate(currentUsernameProvider);
      ref.invalidate(currentProfileProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Name geändert.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  /// Passwort ändern: altes Passwort, neues Passwort und Bestätigung.
  Future<void> _editPassword(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<({String current, String next})>(
      context: context,
      builder: (_) => const _ChangePasswordDialog(),
    );
    if (result == null) return;
    try {
      await ref.read(authRepositoryProvider).changePassword(
          currentPassword: result.current, newPassword: result.next);
      messenger
          .showSnackBar(const SnackBar(content: Text('Passwort geändert.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  /// Ändert die E-Mail-Adresse (Bestätigung per Link an die neue Adresse).
  Future<void> _editEmail(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final value = await _showTextDialog(context,
        title: 'E-Mail ändern',
        label: 'Neue E-Mail',
        initial: email,
        keyboardType: TextInputType.emailAddress);
    if (value == null || value.isEmpty) return;
    try {
      await ref.read(authRepositoryProvider).updateEmail(value);
      messenger.showSnackBar(const SnackBar(
          content: Text('Bestätigungslink an die neue Adresse gesendet.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final profile = ref.watch(currentProfileProvider).valueOrNull;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 96),
      children: [
        // Kopf: Avatar + E-Mail.
        Center(
          child: Column(
            children: [
              GestureDetector(
                onTap: () => _editAvatar(context, ref, profile),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AppAvatar(
                      imageUrl: profile?.avatarUrl,
                      emoji: profile?.avatarEmoji,
                      colorHex: profile?.avatarColor,
                      fallbackText: username,
                      size: 88,
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: scheme.surface, width: 2),
                        ),
                        child: Icon(Icons.photo_camera,
                            size: 16, color: scheme.onPrimary),
                      ),
                    ),
                  ],
                ),
              ),
              if (email != null) ...[
                const SizedBox(height: 12),
                Text(email!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        // Kompakte Einstellungsliste (eine Karte, dünne Trenner).
        Card(
          clipBehavior: Clip.antiAlias,
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              _SettingTile(
                icon: Icons.badge_outlined,
                label: 'Name ändern',
                subtitle: username,
                onTap: () => _editName(context, ref),
              ),
              const Divider(height: 1),
              _SettingTile(
                icon: Icons.lock_outline,
                label: 'Passwort ändern',
                onTap: () => _editPassword(context, ref),
              ),
              const Divider(height: 1),
              _SettingTile(
                icon: Icons.alternate_email,
                label: 'E-Mail ändern',
                subtitle: email,
                onTap: () => _editEmail(context, ref),
              ),
              const Divider(height: 1),
              _SettingTile(
                icon: Icons.star_outline,
                label: 'Favoriten',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const FavoritesManageScreen())),
              ),
              const Divider(height: 1),
              _SettingTile(
                icon: Icons.leaderboard_outlined,
                label: 'Tippbilanz',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const TipStatsScreen())),
              ),
              const Divider(height: 1),
              _SettingTile(
                icon: Icons.logout,
                label: 'Abmelden',
                color: scheme.error,
                showChevron: false,
                onTap: () => _confirmSignOut(context, ref),
              ),
              const Divider(height: 1),
              _SettingTile(
                icon: Icons.delete_forever,
                label: 'Konto löschen',
                color: scheme.error,
                showChevron: false,
                onTap: () => _confirmDeleteAccount(context, ref),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Kompakte Einstellungszeile: kleines Icon, Titel, optional Untertitel.
class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.color,
    this.showChevron = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? subtitle;
  final Color? color;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasSub = subtitle != null && subtitle!.trim().isNotEmpty;
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -1),
      minLeadingWidth: 0,
      leading: Icon(icon, color: color ?? scheme.primary, size: 22),
      title: Text(label,
          style: TextStyle(
              color: color, fontWeight: FontWeight.w600, fontSize: 14.5)),
      subtitle: hasSub
          ? Text(subtitle!.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12, color: scheme.onSurfaceVariant))
          : null,
      trailing: showChevron
          ? Icon(Icons.chevron_right,
              size: 20, color: scheme.onSurfaceVariant)
          : null,
      onTap: onTap,
    );
  }
}

/// Kurzer Text-Eingabe-Dialog (Name / E-Mail / Passwort).
Future<String?> _showTextDialog(
  BuildContext context, {
  required String title,
  required String label,
  String? initial,
  bool obscure = false,
  TextInputType? keyboardType,
}) {
  final controller = TextEditingController(text: initial ?? '');
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        obscureText: obscure,
        keyboardType: keyboardType,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Abbrechen')),
        FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Speichern')),
      ],
    ),
  );
}

/// Dialog zum Ändern des Passworts: aktuelles Passwort, neues Passwort und
/// Bestätigung. Gibt bei Erfolg `(current, next)` zurück, sonst `null`.
class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    final cur = _current.text;
    final next = _next.text;
    final conf = _confirm.text;
    if (cur.isEmpty || next.isEmpty || conf.isEmpty) {
      setState(() => _error = 'Bitte alle Felder ausfüllen.');
      return;
    }
    if (next.length < 6) {
      setState(() =>
          _error = 'Das neue Passwort muss mindestens 6 Zeichen haben.');
      return;
    }
    if (next != conf) {
      setState(() => _error = 'Die neuen Passwörter stimmen nicht überein.');
      return;
    }
    Navigator.of(context).pop((current: cur, next: next));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Passwort ändern'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _current,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Aktuelles Passwort'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _next,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Neues Passwort'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _confirm,
            obscureText: true,
            decoration:
                const InputDecoration(labelText: 'Neues Passwort bestätigen'),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12.5)),
          ],
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen')),
        FilledButton(onPressed: _submit, child: const Text('Speichern')),
      ],
    );
  }
}

/// Eigener Screen für die Tipp-Bilanz (aus dem Profil verlinkt).
class TipStatsScreen extends StatelessWidget {
  const TipStatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('Tippbilanz')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
        children: const [_StatsSection(standalone: true)],
      ),
    );
  }
}

/// Abmelden mit Sicherheitsabfrage.
Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
  final scheme = Theme.of(context).colorScheme;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Abmelden?'),
      content: const Text(
          'Du wirst von deinem Konto abgemeldet. Zum Weiterspielen musst du '
          'dich erneut anmelden.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: scheme.error),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Abmelden'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  await ref.read(authRepositoryProvider).signOut();
}

/// Konto endgültig löschen (mit starker Bestätigung). Nach Erfolg meldet
/// [AuthRepository.deleteAccount] ab → das Gate zeigt wieder den Login.
Future<void> _confirmDeleteAccount(BuildContext context, WidgetRef ref) async {
  final scheme = Theme.of(context).colorScheme;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Konto löschen?'),
      content: const Text(
          'Dein Konto und alle zugehörigen Daten werden endgültig gelöscht — '
          'von dir erstellte Ligen und Tipprunden (für alle Mitglieder), deine '
          'Kader, Tipps, Favoriten, Freundschaften und Nachrichten. Das kann '
          'nicht rückgängig gemacht werden.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: scheme.error),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Endgültig löschen'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: Center(child: CircularProgressIndicator()),
    ),
  );
  try {
    await ref.read(authRepositoryProvider).deleteAccount();
    navigator.pop(); // Fortschritts-Dialog schließen
    navigator.popUntil((r) => r.isFirst);
    messenger.showSnackBar(const SnackBar(content: Text('Konto gelöscht.')));
  } catch (e) {
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text('Löschen fehlgeschlagen: $e')));
  }
}

/// Profil-Dashboard: aggregierte Tipp-Bilanz über alle Tipprunden.
class _StatsSection extends ConsumerWidget {
  const _StatsSection({this.standalone = false});

  /// Auf einem eigenen Screen (kein eingebetteter Abschnitt): dann ohne
  /// Abschnitts-Titel und mit Hinweistext, falls noch keine Bilanz vorliegt.
  final bool standalone;

  static const _exactColor = Color(0xFF2ECC71);
  static const _diffColor = Color(0xFF4FC3A1);
  static const _tendColor = Color(0xFFFFC83D);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(myTipStatsProvider);
    final stats = statsAsync.valueOrNull;
    final scheme = Theme.of(context).colorScheme;
    // Keine Mitgliedschaft/Bilanz: eingebettet nichts, auf dem eigenen
    // Screen ein Hinweis.
    if (stats == null || stats.rounds == 0) {
      if (!standalone) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 12),
        child: Text(
          'Noch keine gewerteten Tipps — tritt einer Tipprunde bei und '
          'tippe los.',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      );
    }

    String quote(int n) =>
        stats.scored == 0 ? '–' : '${(n * 100 / stats.scored).round()}%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!standalone) _SectionLabel('Deine Tipp-Bilanz'),
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
