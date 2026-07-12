import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/chat_message.dart';
import 'app_avatar.dart';

/// Wiederverwendbarer ligainterner Chat (Tippspiel wie Fantasy): scrollende
/// Nachrichtenliste (älteste oben, automatisch nach unten) plus Eingabezeile.
/// Kapselt Eingabe-Controller, Sende-Status, Fehler-Snackbar und
/// Auto-Scrollen — der Aufrufer liefert nur den Nachrichten-Stream, die
/// Namensauflösung und den Sende-Callback.
class LeagueChat extends StatefulWidget {
  const LeagueChat({
    super.key,
    required this.messages,
    required this.names,
    required this.myId,
    required this.onSend,
    required this.onRetry,
    this.avatars = const {},
    this.hintText = 'Nachricht an die Liga …',
    this.emptyText = 'Noch keine Nachrichten.\nSchreib der Liga als Erster!',
    this.extraBuilder,
    this.enableReply = true,
  });

  /// user_id → Avatar-Info (Bild oder Emoji+Farbe); fehlt ein Eintrag, greift
  /// die Initiale des Namens.
  final Map<String, AvatarInfo> avatars;

  /// Ob auf Nachrichten geantwortet werden kann (setzt eine `reply_to`-Spalte
  /// voraus). Für Direktnachrichten aus (dort nicht unterstützt).
  final bool enableReply;

  /// Optionale Zusatzkarte unter einer Nachricht (z. B. Trade-Aktionen).
  final Widget? Function(BuildContext, ChatMessage)? extraBuilder;

  /// Live-Zustand der Nachrichten (älteste zuerst).
  final AsyncValue<List<ChatMessage>> messages;

  /// user_id → Anzeigename (aus der Mitgliederliste).
  final Map<String, String> names;
  final String? myId;

  /// Sendet den Text (optional als Antwort auf [replyTo]); wirft bei Fehlschlag
  /// (wird als Snackbar angezeigt).
  final Future<void> Function(String text, String? replyTo) onSend;
  final VoidCallback onRetry;
  final String hintText;
  final String emptyText;

  @override
  State<LeagueChat> createState() => _LeagueChatState();
}

class _LeagueChatState extends State<LeagueChat> {
  final _textCtrl = TextEditingController();
  bool _sending = false;

  /// Nachricht, auf die gerade geantwortet wird (`null` = normale Nachricht).
  ChatMessage? _replyTo;

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
      await widget.onSend(text, _replyTo?.id);
      _textCtrl.clear();
      if (mounted) setState(() => _replyTo = null);
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: widget.messages.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _ChatError(error: e, onRetry: widget.onRetry),
            data: (list) => list.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(widget.emptyText, textAlign: TextAlign.center),
                    ),
                  )
                : _MessageList(
                    messages: list,
                    names: widget.names,
                    avatars: widget.avatars,
                    myId: widget.myId,
                    extraBuilder: widget.extraBuilder,
                    onReply: widget.enableReply
                        ? (m) => setState(() => _replyTo = m)
                        : null,
                  ),
          ),
        ),
        if (_replyTo != null)
          _ReplyPreview(
            author: _replyTo!.userId == widget.myId
                ? 'Dir'
                : (widget.names[_replyTo!.userId] ?? '?'),
            body: _replyTo!.body,
            onCancel: () => setState(() => _replyTo = null),
          ),
        _Composer(
          controller: _textCtrl,
          sending: _sending,
          hintText: widget.hintText,
          onSend: _send,
        ),
      ],
    );
  }
}

class _MessageList extends StatefulWidget {
  const _MessageList({
    required this.messages,
    required this.names,
    required this.avatars,
    required this.myId,
    required this.onReply,
    this.extraBuilder,
  });

  final List<ChatMessage> messages;
  final Map<String, String> names;
  final Map<String, AvatarInfo> avatars;
  final String? myId;
  final Widget? Function(BuildContext, ChatMessage)? extraBuilder;

