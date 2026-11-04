import '../../core/logic/vereins_kuerzel.dart';

/// **Vereinsnamen überall gleich** (04.11.2026, auf Ansage: „im Tippspiel,
/// Live-Tab und den Vereinsprofilen die Vereinsnamen immer komplett groß und
/// kursiv — die Vereinsnamen müssen überall gleich sein").
///
/// Ein Wort je Verein (`vereinsKurzname`, „Gladbach", „Hamburg") in
/// Versalien. Dazu gehört der Stil ExtraBold kursiv
/// (`Schrift.ueberschriftGewicht` / `Schrift.ueberschriftStil`) — derselbe
/// wie bei Spielernamen und Überschriften. Vorlese-Namen behalten den vollen
/// Namen.
String vereinsName(String voll) => vereinsKurzname(voll).toUpperCase();
