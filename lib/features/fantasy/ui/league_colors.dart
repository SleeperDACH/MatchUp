import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../models/fantasy_models.dart';

/// Farbe einer Fantasy-Liga: **Redraft grün, Dynasty rot** — die beiden
/// Markenfarben von MatchUp.
///
/// Vorher würfelte jede Liga ihre eigene Farbe aus einer modusabhängigen
/// Palette. Das machte zwei Ligen desselben Modus unterscheidbar, ließ den
/// Homescreen aber bunt aussehen; die Zuordnung Modus → Farbe trägt jetzt
/// wieder die Marke. Zwei Ligen gleichen Modus unterscheiden sich über Name,
/// Zustand und ein eigenes Logo (dessen Farbe sticht diese hier).
Color leagueColor(FantasyMode mode) =>
    mode == FantasyMode.dynasty ? MatchUpColors.red : MatchUpColors.green;
