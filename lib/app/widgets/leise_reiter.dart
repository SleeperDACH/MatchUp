import 'package:flutter/material.dart';

/// Reiterleiste als **leise Textumschaltung**.
///
/// Gegenstück zur `SegmentedTabBar`, die ihr aktives Segment in eine grüne
/// Fläche legt. Grün heißt in dieser App „hier läuft etwas" — ein Reiter läuft
/// nicht, und als ganze Zeile Signalfarbe war er auf mehreren Schirmen das
/// lauteste Element. Wo die Reiter nur gliedern (Favoriten, Fantasy-Liga),
/// steht deshalb diese Fassung; wo eine echte Auswahl getroffen wird, bleibt
/// die gefüllte Pille sinnvoll.
///
/// **Die erste Fassung war dafür zu leise**: ein 2 px breiter Rahmenstrich
/// unter dem Wort, über die ganze Wortbreite, hart auf der Unterkante. Drei
/// Dinge sind daraus geworden:
///
///  * **Eine kurze, gerundete Marke** statt eines Rahmens über die volle
///    Wortbreite — sie liest sich als gesetztes Zeichen, nicht als Unterstrich.
///  * **Sie wächst hinein** (`AnimatedContainer`), statt beim Wechsel
///    umzuspringen. Das ist die ganze Bewegung, die die Leiste braucht.
///  * **Sie klebt nicht mehr am Inhalt.** Vorher saß der Strich auf der
///    Unterkante der Leiste, und im `AppBar.bottom` begann direkt darunter die
///    erste Karte — der Strich sah aus, als gehöre er zu ihr. Jetzt liegt
///    darunter Luft und eine Haarlinie über die volle Breite, dieselbe
///    Trennung wie bei den Kapitelmarken im Live- und Favoriten-Tab.
///
/// Braucht einen [DefaultTabController] darüber — wie eine `TabBar` auch.
class LeiseReiter extends StatelessWidget implements PreferredSizeWidget {
  const LeiseReiter({
    super.key,
    required this.titel,
    this.horizontal = 14,
    this.mitLinie = true,
  });

  final List<String> titel;

  /// Seitlicher Abstand; im `AppBar.bottom` sitzt die Leiste weiter außen als
  /// mitten in einem Schirm.
  final double horizontal;

  /// Haarlinie am unteren Rand — trennt die Leiste vom Inhalt darunter.
  final bool mitLinie;

  /// Breite der Marke unter dem aktiven Wort.
  static const _markeBreite = 20.0;

  static const _hoehe = 52.0;

  @override
  Size get preferredSize => const Size.fromHeight(_hoehe);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final controller = DefaultTabController.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => SizedBox(
        height: _hoehe,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.bottomLeft,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: horizontal),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 0; i < titel.length; i++) ...[
                        _Reiter(
                          text: titel[i],
                          aktiv: controller.index == i,
                          onTap: () => controller.animateTo(i),
                          scheme: scheme,
                        ),
                        if (i < titel.length - 1) const SizedBox(width: 20),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            // Luft zwischen Marke und Inhalt — ohne sie klebte der Strich an
            // der ersten Karte darunter.
            const SizedBox(height: 8),
            if (mitLinie)
              Container(height: 1, color: Theme.of(context).dividerColor),
          ],
        ),
      ),
    );
  }
}

class _Reiter extends StatelessWidget {
  const _Reiter({
    required this.text,
    required this.aktiv,
    required this.onTap,
    required this.scheme,
  });

  final String text;
  final bool aktiv;
  final VoidCallback onTap;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: aktiv,
      label: text,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              // **Aus dem Theme abgeleitet, nicht neu gebaut.**
              // `AnimatedDefaultTextStyle` *ersetzt* den Stil, es ergänzt ihn
              // nicht — ein blankes `TextStyle` verliert damit die
              // `fontFamily`, und die Reiter fielen auf Roboto zurück statt
              // Barlow Condensed zu benutzen. In der Vorschau sind sie dabei
              // zu leeren Kästchen geworden; auf dem Gerät wäre es die
              // falsche Schrift gewesen — leiser und schwerer zu bemerken.
              // Dieselbe Falle wie bei `ListTileThemeData` in den
              // Fantasy-Einstellungen.
              style: (Theme.of(context).textTheme.titleSmall ??
                      const TextStyle())
                  .copyWith(
                fontSize: 15,
                // Der Abstand zwischen aktiv und ruhend trägt die Auskunft
                // mit; die Marke allein wäre bei vier Wörtern zu wenig.
                fontWeight: aktiv ? FontWeight.w800 : FontWeight.w600,
                color: aktiv
                    ? scheme.onSurface
                    : scheme.onSurfaceVariant.withValues(alpha: 0.65),
              ),
              child: Text(text),
            ),
            const SizedBox(height: 6),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              height: 3,
              width: aktiv ? LeiseReiter._markeBreite : 0,
              decoration: BoxDecoration(
                color: scheme.onSurface,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
