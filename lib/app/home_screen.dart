import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/models/models.dart';
import '../features/auth/providers.dart';
import '../features/fantasy/models/fantasy_models.dart';
import '../features/fantasy/providers.dart';
import '../features/fantasy/ui/create_fantasy_league.dart';
import '../features/fantasy/ui/fantasy_lobby_screen.dart';
import '../features/tippspiel/models/tip_round.dart';
import '../features/tippspiel/providers.dart';
import 'league_screen.dart';
import 'theme.dart';

/// Startbildschirm. Fantasy ist der Hauptfokus und steht oben; das
/// Tippspiel folgt als zweiter Bereich darunter.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final configured = AppConfig.isSupabaseConfigured;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const _MatchUpTitle(),
        actions: [
          // Gemeinsamer Beitreten-Knopf für alle Spielmodi (Fantasy + Tippspiel),
          // rechts in der Kopfzeile.
          if (configured && user != null)
            TextButton.icon(
              icon: const Icon(Icons.group_add_outlined),
              label: const Text('Beitreten'),
              onPressed: () => joinAnyFlow(context, ref),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myFantasyLeaguesProvider);
          ref.invalidate(myRoundsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(12),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (!configured)
              const _InfoCard(
                'Fantasy & Ligen brauchen eine Server-Verbindung. Starte die '
                'App über ./run_dev.sh (siehe README).',
              )
            else ...[
              const _WelcomeHeader(),
              const SizedBox(height: 16),
              ..._fantasySection(context, ref),
              const SizedBox(height: 24),
              ..._tippspielSection(context, ref),
            ],
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Fantasy (Hauptbereich)
  // ------------------------------------------------------------------
  List<Widget> _fantasySection(BuildContext context, WidgetRef ref) {
    final leagues = ref.watch(myFantasyLeaguesProvider);
    return [
      Row(
        children: [
          Icon(Icons.sports_soccer,
              color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text('Fantasy',
              style: Theme.of(context).textTheme.headlineSmall),
        ],
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 2, 4, 12),
        child: Text(
          'Drafte echte Spieler und sammle Punkte nach ihrer Leistung.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
      Row(
        children: [
          Expanded(
            child: _ModeHero(
              icon: Icons.calendar_today,
              title: 'Fantasy Liga',
              subtitle: 'Eine Saison · Draft',
              onTap: () => createFantasyLeagueFlow(context, FantasyMode.liga),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ModeHero(
              icon: Icons.auto_awesome,
              title: 'Dynasty',
              subtitle: 'Kader über Jahre · U20-Draft',
              onTap: () =>
                  createFantasyLeagueFlow(context, FantasyMode.dynasty),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      leagues.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) =>
            _InfoCard('Fantasy-Ligen konnten nicht geladen werden: $e'),
        data: (list) => Column(
          children: [
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Noch keine Fantasy-Liga — erstelle oben eine Liga oder '
                  'Dynasty.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            for (final league in list) _FantasyLeagueCard(league: league),
          ],
        ),
      ),
    ];
  }

  // ------------------------------------------------------------------
  // Tippspiel (zweiter Bereich)
  // ------------------------------------------------------------------
  List<Widget> _tippspielSection(BuildContext context, WidgetRef ref) {
    final rounds = ref.watch(myRoundsProvider);
    return [
      _sectionHeader(context, 'Tippspiel'),
      rounds.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => _InfoCard('Tipprunden konnten nicht geladen werden: $e'),
        data: (list) => Column(
          children: [
            for (final round in list) _TipRoundCard(round: round),
          ],
        ),
      ),
      const SizedBox(height: 4),
      OutlinedButton.icon(
        icon: const Icon(Icons.add),
        label: const Text('Tipprunde erstellen'),
        onPressed: () => createRoundFlow(context, ref),
      ),
    ];
  }

  Widget _sectionHeader(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      );
}

/// Persönliche Begrüßung oben auf dem Home-Tab.
class _WelcomeHeader extends ConsumerWidget {
  const _WelcomeHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(currentUsernameProvider).valueOrNull;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name == null ? 'Willkommen 👋' : 'Hallo, $name 👋',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            'Deine Ligen & Tipprunden auf einen Blick.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ModeHero extends StatelessWidget {
  const _ModeHero({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      color: scheme.primary.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.4)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 14),
          child: Column(
            children: [
              Icon(icon, size: 34, color: scheme.primary),
              const SizedBox(height: 10),
              Text(title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

class _FantasyLeagueCard extends StatelessWidget {
  const _FantasyLeagueCard({required this.league});

  final FantasyLeague league;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: scheme.primary.withValues(alpha: 0.15),
          child: Icon(
            league.mode == FantasyMode.dynasty
                ? Icons.auto_awesome
                : Icons.calendar_today,
            color: scheme.primary,
            size: 20,
          ),
        ),
        title: Text(league.name),
        subtitle: Text(
            '${league.mode.label} · ${league.draftStatus == DraftStatus.setup ? 'Setup' : league.draftStatus == DraftStatus.drafting ? 'Draft läuft' : 'Saison läuft'}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => FantasyLobbyScreen(league: league))),
      ),
    );
  }
}

class _TipRoundCard extends ConsumerWidget {
  const _TipRoundCard({required this.round});

  final TipRound round;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final league = Leagues.byId(round.leagueId);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: scheme.primary.withValues(alpha: 0.15),
          child: Icon(Icons.emoji_events, color: scheme.primary, size: 20),
        ),
        title: Text(round.name),
        subtitle: Text(league.fixedSeason != null
            ? league.name
            : '${league.name} · Saison ${round.season}/${(round.season + 1) % 100}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          activateRound(ref, round);
          Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => LeagueScreen(round: round)));
        },
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(text),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// MatchUp-Wortmarke für die Kopfzeile: zweifarbiger Doppel-Chevron
// (links Green, rechts Red) + „Match"/„Up". Nativ nachgebaut nach dem
// Marken-SVG (assets/branding/matchup_logo_primary.svg), weil flutter_svg
// dessen Text-Element nicht rendert.
// ---------------------------------------------------------------------
class _MatchUpTitle extends StatelessWidget {
  const _MatchUpTitle();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const _ChevronMark(size: 22),
        const SizedBox(width: 8),
        Text.rich(
          TextSpan(
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: MatchUpColors.snow,
            ),
            children: const [
              TextSpan(text: 'Match'),
              TextSpan(
                  text: 'Up',
                  style: TextStyle(color: MatchUpColors.green)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Der Doppel-Chevron des Logos, exakt nach den SVG-Koordinaten gezeichnet:
/// linke Hälfte Green, rechte Hälfte Red, mittig an den Spitzen geteilt.
class _ChevronMark extends StatelessWidget {
  const _ChevronMark({required this.size});

  /// Höhe in Logischen Pixeln (Breite folgt dem Seitenverhältnis).
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size * _ChevronPainter.refW / _ChevronPainter.refH, size),
      painter: _ChevronPainter(),
    );
  }
}

class _ChevronPainter extends CustomPainter {
  // Referenz-Box um den Chevron (inkl. Platz für die runden Kappen),
  // entnommen aus dem Marken-SVG (viewBox 600×200).
  static const refW = 58.0; // x 164 … 222
  static const refH = 54.4; // y 73.4 … 127.8
  static const _ox = 164.0;
  static const _oy = 73.4;
  static const _centerX = 193.0; // Teilung Green|Red an der Spitze

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / refW;
    final sy = size.height / refH;
    Offset p(double x, double y) => Offset((x - _ox) * sx, (y - _oy) * sy);

    final path = Path()
      // oberer Chevron
      ..moveTo(p(169, 102.4).dx, p(169, 102.4).dy)
      ..lineTo(p(193, 78.4).dx, p(193, 78.4).dy)
      ..lineTo(p(217, 102.4).dx, p(217, 102.4).dy)
      // unterer Chevron
      ..moveTo(p(169, 122.8).dx, p(169, 122.8).dy)
      ..lineTo(p(193, 98.8).dx, p(193, 98.8).dy)
      ..lineTo(p(217, 122.8).dx, p(217, 122.8).dy);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10.0 * (sx + sy) / 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final centerX = (_centerX - _ox) * sx;
    // Linke Hälfte grün.
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, centerX, size.height));
    canvas.drawPath(path, paint..color = MatchUpColors.green);
    canvas.restore();
    // Rechte Hälfte rot.
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(centerX, 0, size.width - centerX, size.height));
    canvas.drawPath(path, paint..color = MatchUpColors.red);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------
// Tippspiel: Tipprunde erstellen / beitreten
// ---------------------------------------------------------------------

Future<void> createRoundFlow(BuildContext context, WidgetRef ref) async {
  final result = await showDialog<(String, LeagueInfo)>(
    context: context,
    builder: (_) => const _CreateRoundDialog(),
  );
  if (result == null) return;
  final (name, league) = result;
  try {
    final round = await ref.read(tipRoundRepositoryProvider).createRound(
          name: name,
          league: league,
          season: league.seasonFor(DateTime.now()),
        );
    ref.invalidate(myRoundsProvider);
    activateRound(ref, round);
    if (!context.mounted) return;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => LeagueScreen(round: round)));
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tipprunde konnte nicht erstellt werden: $e')));
  }
}

/// Gemeinsamer Beitreten-Flow für alle Spielmodi: Ein Einladungscode kann zu
/// einer Fantasy-Liga oder einer Tipprunde gehören. Wir probieren zuerst
/// Fantasy, fällt der Code dort als unbekannt durch, dann das Tippspiel.
Future<void> joinAnyFlow(BuildContext context, WidgetRef ref) async {
  final controller = TextEditingController();
  final code = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Beitreten'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Gib den Einladungscode ein – für eine Fantasy-Liga '
              'oder eine Tipprunde.'),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Einladungscode',
              contentPadding: EdgeInsets.symmetric(horizontal: 12),
            ),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: const Text('Beitreten'),
        ),
      ],
    ),
  );
  if (code == null || code.trim().isEmpty) return;
  final trimmed = code.trim();

  // 1) Als Fantasy-Liga versuchen.
  try {
    final league =
        await ref.read(fantasyLeagueRepositoryProvider).joinLeague(trimmed);
    ref.invalidate(myFantasyLeaguesProvider);
    if (!context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => FantasyLobbyScreen(league: league)));
    return;
  } catch (e) {
    final msg = e.toString();
    if (!msg.contains('Ungültiger Einladungscode')) {
      // Der Code gehört zu einer Fantasy-Liga, der Beitritt scheiterte aber
      // aus einem anderen Grund (z. B. Draft bereits begonnen).
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg.contains('bereits begonnen')
            ? 'Der Draft dieser Liga hat bereits begonnen.'
            : 'Beitritt fehlgeschlagen: $e'),
      ));
      return;
    }
    // Sonst: kein Fantasy-Code -> als Tipprunde weiterversuchen.
  }

  // 2) Als Tipprunde versuchen.
  try {
    final round = await ref.read(tipRoundRepositoryProvider).joinRound(trimmed);
    ref.invalidate(myRoundsProvider);
    activateRound(ref, round);
    if (!context.mounted) return;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => LeagueScreen(round: round)));
  } catch (e) {
    if (!context.mounted) return;
    final msg = e.toString();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg.contains('Ungültiger Einladungscode')
          ? 'Dieser Code passt zu keiner Fantasy-Liga und keiner Tipprunde.'
          : 'Beitritt fehlgeschlagen: $e'),
    ));
  }
}

class _CreateRoundDialog extends StatefulWidget {
  const _CreateRoundDialog();

  @override
  State<_CreateRoundDialog> createState() => _CreateRoundDialogState();
}

class _CreateRoundDialogState extends State<_CreateRoundDialog> {
  final _name = TextEditingController();
  LeagueInfo _league = Leagues.all.first;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (_name.text.trim().length < 3) return;
    Navigator.of(context).pop((_name.text.trim(), _league));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Neue Tipprunde'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Name der Tipprunde',
              contentPadding: EdgeInsets.symmetric(horizontal: 12),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<LeagueInfo>(
            initialValue: _league,
            decoration: const InputDecoration(
              labelText: 'Wettbewerb',
              contentPadding: EdgeInsets.symmetric(horizontal: 12),
            ),
            items: [
              for (final league in Leagues.all)
                DropdownMenuItem(value: league, child: Text(league.name)),
            ],
            onChanged: (league) => setState(() => _league = league ?? _league),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Erstellen')),
      ],
    );
  }
}
