import 'package:flutter/material.dart';

/// Ein Abschnitt in einem Formular oder einer Einstellungsliste: kleine
/// Überschrift in Versalien, optional ein erklärender Satz, darunter der
/// Inhalt in einer abgesetzten Fläche.
///
/// Liegt im Core, weil ihn die Einstellungen einer Tipprunde und die beiden
/// Erstellen-Formulare gleichermaßen benutzen. Als Kopie je Screen wären die
/// drei beim nächsten Feinschliff sofort auseinandergelaufen — und ein
/// Formular, dessen Abschnitte anders aussehen als die Einstellungen
/// derselben Sache, wirkt wie zwei verschiedene Apps.
class FormSection extends StatelessWidget {
  /// Freier Inhalt (Felder, Chips, Schalter) mit Innenabstand.
  const FormSection({
    super.key,
    required this.titel,
    required this.kinder,
    this.hinweis,
    this.gefahr = false,
  }) : _alsZeilen = false;

  /// Antippbare Zeilen, durch feine Linien getrennt und ohne Innenabstand —
  /// die Zeilen bringen ihren eigenen mit.
  const FormSection.zeilen({
    super.key,
    required this.titel,
    required this.kinder,
    this.hinweis,
    this.gefahr = false,
  }) : _alsZeilen = true;

  final String titel;

  /// Erklärender Satz unter der Überschrift; `null` = keiner.
  final String? hinweis;

  /// Rot abgesetzt (Löschen, Verlassen).
  final bool gefahr;

  final List<Widget> kinder;

  final bool _alsZeilen;

  @override
  Widget build(BuildContext context) {
    // Leere Abschnitte zeichnen nichts: sonst bliebe eine Überschrift ohne
    // Inhalt stehen, etwa bei einem Mitglied ohne Adminrechte.
    if (kinder.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final farbe = gefahr ? scheme.error : scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            titel.toUpperCase(),
            style: TextStyle(
              color: farbe,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.3,
            ),
          ),
          if (hinweis != null) ...[
            const SizedBox(height: 2),
            Text(
              hinweis!,
              style: TextStyle(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
                  fontSize: 12.5,
                  height: 1.3),
            ),
          ],
          const SizedBox(height: 8),
          // Kein Kasten: Der Inhalt steht auf dem Seitengrund, eine feine
          // Linie schließt den Abschnitt ab. Die früheren gefüllten Flächen
          // machten aus jedem Formular eine Reihe grauer Kisten — viel Rand,
          // wenig Inhalt.
          for (var i = 0; i < kinder.length; i++) ...[
            if (i > 0 && _alsZeilen)
              Divider(
                  height: 1,
                  indent: 34,
                  color: scheme.outlineVariant.withValues(alpha: 0.5)),
            kinder[i],
          ],
          const SizedBox(height: 10),
          Divider(
              height: 1,
              color: scheme.outlineVariant
                  .withValues(alpha: gefahr ? 0.0 : 0.45)),
        ],
      ),
    );
  }
}

/// Fehlerhinweis unter einem Formular — als Kasten in der Fehlerfarbe, nicht
/// als roter Satz zwischen anderem Text, wo er leicht übersehen wird.
class FormError extends StatelessWidget {
  const FormError({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 20, color: scheme.error),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: scheme.error))),
        ],
      ),
    );
  }
}

/// Fester Aktionsbalken am unteren Rand eines Formulars.
///
/// Der Knopf stand vorher am Ende der Liste. Bei der Tipprunde liegt dazwischen
/// der ganze Wertungs-Editor — wer oben den Namen tippte, sah nicht, dass es
/// überhaupt weitergeht.
class FormActionBar extends StatelessWidget {
  const FormActionBar({
    super.key,
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
            top: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.7))),
      ),
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: SizedBox(
          height: 50,
          child: FilledButton.icon(
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: Text(label),
            onPressed: onPressed,
          ),
        ),
      ),
    );
  }
}
