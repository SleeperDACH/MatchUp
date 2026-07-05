import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chat_message.dart';

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
    this.hintText = 'Nachricht an die Liga …',
    this.emptyText = 'Noch keine Nachrichten.\nSchreib der Liga als Erster!',
  });

  /// Live-Zustand der Nachrichten (älteste zuerst).
  final AsyncValue<List<ChatMessage>> messages;

  /// user_id → Anzeigename (aus der Mitgliederliste).
  final Map<String, String> names;
  final String? myId;

  /// Sendet den Text; wirft bei Fehlschlag (wird als Snackbar angezeigt).
  final Future<void> Function(String text) onSend;
  final VoidCallback onRetry;
  final String hintText;
  final String emptyText;

  @override
  State<LeagueChat> createState() => _LeagueChatState();
}

class _LeagueChatState extends State<LeagueChat> {
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
      await widget.onSend(text);
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
                    myId: widget.myId,
                  ),
          ),
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
