import 'package:flutter/material.dart';
import '../../../app/widgets/skelett.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/widgets/info_knopf.dart';
import '../../../core/ui/form_section.dart';
import '../push_einstellungen.dart';
import 'tipp_zeiten_screen.dart';

/// Ein Schalter je Sorte Benachrichtigung, in vier Blöcken: Fantasy,
/// Tippspiel, Live, Allgemein (Migration 0131).
///
/// **Der Schirm schaltet nicht die Berechtigung**, sondern nur, was die App
/// verschickt. Wer Push im Betriebssystem abgelehnt hat, sieht hier lauter
/// Schalter, die nichts bewirken — deshalb steht der Hinweis darüber und
/// nicht in einer Fußnote.
///
/// Die Schalter reagieren sofort und speichern danach: Ein Schalter, der erst
/// nach der Serverantwort umspringt, fühlt sich kaputt an. Scheitert das
/// Speichern, springt er zurück und sagt, warum.
class PushEinstellungenScreen extends ConsumerStatefulWidget {
  const PushEinstellungenScreen({super.key});

  @override
  ConsumerState<PushEinstellungenScreen> createState() =>
      _PushEinstellungenScreenState();
}

class _PushEinstellungenScreenState
    extends ConsumerState<PushEinstellungenScreen> {
  PushEinstellungen? _stand;
  bool _speichert = false;

  Future<void> _umschalten(String schluessel, bool wert) async {
    final vorher = _stand ?? const PushEinstellungen.allesAn();
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Benachrichtigungen'),
        // Der Satz über die Systemeinstellungen stand als Absatz über der
        // Liste (Design-Ideen Punkt 4).
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
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Einstellungen konnten nicht geladen werden.\n$e',
                textAlign: TextAlign.center),
          ),
        ),
        data: (vomServer) {
          final stand = _stand ?? vomServer;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 96),
            children: [
              for (final b in PushBereich.values) ...[
                FormSection(
                  titel: b.titel,
                  hinweis: b == PushBereich.live
                      ? 'Für die Vereine unter deinen Favoriten.'
                      : null,
                  kinder: [
                    // **Schalter ohne Karte** (Design-Ideen Punkt 1 und 3,
                    // 15.10.2026). Jede Zeile lag in einem eigenen Kasten,
                    // und ein eingeschalteter trug dazu einen grünen Hauch —
                    // bei fast lauter eingeschalteten Sorten ein Schirm aus
                    // grünen Kästen. Den Zustand sagt der Schalter selbst.
                    for (final (i, k)
                        in PushKategorie.imBereich(b).indexed) ...[
                      if (i > 0)
                        Divider(
                            height: 1,
                            color: scheme.onSurface.withValues(alpha: 0.07)),
                      SwitchListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 4),
                        value: stand.an(k.schluessel),
                        onChanged: _speichert
                            ? null
                            : (v) => _umschalten(k.schluessel, v),
                        title: Text(k.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(k.hinweis),
                      ),
                      // **Wann erinnert wird, stellt man selbst ein**
                      // (17.10.2026) — nur sichtbar, solange die Erinnerung
                      // an ist.
                      if (k.schluessel == 'tipps' && stand.an('tipps'))
                        ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          title: const Text('Individuell einstellen'),
                          subtitle: Text(PushEinstellungen.zeitenText(
                              stand.tippZeitenWirksam)),
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
                ),
                const SizedBox(height: 16),
              ],
            ],
          );
        },
      ),
    );
  }
}
