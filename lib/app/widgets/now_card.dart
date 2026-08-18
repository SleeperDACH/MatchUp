import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../home_now.dart';
import '../theme.dart';
import 'pulsing_dot.dart';

/// Die Jetzt-Karte am Kopf des Homescreens: was gerade ansteht, mit Uhr und
/// einem Knopf, der direkt dorthin führt. Bewusst nur *eine* Sache — der
/// Screen soll eine Handlung anbieten, keine zweite Liste.
class NowCard extends StatelessWidget {
  const NowCard({
    super.key,
    required this.item,
    required this.onOpen,
    this.jetzt,
  });

  final NowItem item;
  final VoidCallback onOpen;

  /// Fester „jetzt"-Zeitpunkt für die Golden-Vorschau; im Betrieb `null`,
  /// dann läuft die echte Uhr. Ohne das wäre die Vorschau bei jedem Lauf
  /// eine andere Restzeit — und der Golden-Test grundsätzlich rot.
  final DateTime? jetzt;

  /// Markenfarbe je Art: Fantasy grün, Tippspiel gold, „alles erledigt" grau.
  Color get _accent => switch (item.kind) {
        NowKind.draft => MatchUpColors.green,
        NowKind.tips => const Color(0xFFFFC83D),
        NowKind.kickoff => const Color(0xFF7C93A8),
      };

  String get _headline => switch (item.kind) {
        NowKind.draft => item.myTurn ? 'Du bist dran' : 'Draft läuft',
        NowKind.tips =>
          item.openTips == 1 ? '1 Tipp offen' : '${item.openTips} Tipps offen',
        NowKind.kickoff => 'Alles getippt',
      };

  String get _action => switch (item.kind) {
        NowKind.draft => item.myTurn ? 'Jetzt picken' : 'Zum Draft',
        NowKind.tips => 'Jetzt tippen',
        NowKind.kickoff => 'Zur Runde',
      };

  /// Pulsiert nur, wenn es wirklich brennt: eigener Pick oder Anstoß in
  /// unter einer Stunde. Sonst wäre das Signal wertlos.
  bool get _urgent {
    if (item.kind == NowKind.draft) return item.myTurn;
    final d = item.deadline;
    if (d == null || item.kind != NowKind.tips) return false;
    return d.difference(jetzt ?? DateTime.now()) < const Duration(hours: 1);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = _accent;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Color.alphaBlend(
                    accent.withValues(alpha: dark ? 0.22 : 0.17),
                    scheme.surfaceContainerHighest),
                Color.alphaBlend(
                    accent.withValues(alpha: dark ? 0.05 : 0.04),
                    scheme.surfaceContainerHighest),
              ],
            ),
            border: Border.all(color: accent.withValues(alpha: 0.45)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(13, 10, 10, 11),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          if (_urgent)
                            PulsingDot(size: 8, color: accent)
                          else
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                  color: accent, shape: BoxShape.circle),
                            ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              _headline,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      height: 1.05,
                                      color: scheme.onSurface),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child:
                            _DeadlineLine(item: item, accent: accent, jetzt: jetzt),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // Kompakter Knopf statt breiter Fläche: die Karte soll eine
                // Zeile hoch sein, nicht ein Viertel des Bildschirms.
                FilledButton(
                  onPressed: onOpen,
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: MatchUpColors.base,
                    minimumSize: const Size(0, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    textStyle: const TextStyle(
                        fontFamily: 'BarlowCondensed',
                        fontSize: 15,
                        fontWeight: FontWeight.w800),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11)),
                  ),
                  child: Text(_action),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Zweite Zeile: Kontext („Spieltag 3") und die laufende Uhr.
class _DeadlineLine extends StatefulWidget {
  const _DeadlineLine(
      {required this.item, required this.accent, this.jetzt});

  final NowItem item;
  final Color accent;

  /// Fester Zeitpunkt für die Vorschau; `null` = echte Uhr mit Ticker.
  final DateTime? jetzt;

  @override
  State<_DeadlineLine> createState() => _DeadlineLineState();
}

class _DeadlineLineState extends State<_DeadlineLine> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  /// Sekundentakt nur in der letzten Stunde — davor genügt jede halbe Minute,
  /// damit die Karte nicht dauernd neu zeichnet.
  void _schedule() {
    _timer?.cancel();
    if (widget.jetzt != null) return; // Vorschau: eingefrorene Zeit.
    final d = widget.item.deadline;
    if (d == null) return;
    final left = d.difference(DateTime.now());
    if (left.isNegative) return;
    final tick = left < const Duration(hours: 1)
        ? const Duration(seconds: 1)
        : const Duration(seconds: 30);
    _timer = Timer(tick, () {
      if (!mounted) return;
      setState(() {});
      _schedule();
    });
  }

  @override
  void didUpdateWidget(_DeadlineLine old) {
    super.didUpdateWidget(old);
    if (old.item.deadline != widget.item.deadline) _schedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = widget.jetzt ?? DateTime.now();
    // Der Liganame (bzw. „3 Tippspiele") steht jetzt hier: in der kompakten
    // Karte gibt es keine eigene Zeile mehr dafür. Der Spieltag entfällt,
    // sonst wird die Zeile so lang, dass ausgerechnet die Uhrzeit
    // abgeschnitten wird.
    final parts = <String>[
      widget.item.kontext,
      if (widget.item.deadline != null)
        formatDeadline(widget.item.deadline!, now,
            isPick: widget.item.kind == NowKind.draft),
    ];
    return Text(
      parts.join(' · '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
    );
  }
}

/// Restzeit als Text: je näher die Deadline, desto genauer. Für den Pick
/// („[isPick]") zählt nur die Uhr, ein Datum wäre dort sinnlos.
String formatDeadline(DateTime deadline, DateTime now, {bool isPick = false}) {
  final left = deadline.difference(now);
  if (left.isNegative) return isPick ? 'Zeit abgelaufen' : 'Anpfiff';
  String two(int n) => n.toString().padLeft(2, '0');
  if (left < const Duration(hours: 1)) {
    return '${isPick ? 'noch' : 'Anstoß in'} '
        '${left.inMinutes}:${two(left.inSeconds % 60)} min';
  }
  if (left < const Duration(hours: 24)) {
    return '${isPick ? 'noch' : 'Anstoß in'} '
        '${left.inHours}:${two(left.inMinutes % 60)} Std';
  }
  if (left < const Duration(days: 7)) {
    // Kurzer Wochentag: in der schmalen Karte steht neben der Zeile noch der
    // Knopf, „Anstoß am Donnerstag, 15:00 Uhr" wird dort abgeschnitten.
    return 'Anstoß ${DateFormat('E, HH:mm', 'de_DE').format(deadline)} Uhr';
  }
  return 'Anstoß ${DateFormat('E, d. MMM, HH:mm', 'de_DE').format(deadline)}';
}
