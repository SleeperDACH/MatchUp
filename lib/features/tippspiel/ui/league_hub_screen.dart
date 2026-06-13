import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../auth/providers.dart';
import '../models/chat_message.dart';
import '../models/tip.dart';
import '../models/tip_round.dart';
import '../providers.dart';

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
  final _textCtrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(tipRoundRepositoryProvider)
          .sendMessage(widget.round.id, text);
      _textCtrl.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Nachricht konnte nicht gesendet werden: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _openRules() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RulesSheet(
        scoring: widget.round.scoring,
        league: ref.read(selectedLeagueProvider),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(roundMessagesProvider(widget.round.id));
    final members = ref.watch(roundMembersProvider(widget.round.id));
    final myId = ref.watch(currentUserProvider)?.id;

    // user_id → Anzeigename aus der Mitgliederliste.
    final names = <String, String>{
      for (final m in members.valueOrNull ?? const <RoundMember>[])
        m.userId: m.username,
    };

    return Column(
      children: [
        _RulesBanner(onTap: _openRules),
        Expanded(
          child: messages.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _ChatError(
              error: e,
              onRetry: () =>
                  ref.invalidate(roundMessagesProvider(widget.round.id)),
            ),
            data: (list) => _MessageList(
              messages: list,
              names: names,
              myId: myId,
            ),
          ),
        ),
        _Composer(
          controller: _textCtrl,
          sending: _sending,
          onSend: _send,
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

class _MessageList extends StatefulWidget {
  const _MessageList({
    required this.messages,
    required this.names,
    required this.myId,
  });

  final List<ChatMessage> messages;
  final Map<String, String> names;
  final String? myId;

  @override
  State<_MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<_MessageList> {
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _toBottom(animate: false));
  }

  @override
  void didUpdateWidget(_MessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Bei neuer Nachricht ans untere Ende scrollen.
    if (widget.messages.length != oldWidget.messages.length) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _toBottom(animate: true));
    }
  }

  void _toBottom({required bool animate}) {
    if (!_controller.hasClients) return;
    final max = _controller.position.maxScrollExtent;
    if (animate) {
      _controller.animateTo(max,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } else {
      _controller.jumpTo(max);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.messages.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Noch keine Nachrichten.\nSchreib der Liga als Erster!',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    // Älteste oben, neueste unten — automatisch nach unten gescrollt.
    return ListView.builder(
      controller: _controller,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      itemCount: widget.messages.length,
      itemBuilder: (context, i) {
        final msg = widget.messages[i];
        return _MessageBubble(
          message: msg,
          author: widget.names[msg.userId] ?? '?',
          isMine: msg.userId == widget.myId,
        );
      },
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.author,
    required this.isMine,
  });

  final ChatMessage message;
  final String author;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final time = TimeOfDay.fromDateTime(message.createdAt.toLocal());
    final timeText =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: isMine
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMine)
              Text(
                author,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            Text(message.body),
            const SizedBox(height: 2),
            Text(
              timeText,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(28);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: 'Nachricht an die Liga …',
                  filled: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 16),
                  // Dezenter Rahmen; beim Fokus etwas kräftiger.
                  enabledBorder: OutlineInputBorder(
                    borderRadius: radius,
                    borderSide: BorderSide(color: scheme.outlineVariant),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: radius,
                    borderSide: BorderSide(color: scheme.outline),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: sending ? null : onSend,
              iconSize: 26,
              padding: const EdgeInsets.all(14),
              icon: sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatError extends StatelessWidget {
  const _ChatError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Chat konnte nicht geladen werden.',
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('$error',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Erneut laden')),
          ],
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
                    const SizedBox(height: 24),
                    Text('Quoten-Bonus ★', style: textTheme.titleMedium),
                    const SizedBox(height: 8),
                    const _Bullet('Gibt es nur, wenn du die richtige Tendenz '
                        'getippt hast (Sieger bzw. Unentschieden) – das exakte '
                        'Ergebnis spielt keine Rolle. Der Bonus kommt '
                        'zusätzlich zur Wertung oben.'),
                    const _Bullet('Maßgeblich ist die Quote für deine getippte '
                        'Tendenz (Heimsieg, Remis oder Auswärtssieg), '
                        'eingefroren zum Anstoß: Je unwahrscheinlicher dein '
                        'richtiger Tipp war, desto mehr Bonus.'),
                    const _Bullet('+5 Punkte, wenn diese Quote über 5,0 lag – '
                        'du also einen klaren Außenseiter richtig getippt '
                        'hast.'),
                    const _Bullet('+1 Punkt, wenn diese Quote mindestens 2,0 '
                        'höher war als die niedrigste der drei Quoten (der '
                        'Favorit).'),
                    const _Bullet('Die beiden Stufen addieren sich nicht – pro '
                        'Spiel zählt der höhere der beiden Boni.'),
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
