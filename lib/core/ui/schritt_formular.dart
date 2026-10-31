import 'package:flutter/material.dart';

import '../../app/typografie.dart';
import '../../app/widgets/mit_ladekreis.dart';
import 'form_section.dart';

/// Eine Seite im [SchrittFormular]: Titel für die Anzeige oben, der Inhalt,
/// und optional eine Prüfung, die vor „Weiter" läuft (Fehlertext oder
/// `null`).
class Schritt {
  const Schritt({required this.titel, required this.inhalt, this.pruefe});

  final String titel;
  final List<Widget> inhalt;
  final String? Function()? pruefe;
}

/// **Anlegen in Schritten** (29.10.2026, auf Ansage nach Punkt 4: „Die Nutzer
/// müssen alles sofort sehen, sonst übersehen sie Funktionen … erst Name und
/// Nutzer, dann Weiter, auf 3–4 Seiten thematisch sortiert, vor und zurück,
/// und man erkennt, auf welcher man ist").
///
/// Ersetzt „Weitere Einstellungen" (zugeklappt) beim Anlegen: Jede
/// Einstellung steht offen da, nur verteilt.
///
/// - **Oben** eine Leiste aus Segmenten (erledigt und aktuell hell), darunter
///   „Schritt 2 von 4" und der Titel der Seite. Ein Tipp auf ein Segment
///   springt zu einer schon besuchten Seite.
/// - **Unten** „Zurück" und „Weiter", auf der letzten Seite [abschluss].
/// - **Zurück-Geste und Pfeil oben links** gehen eine Seite zurück, erst auf
///   der ersten verlassen sie den Schirm.
/// - Die Seiten bleiben am Leben (`IndexedStack`), Eingaben gehen beim
///   Blättern nicht verloren.
class SchrittFormular extends StatefulWidget {
  const SchrittFormular({
    super.key,
    required this.titel,
    required this.schritte,
    required this.abschluss,
    required this.onAbschluss,
    this.busy = false,
    this.fehler,
    this.aktionen,
  }) : assert(schritte.length >= 2);

  final String titel;
  final List<Schritt> schritte;
  final String abschluss;
  final VoidCallback onAbschluss;
  final bool busy;

  /// Fehler von außen (z. B. „Liga konnte nicht erstellt werden").
  final String? fehler;
  final List<Widget>? aktionen;

  @override
  State<SchrittFormular> createState() => SchrittFormularState();
}

class SchrittFormularState extends State<SchrittFormular> {
  int _seite = 0;
  int _weitesteSeite = 0;
  String? _pruefFehler;

  /// Aktuelle Seite (0-basiert) — für Tests.
  int get seite => _seite;

  bool get _letzte => _seite == widget.schritte.length - 1;

  void _gehe(int ziel) {
    FocusScope.of(context).unfocus();
    setState(() {
      _seite = ziel;
      if (ziel > _weitesteSeite) _weitesteSeite = ziel;
      _pruefFehler = null;
    });
  }

  void _weiter() {
    final f = widget.schritte[_seite].pruefe?.call();
    if (f != null) {
      setState(() => _pruefFehler = f);
      return;
    }
    if (!_letzte) {
      _gehe(_seite + 1);
      return;
    }
    // Vor dem Anlegen alle Seiten prüfen — wer zurückgesprungen ist und dort
    // etwas geändert hat, landet auf der Seite mit dem Fehler.
    for (var i = 0; i < widget.schritte.length; i++) {
      final fehler = widget.schritte[i].pruefe?.call();
      if (fehler != null) {
        _gehe(i);
        setState(() => _pruefFehler = fehler);
        return;
      }
    }
    widget.onAbschluss();
  }

  @override
  Widget build(BuildContext context) {
    final fehler = _pruefFehler ?? widget.fehler;
    return PopScope(
      canPop: _seite == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _seite > 0) _gehe(_seite - 1);
      },
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Text(widget.titel),
          actions: widget.aktionen,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(78),
            child: _Kopf(
              schritte: widget.schritte,
              seite: _seite,
              weiteste: _weitesteSeite,
              onTippe: (i) =>
                  i <= _weitesteSeite && i != _seite ? _gehe(i) : null,
            ),
          ),
        ),
        body: IndexedStack(
          index: _seite,
          children: [
            for (final s in widget.schritte)
              ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: s.inhalt,
              ),
          ],
        ),
        bottomNavigationBar: _Fuss(
          zurueck: _seite > 0 ? () => _gehe(_seite - 1) : null,
          weiterLabel: _letzte ? widget.abschluss : 'Weiter',
          onWeiter: widget.busy ? null : _weiter,
          busy: widget.busy && _letzte,
          fehler: fehler,
        ),
      ),
    );
  }
}

class _Kopf extends StatelessWidget {
  const _Kopf({
    required this.schritte,
    required this.seite,
    required this.weiteste,
    required this.onTippe,
  });

  final List<Schritt> schritte;
  final int seite;
  final int weiteste;
  final void Function(int) onTippe;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 0; i < schritte.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: Semantics(
                    button: i <= weiteste && i != seite,
                    selected: i == seite,
                    label: 'Schritt ${i + 1}: ${schritte[i].titel}',
                    excludeSemantics: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onTippe(i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          height: 4,
                          decoration: BoxDecoration(
                            color: i <= seite
                                ? scheme.onSurface
                                : i <= weiteste
                                ? scheme.onSurface.withValues(alpha: 0.35)
                                : Theme.of(context).dividerColor,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  schritte[seite].titel.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: Schrift.titel + 3,
                    fontWeight: Schrift.ueberschriftGewicht,
                    fontStyle: Schrift.ueberschriftStil,
                  ),
                ),
              ),
              Text(
                'Schritt ${seite + 1} von ${schritte.length}',
                style: TextStyle(
                  fontSize: Schrift.label + 1,
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Fuss extends StatelessWidget {
  const _Fuss({
    required this.zurueck,
    required this.weiterLabel,
    required this.onWeiter,
    required this.busy,
    required this.fehler,
  });

  final VoidCallback? zurueck;
  final String weiterLabel;
  final VoidCallback? onWeiter;
  final bool busy;
  final String? fehler;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (fehler != null) ...[
              FormError(text: fehler!),
              const SizedBox(height: 10),
            ],
            SizedBox(
              height: 50,
              child: Row(
                children: [
                  if (zurueck != null) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: zurueck,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                        ),
                        child: const Text('Zurück'),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: onWeiter,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                      ),
                      child: MitLadekreis(
                        laedt: busy,
                        child: Text(weiterLabel),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
