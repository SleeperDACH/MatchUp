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

  IconData get _icon => switch (item.kind) {
        NowKind.draft => Icons.gavel_rounded,
        NowKind.tips => Icons.edit_note_rounded,
        NowKind.kickoff => Icons.check_circle_outline,
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
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(
                    accent.withValues(alpha: dark ? 0.20 : 0.16),
                    scheme.surfaceContainerHighest),
                scheme.surfaceContainerHighest,
              ],
            ),
            border: Border.all(color: accent.withValues(alpha: 0.45)),
          ),
          child: Stack(
            children: [
              // Großes, fast verschwundenes Symbol als Tiefe im Hintergrund.
              Positioned(
                right: -14,
                bottom: -18,
                child: Icon(_icon,
                    size: 116, color: accent.withValues(alpha: 0.09)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                        Expanded(
                          child: Text(
                            item.label.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: accent,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _headline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: scheme.onSurface),
                    ),
                    const SizedBox(height: 2),
                    _DeadlineLine(item: item, accent: accent, jetzt: jetzt),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        FilledButton(
                          onPressed: onOpen,
                          style: FilledButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: MatchUpColors.base,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 22, vertical: 10),
                            textStyle: const TextStyle(
                                fontFamily: 'BarlowCondensed',
                                fontSize: 16,
                                fontWeight: FontWeight.w800),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(_action),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
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
    final parts = <String>[
      if (widget.item.detail != null) widget.item.detail!,
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
    return 'Anstoß am '
        '${DateFormat("EEEE, HH:mm 'Uhr'", 'de_DE').format(deadline)}';
  }
  return 'Anstoß ${DateFormat('E, d. MMM, HH:mm', 'de_DE').format(deadline)}';
}
