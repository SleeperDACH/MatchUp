import 'package:flutter/material.dart';

/// Reiterleiste als **leise Textumschaltung** mit Unterstrich.
///
/// Gegenstück zur `SegmentedTabBar`, die ihr aktives Segment in eine grüne
/// Fläche legt. Grün heißt in dieser App „hier läuft etwas" — ein Reiter läuft
/// nicht, und als ganze Zeile Signalfarbe war er auf mehreren Schirmen das
/// lauteste Element. Wo die Reiter nur gliedern (Favoriten, Fantasy-Liga),
/// steht deshalb diese Fassung; wo eine echte Auswahl getroffen wird, bleibt
/// die gefüllte Pille sinnvoll.
///
/// Braucht einen [DefaultTabController] darüber — wie eine `TabBar` auch.
class LeiseReiter extends StatelessWidget implements PreferredSizeWidget {
  const LeiseReiter({super.key, required this.titel, this.horizontal = 14});

  final List<String> titel;

  /// Seitlicher Abstand; im `AppBar.bottom` sitzt die Leiste weiter außen als
  /// mitten in einem Schirm.
  final double horizontal;

  @override
  Size get preferredSize => const Size.fromHeight(44);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final controller = DefaultTabController.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => SizedBox(
        height: 44,
        child: Align(
          alignment: Alignment.bottomLeft,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: horizontal),
            child: Row(
              children: [
                for (var i = 0; i < titel.length; i++) ...[
                  Semantics(
                    button: true,
                    selected: controller.index == i,
                    label: titel[i],
                    excludeSemantics: true,
                    child: GestureDetector(
                      onTap: () => controller.animateTo(i),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        padding: const EdgeInsets.only(bottom: 8, top: 8),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: controller.index == i
                                  ? scheme.onSurface
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                        child: Text(
                          titel[i],
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: controller.index == i
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: controller.index == i
                                ? scheme.onSurface
                                : scheme.onSurfaceVariant.withValues(
                                    alpha: 0.75,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (i < titel.length - 1) const SizedBox(width: 18),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
