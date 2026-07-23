import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../../core/ui/league_chat.dart';
import '../../auth/providers.dart';
import '../models/tip.dart';
import '../models/tip_round.dart';
import '../providers.dart';

/// Öffnet die Regeln-/Punkteverteilungs-Ansicht als Bottom-Sheet. Für
/// gekoppelte Tippspiele (ohne eigenen Liga-Tab) über die Einstellungen
/// erreichbar.
void showTipRoundRules(BuildContext context, ScoringRules scoring,
        LeagueInfo league) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RulesSheet(scoring: scoring, league: league),
    );

/// Liga-Tab: ligainterner Chat plus eine Aufführung der Regeln
/// (Punkteverteilung, Tippabgabe). Ersetzt in Server-Ligen die frühere
/// „Meine Punkte"-Ansicht.
class LeagueHubScreen extends ConsumerStatefulWidget {
  const LeagueHubScreen({super.key, required this.round});

  final TipRound round;

  @override
  ConsumerState<LeagueHubScreen> createState() => _LeagueHubScreenState();
}

class _LeagueHubScreenState extends ConsumerState<LeagueHubScreen> {
  void _openRules() => showTipRoundRules(
      context, widget.round.scoring, ref.read(selectedLeagueProvider));

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(roundMessagesProvider(widget.round.id));
    final members = ref.watch(roundMembersProvider(widget.round.id));
    final myId = ref.watch(currentUserProvider)?.id;

    // user_id → Anzeigename aus der Mitgliederliste.
    final memberList = members.valueOrNull ?? const <RoundMember>[];
    final names = <String, String>{
      for (final m in memberList) m.userId: m.display,
    };
    final avatars = {
      for (final m in memberList)
        m.userId: (url: m.avatarUrl, emoji: m.avatarEmoji, color: m.avatarColor)
    };

    return Column(
      children: [
        _RulesBanner(onTap: _openRules),
        Expanded(
          child: LeagueChat(
            messages: messages,
            names: names,
            avatars: avatars,
            myId: myId,
            onSend: (text, replyTo) => ref
                .read(tipRoundRepositoryProvider)
                .sendMessage(widget.round.id, text, replyTo: replyTo),
            onRetry: () =>
                ref.invalidate(roundMessagesProvider(widget.round.id)),
          ),
        ),
      ],
    );
  }
}

/// Auffälliger, aber dezenter Einstieg zu den Liga-Regeln über dem Chat.
class _RulesBanner extends StatelessWidget {
  const _RulesBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.gavel_outlined, size: 20, color: scheme.primary),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Regeln & Punkteverteilung'),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}


/// Die Regeln-Aufführung als Bottom-Sheet: Punkteverteilung + Hinweise zur
/// Tippabgabe. Die Punktwerte stammen aus dem Schema der Tipprunde.
class _RulesSheet extends StatelessWidget {
  const _RulesSheet({required this.scoring, required this.league});

