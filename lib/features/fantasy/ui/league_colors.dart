import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../models/fantasy_models.dart';

/// Farbe einer Fantasy-Liga: **das Markengrün von MatchUp.**
///
/// Vorher würfelte jede Liga ihre eigene Farbe aus einer modusabhängigen
/// Palette. Das machte zwei Ligen unterscheidbar, ließ den Homescreen aber
/// bunt aussehen; die Farbe trägt seitdem wieder die Marke.
///
/// **Seit dem Wegfall von Dynasty gibt es nur noch eine Farbe** — das Rot
/// stand für den zweiten Modus, den es nicht mehr gibt. Die Funktion bleibt
/// trotzdem: Sie ist der eine Ort, an dem diese Zuordnung steht, und alle
/// Aufrufer lesen sie weiter. Ligen unterscheiden sich über Name, Zustand und
/// ein eigenes Logo, dessen Farbe diese hier sticht.
Color leagueColor(FantasyMode mode) => MatchUpColors.green;
