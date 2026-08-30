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
/// **Die Leiste nimmt die volle Breite ein**, jeder Reiter denselben Anteil.
/// Vorher standen die Wörter links zusammengedrängt in einer waagerecht
/// scrollbaren Zeile, und rechts blieb Leere — die Leiste sah aus wie ein
/// angefangener Satz. Damit ist auch das Scrollen weg: Passt ein Wort nicht,
/// schrumpft es (`FittedBox`), wie überall sonst in dieser App.
///
/// **Die Marke unter dem aktiven Wort** ist kurz und gerundet, kein Rahmen über
/// die volle Wortbreite, und sie wächst hinein statt umzuspringen. Darunter
/// liegen Luft und eine Haarlinie über die volle Breite — dieselbe Trennung wie
/// bei den Kapitelmarken. Ohne die klebte der Strich im `AppBar.bottom` an der
/// ersten Karte darunter und sah aus, als gehöre er zu ihr.
///
/// Braucht einen [DefaultTabController] darüber — wie eine `TabBar` auch.
class LeiseReiter extends StatelessWidget implements PreferredSizeWidget {
  const LeiseReiter({
    super.key,
    required this.titel,
    this.horizontal = 14,
    this.mitLinie = true,
    this.zeichen = const {},
  });

  final List<String> titel;

  /// Seitlicher Abstand; im `AppBar.bottom` sitzt die Leiste weiter außen als
  /// mitten in einem Schirm.
  final double horizontal;

  /// Haarlinie am unteren Rand — trennt die Leiste vom Inhalt darunter.
  final bool mitLinie;

  /// Reiter, die statt des Wortes ein **Zeichen** tragen: Index → Bauplan.
  ///
  /// Der Bauplan bekommt gesagt, ob sein Reiter aktiv ist und welche Farbe der
  /// Text an dieser Stelle hätte — so kann ein Logo im Ruhezustand mitgedämpft
  /// werden, ohne dass die Leiste die Marke kennen muss.
  ///
  /// **Der Text aus [titel] bleibt trotzdem stehen** — als Beschriftung für die
  /// Vorlesehilfe. Ein Logo ohne Namen ist für VoiceOver eine stumme
  /// Schaltfläche.
  final Map<int, Widget Function(bool aktiv, Color farbe)> zeichen;

  /// Breite der Marke unter dem aktiven Reiter.
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
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontal),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < titel.length; i++)
                      Expanded(
                        child: _Reiter(
                          text: titel[i],
                          zeichen: zeichen[i],
                          aktiv: controller.index == i,
                          onTap: () => controller.animateTo(i),
                          scheme: scheme,
                        ),
                      ),
                  ],
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
    this.zeichen,
  });

  final String text;
  final bool aktiv;
  final VoidCallback onTap;
  final ColorScheme scheme;
  final Widget Function(bool aktiv, Color farbe)? zeichen;

  @override
  Widget build(BuildContext context) {
    final farbe = aktiv
        ? scheme.onSurface
        : scheme.onSurfaceVariant.withValues(alpha: 0.65);
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
            SizedBox(
              // Feste Zeilenhöhe, damit ein Zeichen die Marke nicht gegen die
              // Wörter der Nachbarreiter verschiebt.
              height: 22,
              child: Center(
                child: zeichen != null
                    ? zeichen!(aktiv, farbe)
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 160),
                          curve: Curves.easeOut,
                          // **Aus dem Theme abgeleitet, nicht neu gebaut.**
                          // `AnimatedDefaultTextStyle` *ersetzt* den Stil, es
                          // ergänzt ihn nicht — ein blankes `TextStyle`
                          // verliert damit die `fontFamily`, und die Reiter
                          // fielen stumm auf Roboto zurück statt Barlow
                          // Condensed zu benutzen. Dieselbe Falle wie bei
                          // `ListTileThemeData` in den Fantasy-Einstellungen.
                          style: (Theme.of(context).textTheme.titleSmall ??
                                  const TextStyle())
                              .copyWith(
                            fontSize: 14,
                            // Das Gewicht trägt die Auskunft mit; die Marke
                            // allein wäre bei vier Reitern zu wenig.
                            fontWeight:
                                aktiv ? FontWeight.w800 : FontWeight.w600,
                            color: farbe,
                          ),
                          child: Text(text, maxLines: 1),
                        ),
                      ),
              ),
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