  final ScoringRules scoring;
  final LeagueInfo league;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: ConstrainedBox(
        // Höhe begrenzen, damit der Body innerhalb des Sheets scrollt und
        // nichts abgeschnitten wird (insbesondere im Web).
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Fester Kopf mit Titel und Schließen-Button (statt Wischen).
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Regeln & Wertung',
                        style: textTheme.headlineSmall),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: 'Schließen',
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Wettbewerb: ${league.name}',
                        style: textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 20),
                    Text('Punkteverteilung', style: textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Pro Spiel zählt nur die höchste zutreffende Stufe – '
                      'innerhalb eines Spiels addieren sich diese Punkte nicht.',
                      style: textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    _RuleRow(
                      points: scoring.exact,
                      label: 'Exaktes Ergebnis',
                      detail: 'Du tippst den Endstand genau richtig. '
                          'Beispiel: Tipp 2:1, Endstand 2:1.',
                    ),
                    _RuleRow(
                      points: scoring.goalDiff,
                      label: 'Richtige Tordifferenz',
                      detail: 'Richtiger Sieger und gleicher Tor-Abstand wie im '
                          'Endstand, aber anderes Ergebnis. Beispiel: Tipp 2:1, '
                          'Endstand 3:2. Bei einem Remis: du tippst '
                          'unentschieden, nur mit anderem Stand (Tipp 1:1, '
                          'Endstand 2:2).',
                    ),
                    _RuleRow(
                      points: scoring.tendency,
                      label: 'Richtige Tendenz',
                      detail: 'Du tippst den richtigen Sieger, aber Tor-Abstand '
                          'und Ergebnis stimmen nicht. Beispiel: Tipp 3:0, '
                          'Endstand 1:0.',
                    ),
                    const _RuleRow(
                      points: 0,
                      label: 'Daneben',
                      detail: 'Der getippte Ausgang (Heimsieg, Remis oder '
                          'Auswärtssieg) ist nicht eingetreten.',
                    ),
                    if (scoring.oddsBonus) ...[
                      const SizedBox(height: 24),
                      Text('Quoten-Bonus ★', style: textTheme.titleMedium),
                      const SizedBox(height: 8),
                      const _Bullet('Gibt es nur, wenn du die richtige Tendenz '
                          'getippt hast (Sieger bzw. Unentschieden) – das '
                          'exakte Ergebnis spielt keine Rolle. Der Bonus kommt '
                          'zusätzlich zur Wertung oben.'),
                      const _Bullet('Maßgeblich ist die zum Anstoß '
                          'eingefrorene Quote deiner getippten Tendenz: Je '
                          'höher die Quote, desto mehr Bonus.'),
                      _Bullet('+${scoring.oddsPoints1} Punkte ab einer Quote '
                          'von ${scoring.oddsOdds1.toStringAsFixed(1).replaceAll('.', ',')}.'),
                      _Bullet('+${scoring.oddsPoints2} Punkte ab einer Quote '
                          'von ${scoring.oddsOdds2.toStringAsFixed(1).replaceAll('.', ',')} '
                          '(krasser Außenseiter).'),
                      const _Bullet('Die beiden Stufen addieren sich nicht – '
                          'pro Spiel zählt der höhere der beiden Boni.'),
                    ],
                    if (scoring.solo > 0) ...[
                      const SizedBox(height: 24),
                      Text('Alleinstellungs-Bonus ★',
                          style: textTheme.titleMedium),
                      const SizedBox(height: 8),
                      _Bullet('+${scoring.solo} Punkte, wenn du als Einzige/r '
                          'das exakte Ergebnis eines Spiels getippt hast — '
                          'zusätzlich zur Wertung oben.'),
                    ],
                    if (scoring.headToHead) ...[
                      const SizedBox(height: 24),
                      Text('Head-to-Head', style: textTheme.titleMedium),
                      const SizedBox(height: 8),
                      const _Bullet('Jeder Spieltag ist zusätzlich ein Duell '
                          'gegen ein anderes Mitglied: Wer an dem Spieltag mehr '
                          'Punkte holt, gewinnt (Sieg/Niederlage/Unentschieden).'),
                      const _Bullet('Die Paarungen und die Bilanz (S-N-U) '
                          'stehen im „Duelle"-Tab.'),
                    ],
                    if (scoring.bonusTips.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Text('Bonustipps', style: textTheme.titleMedium),
                      const SizedBox(height: 8),
                      _Bullet('Saison-Prognosen, die du vor dem ersten Spieltag '
                          'abgibst: '
                          '${scoring.bonusTips.map(bonusTipLabel).join(', ')}.'),
                      _Bullet('Jede richtige Prognose bringt '
                          '+${scoring.bonusPoints} Punkte. Abgabe über die '
                          'Tabelle („Bonustipps abgeben").'),
                    ],
                    if (league.fixedSeason != null) ...[
                      const SizedBox(height: 24),
                      Text('K.-o.-Runde', style: textTheme.titleMedium),
                      const SizedBox(height: 8),
                      const _Bullet('In der K.-o.-Runde zählt das Ergebnis '
                          'nach Verlängerung (120 Minuten).'),
                      const _Bullet('Ein Elfmeterschießen wird nicht '
                          'mitgewertet: Maßgeblich ist der Spielstand am Ende '
                          'der Verlängerung. Beispiel: 1:1 nach Verlängerung, '
                          'das Team gewinnt im Elfmeterschießen – gewertet wird '
                          'der Tipp gegen 1:1.'),
                    ],
                    const SizedBox(height: 24),
                    Text('Tippabgabe', style: textTheme.titleMedium),
                    const SizedBox(height: 8),
                    const _Bullet('Tipps lassen sich bis zum Anstoß des '
                        'jeweiligen Spiels abgeben und beliebig ändern.'),
                    const _Bullet('Mit dem Anstoß wird die Begegnung gesperrt; '
                        'ab diesem Zeitpunkt sind auch die Tipps der '
                        'Mitspieler einsehbar.'),
                    const _Bullet('Jede Begegnung wird einzeln gewertet; die '
                        'Summe aller Punkte ergibt den Tabellenstand.'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({
    required this.points,
    required this.label,
    required this.detail,
  });

  final int points;
  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Text(
              '$points',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: points > 0 ? scheme.primary : scheme.onSurfaceVariant,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600)),
                Text(detail,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  '),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
