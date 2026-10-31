import 'package:flutter/material.dart';

import '../../../app/typografie.dart';

/// „Nico Schlotterbeck" → (Nico, Schlotterbeck). Der letzte Namensteil ist
/// der Nachname — dieselbe Regel wie auf dem Draft-Board und im Profilkopf.
/// Einteilige Namen haben keinen Vornamen.
({String vorname, String nachname}) namensTeile(String voll) {
  final teile = voll.trim().split(RegExp(r'\s+'));
  if (teile.length < 2) return (vorname: '', nachname: voll.trim());
  return (
    vorname: teile.sublist(0, teile.length - 1).join(' '),
    nachname: teile.last,
  );
}

/// **Der Nachname trägt, der Vorname begleitet** (31.10.2026, auf Ansage:
/// „den Vornamen irgendwie kleiner machen, dafür den Nachnamen größer").
///
/// Eine Zeile, beide in Versalien und kursiv: der Vorname klein, normal und
/// grau, der Nachname groß in ExtraBold — wer einen Spieler sucht, sucht
/// nach dem Nachnamen. Überall dort, wo der volle Name steht (Free Agency,
/// Draft, Spielerwahl, Kaderlisten); wo nur der Nachname steht, bleibt er
/// allein.
class GestufterSpielerName extends StatelessWidget {
  const GestufterSpielerName(
    this.name, {
    super.key,
    this.nachnameGroesse = Schrift.titel,
    this.vornameGroesse = Schrift.label,
    this.farbe,
    this.maxLines = 1,
  });

  final String name;
  final double nachnameGroesse;
  final double vornameGroesse;

  /// Farbe des Nachnamens; `null` erbt (etwa von einem `ListTile`).
  final Color? farbe;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final t = namensTeile(name);
    final leise = Theme.of(context).colorScheme.onSurfaceVariant;
    return Text.rich(
      TextSpan(
        children: [
          if (t.vorname.isNotEmpty)
            TextSpan(
              text: '${t.vorname.toUpperCase()} ',
              style: TextStyle(
                fontSize: vornameGroesse,
                fontWeight: FontWeight.w400,
                fontStyle: Schrift.ueberschriftStil,
                color: leise,
              ),
            ),
          TextSpan(
            text: t.nachname.toUpperCase(),
            style: TextStyle(
              fontSize: nachnameGroesse,
              fontWeight: Schrift.ueberschriftGewicht,
              fontStyle: Schrift.ueberschriftStil,
              color: farbe,
            ),
          ),
        ],
      ),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}
