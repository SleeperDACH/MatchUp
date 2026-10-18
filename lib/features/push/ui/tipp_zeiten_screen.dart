import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/typografie.dart';
import '../../../app/widgets/kapitelmarke.dart';
import '../../../app/widgets/mit_ladekreis.dart';
import '../../../app/widgets/pill_selector.dart';
import '../push_einstellungen.dart';

/// **Wann die Tipp-Erinnerung kommt** — individuell (auf Ansage, 17.10.2026).
///
/// Beliebig viele Zeitpunkte aus 30 Minuten, 1 Stunde und 2, 4 … 24 Stunden
/// vor Anpfiff. Standard sind 2 Stunden und 30 Minuten; wer genau das wählt,
/// speichert `null` und folgt damit auch einem künftig geänderten Standard.
/// Mindestens ein Zeitpunkt muss bleiben — wer gar nicht erinnert werden will,
/// schaltet „Offene Tipps" aus.
class TippZeitenScreen extends ConsumerStatefulWidget {
  const TippZeitenScreen({super.key, required this.stand});

  final PushEinstellungen stand;

  @override
  ConsumerState<TippZeitenScreen> createState() => _TippZeitenScreenState();
}

class _TippZeitenScreenState extends ConsumerState<TippZeitenScreen> {
  late final Set<int> _wahl = {...widget.stand.tippZeitenWirksam};
  bool _speichert = false;

  static String _label(int m) => m < 60 ? '$m Min.' : '${m ~/ 60} Std.';

  bool get _istStandard =>
      _wahl.length == PushEinstellungen.tippZeitenStandard.length &&
      _wahl.containsAll(PushEinstellungen.tippZeitenStandard);

  Future<void> _speichern() async {
    setState(() => _speichert = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final neu =
          widget.stand.mitTippZeiten(_istStandard ? null : _wahl.toList());
      await ref.read(pushEinstellungenRepositoryProvider).speichern(neu);
      ref.invalidate(pushEinstellungenProvider);
      navigator.pop(neu);
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Konnte nicht gespeichert werden: $e')));
    } finally {
      if (mounted) setState(() => _speichert = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final kurz = [for (final m in PushEinstellungen.tippZeitenWahl) if (m <= 60) m];
    final stunden = [
      for (final m in PushEinstellungen.tippZeitenWahl) if (m > 60) m
    ];
    Widget chips(List<int> werte) => Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in werte)
              PillChip(
                label: _label(m),
                selected: _wahl.contains(m),
                onTap: () => setState(() {
                  if (_wahl.contains(m)) {
                    // Mindestens einer bleibt — sonst gäbe es keine
                    // Erinnerung, obwohl der Schalter an ist.
                    if (_wahl.length > 1) _wahl.remove(m);
                  } else {
                    _wahl.add(m);
                  }
                }),
              ),
          ],
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Tipp-Erinnerung')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          Text(
            _wahl.isEmpty
                ? ''
                : 'Du wirst erinnert: ${PushEinstellungen.zeitenText(_wahl.toList())}.',
            style: TextStyle(
              fontSize: Schrift.text,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const Kapitelmarke('Kurz vorher', obenLuft: Abstand.l),
          chips(kurz),
          const Kapitelmarke('Stunden vorher'),
          chips(stunden),
          const SizedBox(height: Abstand.l),
          if (!_istStandard)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() {
                  _wahl
                    ..clear()
                    ..addAll(PushEinstellungen.tippZeitenStandard);
                }),
                child: const Text('Auf Standard zurücksetzen '
                    '(2 Std. und 30 Min.)'),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: _speichert ? null : _speichern,
              child: MitLadekreis(
                  laedt: _speichert, child: const Text('Speichern')),
            ),
          ),
        ),
      ),
    );
  }
}