  /// Auf eine Nachricht antworten (Long-Press auf die Blase); `null` = aus.
  final void Function(ChatMessage)? onReply;

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
    // Nachrichten mit Datumstrennern (wie WhatsApp) zu Zeilen aufbauen.
    final byId = {for (final m in widget.messages) m.id: m};
    final rows = <Widget>[];
    DateTime? lastDay;
    for (final msg in widget.messages) {
      final day = DateUtils.dateOnly(msg.createdAt.toLocal());
      if (lastDay == null || day != lastDay) {
        rows.add(_DateSeparator(day: day));
        lastDay = day;
      }
      if (msg.isSystem) {
        rows.add(_SystemLine(text: msg.body));
        continue;
      }
      final isMine = msg.userId == widget.myId;
      // Sonderinhalt (z. B. Trade-Karte) ersetzt die Textblase.
      final extra = widget.extraBuilder?.call(context, msg);
      if (extra != null) {
        rows.add(Align(
          alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
          child: extra,
        ));
        continue;
      }
      // Zitierte Original-Nachricht auflösen (falls noch vorhanden).
      final quoted = msg.replyTo == null ? null : byId[msg.replyTo];
      rows.add(_MessageBubble(
        message: msg,
        author: widget.names[msg.userId] ?? '?',
        avatar: widget.avatars[msg.userId],
        isMine: isMine,
        hasReply: msg.replyTo != null,
        quotedAuthor: quoted == null
            ? null
            : (quoted.userId == widget.myId
                ? 'Du'
                : (widget.names[quoted.userId] ?? '?')),
        quotedBody: quoted?.body,
        onReply: widget.onReply == null ? null : () => widget.onReply!(msg),
      ));
    }
    // Älteste oben, neueste unten — automatisch nach unten gescrollt.
    return ListView.builder(
      controller: _controller,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      itemCount: rows.length,
      itemBuilder: (context, i) => rows[i],
    );
  }
}

/// Zentrierter Datumstrenner zwischen Nachrichten verschiedener Tage.
class _DateSeparator extends StatelessWidget {
  const _DateSeparator({required this.day});

  final DateTime day;

  String get _label {
    final today = DateUtils.dateOnly(DateTime.now());
    if (day == today) return 'Heute';
    if (day == today.subtract(const Duration(days: 1))) return 'Gestern';
    return DateFormat('d. MMMM yyyy', 'de_DE').format(day);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          _label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }
}

/// Automatische System-Mitteilung (Kaderänderung o. Ä.): zentrierte Karte
/// mit Akzentrand, flankiert von dünnen Linien wie ein Ereignis-Marker.
class _SystemLine extends StatelessWidget {
  const _SystemLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Emoji am Anfang (falls vorhanden) vom Text trennen, damit es als
    // farbiges Badge links steht.
    final parts = text.split(' ');
    final hasIcon = parts.isNotEmpty && parts.first.runes.length <= 2 &&
        parts.first.codeUnits.first > 0x2000;
    final icon = hasIcon ? parts.first : null;
    final body = hasIcon ? parts.sublist(1).join(' ') : text;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.86),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.22)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (icon != null) ...[
                  Text(icon, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    body,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.author,
    required this.isMine,
    required this.onReply,
    this.avatar,
    this.hasReply = false,
    this.quotedAuthor,
    this.quotedBody,
  });

  final ChatMessage message;
  final String author;
  final AvatarInfo? avatar;
  final bool isMine;

  /// `null` = Antworten deaktiviert (kein Long-Press-Menü).
  final VoidCallback? onReply;

  /// Diese Nachricht ist eine Antwort (zitiert unten aufgelöst).
  final bool hasReply;
  final String? quotedAuthor;
  final String? quotedBody;

  void _showActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Antworten'),
              onTap: () {
                Navigator.of(ctx).pop();
                onReply!();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final time = TimeOfDay.fromDateTime(message.createdAt.toLocal());
    final timeText =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    final bubble = GestureDetector(
        onLongPress: onReply == null ? null : () => _showActions(context),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.72,
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
              if (hasReply)
                _QuotedReply(author: quotedAuthor, body: quotedBody),
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

    // Eigene Nachrichten rechts ohne Avatar; fremde links mit kleinem Avatar.
    if (isMine) {
      return Align(alignment: Alignment.centerRight, child: bubble);
    }
    return Padding(
      padding: const EdgeInsets.only(right: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: AppAvatar(
              imageUrl: avatar?.url,
              emoji: avatar?.emoji,
              colorHex: avatar?.color,
              fallbackText: author,
              size: 30,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(child: bubble),
        ],
      ),
    );
  }
}

/// Zitat der beantworteten Nachricht innerhalb einer Blase (Balken + Auszug).
class _QuotedReply extends StatelessWidget {
  const _QuotedReply({required this.author, required this.body});

  final String? author;
  final String? body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: scheme.primary, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            author ?? 'Nachricht',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
          ),
          Text(
            body ?? 'Nachricht nicht mehr verfügbar',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

/// Vorschau der zu beantwortenden Nachricht über dem Eingabefeld.
class _ReplyPreview extends StatelessWidget {
  const _ReplyPreview({
    required this.author,
    required this.body,
    required this.onCancel,
  });

  final String author;
  final String body;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 34,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Antwort an $author',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                        )),
                Text(body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        )),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            iconSize: 20,
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.hintText,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final String hintText;
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
                  hintText: hintText,
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
