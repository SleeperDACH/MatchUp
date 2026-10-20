import 'package:flutter/material.dart';

import '../../app/typografie.dart';

/// Ein Eingabefeld in einem [eingabeBlatt].
class EingabeFeld {
  const EingabeFeld({
    required this.label,
    this.start = '',
    this.verdeckt = false,
    this.tastatur,
    this.maxLaenge,
    this.grossschreibung = TextCapitalization.none,
    this.autokorrektur = true,
  });

  final String label;

  /// Vorbelegung.
  final String start;

  /// Passwortfeld.
  final bool verdeckt;
  final TextInputType? tastatur;
  final int? maxLaenge;
  final TextCapitalization grossschreibung;
  final bool autokorrektur;
}

/// **Eine Eingabe — als Blatt, nicht als Kasten** (20.10.2026). Die
/// Gegenstücke zu [rueckfrage] für alles, was ein Textfeld braucht: Liga-Name,
/// Teamname, Profilname und E-Mail, Passwort ändern und vergessen, Beitreten
/// mit Code. Dieselbe Form: Titel schräg in Versalien, höchstens ein Satz,
/// darunter die Felder, unten die Knöpfe groß in voller Breite.
///
/// [pruefe] bekommt die getrimmten Werte (Passwörter ungetrimmt) und liefert
/// einen Fehlertext oder `null`; der Fehler steht dann rot über den Knöpfen,
/// und das Blatt bleibt offen. Liefert die Werte in Feldreihenfolge oder
/// `null` bei Abbruch.
Future<List<String>?> eingabeBlatt(
  BuildContext context, {
  required String titel,
  String? text,
  required List<EingabeFeld> felder,
  required String ja,
  String? Function(List<String> werte)? pruefe,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    builder: (_) => EingabeBlatt(
      titel: titel,
      text: text,
      felder: felder,
      ja: ja,
      pruefe: pruefe,
    ),
  );
}

/// Ein Feld, ein Wert — die häufige Form von [eingabeBlatt].
Future<String?> eingabe(
  BuildContext context, {
  required String titel,
  String? text,
  required EingabeFeld feld,
  required String ja,
  String? Function(String wert)? pruefe,
}) async {
  final werte = await eingabeBlatt(
    context,
    titel: titel,
    text: text,
    felder: [feld],
    ja: ja,
    pruefe: pruefe == null ? null : (w) => pruefe(w.first),
  );
  return werte?.first;
}

/// Der Inhalt von [eingabeBlatt] — öffentlich, damit Vorschauen ihn zeigen
/// können. Eigenes StatefulWidget, damit die Controller erst nach der
/// Ausblend-Animation entsorgt werden.
class EingabeBlatt extends StatefulWidget {
  const EingabeBlatt({
    super.key,
    required this.titel,
    required this.felder,
    required this.ja,
    this.text,
    this.pruefe,
  });

  final String titel;
  final String? text;
  final List<EingabeFeld> felder;
  final String ja;
  final String? Function(List<String> werte)? pruefe;

  @override
  State<EingabeBlatt> createState() => _EingabeBlattState();
}

class _EingabeBlattState extends State<EingabeBlatt> {
  late final List<TextEditingController> _ctrl = [
    for (final f in widget.felder) TextEditingController(text: f.start),
  ];
  String? _fehler;

  @override
  void dispose() {
    for (final c in _ctrl) {
      c.dispose();
    }
    super.dispose();
  }

  void _absenden() {
    final werte = [
      for (final (i, f) in widget.felder.indexed)
        f.verdeckt ? _ctrl[i].text : _ctrl[i].text.trim(),
    ];
    final fehler = widget.pruefe?.call(werte);
    if (fehler != null) {
      setState(() => _fehler = fehler);
      return;
    }
    Navigator.of(context).pop(werte);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const hoch = Size.fromHeight(50);
    final letztes = widget.felder.length - 1;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 24, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.titel.toUpperCase(),
                style: const TextStyle(
                  fontSize: Schrift.gross,
                  fontWeight: Schrift.ueberschriftGewicht,
                  fontStyle: Schrift.ueberschriftStil,
                  height: 1.15,
                ),
              ),
              if (widget.text != null) ...[
                const SizedBox(height: 10),
                Text(
                  widget.text!,
                  style: TextStyle(
                    fontSize: Schrift.text,
                    height: 1.35,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              for (final (i, f) in widget.felder.indexed) ...[
                if (i > 0) const SizedBox(height: 12),
                TextField(
                  controller: _ctrl[i],
                  autofocus: i == 0,
                  obscureText: f.verdeckt,
                  keyboardType: f.tastatur,
                  maxLength: f.maxLaenge,
                  textCapitalization: f.grossschreibung,
                  autocorrect: f.autokorrektur && !f.verdeckt,
                  textInputAction:
                      i == letztes ? TextInputAction.done : TextInputAction.next,
                  decoration: InputDecoration(labelText: f.label),
                  onChanged: (_) {
                    if (_fehler != null) setState(() => _fehler = null);
                  },
                  onSubmitted: i == letztes ? (_) => _absenden() : null,
                ),
              ],
              if (_fehler != null) ...[
                const SizedBox(height: 12),
                Text(
                  _fehler!,
                  style: TextStyle(fontSize: Schrift.text, color: scheme.error),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _absenden,
                style: FilledButton.styleFrom(minimumSize: hoch),
                child: Text(widget.ja),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  minimumSize: hoch,
                  foregroundColor: scheme.onSurfaceVariant,
                ),
                child: const Text('Abbrechen'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
