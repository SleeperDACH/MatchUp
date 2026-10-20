import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/widgets/info_knopf.dart';
import '../../../app/widgets/skelett.dart';
import '../push_einstellungen.dart';
import '../live_abos.dart';
import 'live_abos_screen.dart';
import 'tipp_zeiten_screen.dart';

/// **Benachrichtigungen in zwei Ebenen** (18.10.2026, auf Ansage): Oben die
/// vier Bereiche — Fantasy, Tippspiel, Live, Allgemein (Migration 0131) — als
/// Zeilen mit dem Stand („3 von 4 an"), dahinter je ein eigener Schirm mit den
/// Schaltern ([PushBereichScreen]). Vorher standen alle Schalter auf einer
/// langen Seite untereinander.
///
/// **Der Schirm schaltet nicht die Berechtigung**, sondern nur, was die App
/// verschickt. Ob das Gerät überhaupt anzeigt, steht hinter dem ⓘ.
class PushEinstellungenScreen extends ConsumerWidget {
  const PushEinstellungenScreen({super.key});

  static IconData symbol(PushBereich b) => switch (b) {
        PushBereich.fantasy => Icons.sports_soccer_outlined,
        PushBereich.tippspiel => Icons.edit_note_outlined,
        PushBereich.live => Icons.bolt_outlined,
        PushBereich.allgemein => Icons.notifications_none_outlined,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final geladen = ref.watch(pushEinstellungenProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Benachrichtigungen'),
        actions: const [
          InfoKnopf(
            titel: 'Systemeinstellungen',
            text: 'Ob dein Gerät Benachrichtigungen überhaupt anzeigt, '
                'entscheidest du in den Systemeinstellungen. Hier legst du '
                'fest, wofür MatchUp sie schickt.',
          ),
        ],
      ),
      body: geladen.when(
        loading: () => const Skelett(),
        error: (e, _) => _Fehler(e),
        data: (stand) => ListView(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 96),
          children: [
            for (final (i, b) in PushBereich.values.indexed) ...[
              if (i > 0)
                Divider(
                    height: 1,
                    indent: 56,
                    color: scheme.onSurface.withValues(alpha: 0.07)),
              _BereichZeile(bereich: b, stand: stand),
            ],
          ],
        ),
      ),
    );
  }
}

/// Eine Zeile der Übersicht: Symbol, Bereich, wie viel davon an ist.
class _BereichZeile extends StatelessWidget {
  const _BereichZeile({required this.bereich, required this.stand});

  final PushBereich bereich;
  final PushEinstellungen stand;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sorten = PushKategorie.imBereich(bereich);
    final an = sorten.where((k) => stand.an(k.schluessel)).length;
    // „Alle an" / „Aus" sagen mehr als „4 von 4" — die Zahl nur dazwischen.
    final zusammenfassung = an == sorten.length
        ? 'Alle an'
        : an == 0
            ? 'Aus'
            : '$an von ${sorten.length} an';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: Icon(PushEinstellungenScreen.symbol(bereich),
          color: scheme.onSurfaceVariant),
      title: Text(bereich.titel,
          style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(zusammenfassung),
      trailing:
          Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PushBereichScreen(bereich: bereich),
      )),
    );
  }
}

/// Die Schalter eines Bereichs.
///
/// Die Schalter reagieren sofort und speichern danach: Ein Schalter, der erst
/// nach der Serverantwort umspringt, fühlt sich kaputt an. Scheitert das
/// Speichern, springt er zurück und sagt, warum. Gespeichert wird der ganze
/// Stand, nicht nur dieser Bereich — die Übersicht liest denselben Provider
/// und zeigt beim Zurückgehen den neuen Stand.
class PushBereichScreen extends ConsumerStatefulWidget {
  const PushBereichScreen({super.key, required this.bereich});

  final PushBereich bereich;

  @override
  ConsumerState<PushBereichScreen> createState() => _PushBereichScreenState();
}

class _PushBereichScreenState extends ConsumerState<PushBereichScreen> {
  PushEinstellungen? _stand;
  bool _speichert = false;

  Future<void> _umschalten(String schluessel, bool wert) async {
    final vorher = _stand ??
        ref.read(pushEinstellungenProvider).valueOrNull ??
        const PushEinstellungen.allesAn();
    final nachher = vorher.kopieMit(schluessel, wert);
    setState(() {
      _stand = nachher;
      _speichert = true;
    });
    try {
      await ref.read(pushEinstellungenRepositoryProvider).speichern(nachher);
      ref.invalidate(pushEinstellungenProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() => _stand = vorher);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Konnte nicht gespeichert werden: $e')));
    } finally {
      if (mounted) setState(() => _speichert = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final geladen = ref.watch(pushEinstellungenProvider);
    final b = widget.bereich;

    return Scaffold(
      appBar: AppBar(title: Text(b.titel)),
      body: geladen.when(
        // Beim Nachladen nach dem Speichern liegt der alte Wert vor — der
        // Schirm bleibt dann stehen (`skipLoadingOnRefresh`).
        loading: () => const Skelett(),
        error: (e, _) => _Fehler(e),
        data: (vomServer) {
          final stand = _stand ?? vomServer;
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            children: [
              // **Für welche Vereine** (20.10.2026, Migration 0142): Favoriten
              // melden von selbst, dazu einzelne Vereine oder ganze Ligen.
              if (b == PushBereich.live) ...[
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  leading: Icon(Icons.shield_outlined,
                      color: scheme.onSurfaceVariant),
                  title: const Text('Vereine & Ligen',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                      ref.watch(liveAbosProvider).valueOrNull?.zusammenfassung ??
                          'Favoriten und Abos'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const LiveAbosScreen())),
                ),
                Divider(
                    height: 1,
                    color: scheme.onSurface.withValues(alpha: 0.07)),
              ],
              for (final (i, k) in PushKategorie.imBereich(b).indexed) ...[
                if (i > 0)
                  Divider(
                      height: 1,
                      color: scheme.onSurface.withValues(alpha: 0.07)),
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  value: stand.an(k.schluessel),
                  onChanged:
                      _speichert ? null : (v) => _umschalten(k.schluessel, v),
                  title: Text(k.name,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(k.hinweis),
                ),
                // **Wann erinnert wird, stellt man selbst ein**
                // (17.10.2026) — nur sichtbar, solange die Erinnerung an ist.
                if (k.schluessel == 'tipps' && stand.an('tipps'))
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    title: const Text('Individuell einstellen'),
                    subtitle: Text(
                        PushEinstellungen.zeitenText(stand.tippZeitenWirksam)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final neu = await Navigator.of(context)
                          .push<PushEinstellungen>(MaterialPageRoute(
                        builder: (_) => TippZeitenScreen(stand: stand),
                      ));
                      if (neu != null && mounted) {
                        setState(() => _stand = neu);
                      }
                    },
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Fehler extends StatelessWidget {
  const _Fehler(this.fehler);

  final Object fehler;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Einstellungen konnten nicht geladen werden.\n$fehler',
              textAlign: TextAlign.center),
        ),
      );
}
