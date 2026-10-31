import 'package:flutter/material.dart';

import 'glossar.dart';
import 'typografie.dart';
import 'widgets/kapitelmarke.dart';

/// **Glossar im Profil** (29.10.2026, Punkt 7 der Nutzer-Analyse).
///
/// Oben ein Suchfeld, darunter die Begriffe nach Bereich unter
/// Kapitelmarken — Begriff fett, darunter zwei, drei Sätze, Haarlinien
/// dazwischen. Kein Aufklappen: Die Texte sind kurz, und wer etwas sucht,
/// soll es lesen, ohne zu tippen.
class GlossarScreen extends StatefulWidget {
  const GlossarScreen({super.key});

  @override
  State<GlossarScreen> createState() => _GlossarScreenState();
}

class _GlossarScreenState extends State<GlossarScreen> {
  final _suche = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _suche.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final treffer = glossarSuche(_q);
    final kinder = <Widget>[];
    for (final bereich in GlossarBereich.values) {
      final eintraege = [
        for (final g in treffer)
          if (g.bereich == bereich) g,
      ];
      if (eintraege.isEmpty) continue;
      kinder.add(Kapitelmarke(bereich.titel));
      for (var i = 0; i < eintraege.length; i++) {
        kinder.add(_Begriff(eintrag: eintraege[i], trenner: i > 0));
      }
    }

    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('Glossar')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          24 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        children: [
          TextField(
            controller: _suche,
            onChanged: (v) => setState(() => _q = v),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Begriff suchen',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _q.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Suche leeren',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() {
                        _suche.clear();
                        _q = '';
                      }),
                    ),
            ),
          ),
          ...kinder,
          if (treffer.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 48),
              child: Text(
                'Zu „${_q.trim()}“ steht hier nichts.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

class _Begriff extends StatelessWidget {
  const _Begriff({required this.eintrag, required this.trenner});

  final GlossarEintrag eintrag;
  final bool trenner;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: trenner
            ? Border(top: BorderSide(color: Theme.of(context).dividerColor))
            : null,
      ),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eintrag.e.titel,
            style: const TextStyle(
              fontSize: Schrift.titel,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            eintrag.e.text,
            style: TextStyle(
              fontSize: Schrift.text,
              height: 1.4,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
