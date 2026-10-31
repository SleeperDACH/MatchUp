import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/farben.dart';
import '../../app/typografie.dart';

/// **Erst fragen wir, dann das System** (29.10.2026, Punkt 5 der
/// Nutzer-Analyse).
///
/// Vorher kam die Systemabfrage, sobald der Homescreen zum ersten Mal stand —
/// bevor man wusste, wofür. Wer da „Nicht erlauben" tippt, bekommt die
/// Abfrage nie wieder; Tore, Tipp-Erinnerungen und Draft-Pings erreichen ihn
/// nie. Jetzt kommt sie **nach der Vereinsauswahl**, mit dem Namen des
/// Vereins, als eigenes Blatt: Wer zustimmt, sieht danach die Systemabfrage;
/// wer „Später" sagt, wird in zwei Wochen noch einmal gefragt, und die
/// Systemabfrage ist bis dahin unverbraucht.

const _schluesselSpaeter = 'push_frage_spaeter_bis';
const _spaeterAbstand = Duration(days: 14);

/// Darf die Frage jetzt kommen? Nein, solange ein „Später" noch gilt.
Future<bool> pushFrageFaellig({DateTime? jetzt}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final bis = prefs.getInt(_schluesselSpaeter);
    if (bis == null) return true;
    return (jetzt ?? DateTime.now()).millisecondsSinceEpoch >= bis;
  } catch (_) {
    return true;
  }
}

/// „Später": in zwei Wochen wieder fragen.
Future<void> pushFrageVertagen({DateTime? jetzt}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _schluesselSpaeter,
      (jetzt ?? DateTime.now()).add(_spaeterAbstand).millisecondsSinceEpoch,
    );
  } catch (_) {}
}

/// Das Blatt. `true` = erlauben (danach die Systemabfrage), `false` = später.
/// [verein] ist der erste Lieblingsverein — „für Hannover" sagt mehr als
/// „für deine Vereine".
Future<bool> zeigePushFrage(BuildContext context, {String? verein}) async {
  final ja = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    builder: (ctx) => _PushFrageBlatt(verein: verein),
  );
  return ja ?? false;
}

class _PushFrageBlatt extends StatelessWidget {
  const _PushFrageBlatt({this.verein});

  final String? verein;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final farben = context.farben;
    final fuer = verein == null || verein!.isEmpty ? 'deine Vereine' : verein!;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: farben.gruen.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.notifications_active_outlined,
                  color: farben.gruen,
                  size: 26,
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'NICHTS VERPASSEN',
              style: TextStyle(
                fontSize: Schrift.gross,
                fontWeight: Schrift.ueberschriftGewicht,
                fontStyle: Schrift.ueberschriftStil,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Sollen wir dir Bescheid geben, wenn es bei $fuer spannend wird?',
              style: TextStyle(
                fontSize: Schrift.text,
                height: 1.35,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            _Punkt(
              symbol: Icons.sports_soccer_outlined,
              text: 'Anpfiff, Tore und Endstand',
            ),
            _Punkt(
              symbol: Icons.schedule_outlined,
              text: 'Erinnerung, bevor ein Tipp fällig wird',
            ),
            _Punkt(
              symbol: Icons.groups_outlined,
              text: 'Draft, Trades und Chat in deinen Ligen',
            ),
            const SizedBox(height: 8),
            Text(
              'Was genau, stellst du jederzeit unter Profil › '
              'Benachrichtigungen ein.',
              style: TextStyle(
                fontSize: Schrift.label,
                color: scheme.onSurfaceVariant,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: const Text('Benachrichtigungen erlauben'),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: scheme.onSurfaceVariant,
                minimumSize: const Size.fromHeight(44),
              ),
              child: const Text('Später'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Punkt extends StatelessWidget {
  const _Punkt({required this.symbol, required this.text});

  final IconData symbol;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(symbol, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: Schrift.text,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
