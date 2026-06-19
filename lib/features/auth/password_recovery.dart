import 'package:flutter/foundation.dart';

/// True, sobald über den Recovery-Link (`passwordRecovery`-Event) ein neues
/// Passwort gesetzt werden soll. Steuert direkt den Root (`_RootGate` in
/// main.dart): ist es gesetzt, zeigt die App den „Neues Passwort"-Screen —
/// unabhängig vom Navigator-Stack, damit das Fenster nicht durch Rebuilds
/// oder Auto-Navigation verloren geht.
final passwordRecoveryMode = ValueNotifier<bool>(false);
