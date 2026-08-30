import 'package:flutter/material.dart';

import '../theme.dart';

/// Tab-Leiste als Segment-Steuerung: der aktive Reiter sitzt in einer weich
/// gefüllten Pille, die übrigen sind nur gedämpfter Text.
///
/// Ersetzt die Material-Standardleiste mit Unterstrich und Trennlinie. Die
/// wirkte im dunklen MatchUp-Look wie ein Fremdkörper: harte Linie über die
/// volle Breite, dazu ein zweiter Strich als Divider.
///
/// Nutzt weiterhin [TabBar] und damit den [DefaultTabController] — Wischen,
/// Tastatur und Barrierefreiheit bleiben unverändert; getauscht ist nur die
/// Optik über `indicator`.
class SegmentedTabBar extends StatelessWidget implements PreferredSizeWidget {
  const SegmentedTabBar({
    super.key,
    required this.tabs,
    this.scrollable,
    this.controller,
  });

  final List<Tab> tabs;

  /// Ohne Angabe: ab vier Reitern scrollbar, darunter gleichmäßig verteilt.
  final bool? scrollable;

  /// Nur nötig, wo der Screen den Controller selbst hält (Draft-Raum);
  /// sonst greift der [DefaultTabController].
  final TabController? controller;

  /// Ohne Angabe wird gescrollt, sobald die Reiter nicht mehr nebeneinander
  /// passen. Reiter mit Symbol tragen kurze Wörter untereinander und brauchen
  /// weniger Breite — dort passen vier, bei reinem Text nur drei.
  bool get _scrollable =>
      scrollable ?? (_hasIcons ? tabs.length > 4 : tabs.length > 3);

  /// Reiter mit Symbol **und** Text brauchen zwei Zeilen Platz.
  bool get _hasIcons => tabs.any((t) => t.icon != null);

  @override
  Size get preferredSize => Size.fromHeight(_hasIcons ? 76 : 52);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: Theme.of(context).appBarTheme.backgroundColor,
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: TabBar(
        controller: controller,
        isScrollable: _scrollable,
        // Ohne das setzt Material die Reiter in einer Scroll-Leiste an den
        // linken Rand mit Extra-Einzug; so beginnen sie bündig.
        tabAlignment: _scrollable ? TabAlignment.start : TabAlignment.fill,
        // Der Unterstrich weicht der Pille, die Trennlinie entfällt ganz.
        indicator: BoxDecoration(
          color: MatchUpColors.green.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(11),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorPadding: EdgeInsets.symmetric(vertical: _hasIcons ? 3 : 5),
        dividerColor: Colors.transparent,
        dividerHeight: 0,
        labelColor: MatchUpColors.green,
        unselectedLabelColor: scheme.onSurfaceVariant,
        labelStyle:
            const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        unselectedLabelStyle:
            const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        labelPadding:
            EdgeInsets.symmetric(horizontal: _hasIcons ? 6 : 14),
        // Kein grauer Wisch beim Antippen — die Pille ist Rückmeldung genug.
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        splashFactory: NoSplash.splashFactory,
        tabs: tabs,
      ),
    );
  }
}
