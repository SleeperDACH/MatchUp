import 'package:flutter/material.dart';
import '../../app/widgets/skelett.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../app/typografie.dart';
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
    this.systemBuilder,
    this.enableReply = true,
    this.neuAb,
  });

  /// user_id → Avatar-Info (Bild oder Emoji+Farbe); fehlt ein Eintrag, greift
  /// die Initiale des Namens.
  final Map<String, AvatarInfo> avatars;

  /// Ob auf Nachrichten geantwortet werden kann (setzt eine `reply_to`-Spalte
  /// voraus). Für Direktnachrichten aus (dort nicht unterstützt).
  final bool enableReply;

  /// **Ab wann ist eine Nachricht neu?** Ist der Zeitpunkt gesetzt, zieht der
  /// Verlauf vor der ersten jüngeren *fremden* Nachricht eine Linie „Neue
  /// Nachrichten".
  ///
  /// Ohne sie war nicht zu erkennen, welche Nachrichten der rote Zähler
  /// gemeint hatte: Der Schirm setzte die Lesemarke beim Öffnen auf *jetzt*,
  /// die Ungelesenen waren also verschwunden, bevor man sie sehen konnte.
  /// Deshalb hält der Schirm den Stand **von vor dem Öffnen** fest und reicht
  /// ihn hier herein.
  final DateTime? neuAb;

  /// Optionale Zusatzkarte unter einer Nachricht (z. B. Trade-Aktionen).
  final Widget? Function(BuildContext, ChatMessage)? extraBuilder;

  /// Eigene Darstellung einer **Systemnachricht** — etwa die Kaderbewegungen
  /// im Liga-Chat (17.10.2026). `null` zurückgeben heißt: die gewöhnliche
  /// Systemzeile.
  final Widget? Function(BuildContext, ChatMessage)? systemBuilder;

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

  /// Nachricht, auf die gerade geantwortet wird (`null` = normale Nachricht).
  ChatMessage? _replyTo;

  /// **Eigene Nachrichten, die der Server noch nicht zurückgemeldet hat.**
  ///
  /// Gemeldet: „Wenn man eine Nachricht schickt, wird sie nicht direkt nach dem
  /// Absenden angezeigt, sondern ein paar Sekunden verzögert." Der Verlauf
  /// zeigte nur, was über die Realtime-Verbindung zurückkam — Senden,
  /// Schreiben in die Datenbank, Ereignis an alle Zuhörer, und erst dann die
  /// Blase. Jetzt steht sie im selben Moment da, in dem man tippt, und wird
  /// gegen die echte Zeile getauscht, sobald die ankommt ([_zusammenfuehren]).
  final _ausstehend = <ChatMessage>[];

  /// Die davon, deren Speichern der Server schon bestätigt hat. Sie stehen
  /// voll da; nur was noch unterwegs ist, ist gedämpft.
  final _bestaetigt = <String>{};
  var _laufendeNr = 0;

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    final antwortAuf = _replyTo;
    final lokal = ChatMessage(
      id: 'ausstehend:${_laufendeNr++}',
      userId: widget.myId,
      body: text,
      createdAt: DateTime.now(),
      replyTo: antwortAuf?.id,
    );
    // **Sofort zeigen, dann senden.** Das Eingabefeld ist gleich wieder frei;
    // wer drei Nachrichten hintereinander tippt, wartet auf keine davon.
    setState(() {
      _ausstehend.add(lokal);
      _replyTo = null;
    });
    _textCtrl.clear();
    try {
      await widget.onSend(text, antwortAuf?.id);
      if (mounted) setState(() => _bestaetigt.add(lokal.id));
    } catch (e) {
      if (!mounted) return;
      // **Ein Fehlschlag nimmt die Blase wieder weg und gibt den Text
      // zurück.** Eine Nachricht, die im Verlauf steht, aber nie angekommen
      // ist, wäre schlimmer als die Verzögerung, um die es ging.
      setState(() {
        _ausstehend.remove(lokal);
        _replyTo ??= antwortAuf;
      });
      if (_textCtrl.text.isEmpty) _textCtrl.text = text;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nachricht konnte nicht gesendet werden: $e')),
      );
    }
  }

  /// Server-Verlauf plus eigene Nachrichten, die er noch nicht kennt.
  ///
  /// Eine ausstehende Nachricht gilt als angekommen, sobald im Verlauf eine
  /// eigene mit demselben Text steht, die nicht älter ist als sie (mit einer
  /// Minute Spielraum für eine falsch gehende Uhr). Jede Server-Zeile löst
  /// dabei höchstens **eine** ausstehende ab — zweimal „ok" hintereinander
  /// sind zwei Nachrichten.
  List<ChatMessage> _zusammenfuehren(List<ChatMessage> server) {
    if (_ausstehend.isEmpty) return server;
    final vergeben = <String>{};
    final offen = <ChatMessage>[];
    for (final a in _ausstehend) {
      final treffer = server.where((m) =>
          !vergeben.contains(m.id) &&
          m.userId == a.userId &&
          m.body == a.body &&
          !m.createdAt.isBefore(
              a.createdAt.subtract(const Duration(minutes: 1))));
      if (treffer.isEmpty) {
        offen.add(a);
      } else {
        vergeben.add(treffer.first.id);
      }
    }
    // Angekommene aufräumen, ohne im `build` `setState` zu rufen.
    if (offen.length != _ausstehend.length) {
      _ausstehend
        ..clear()
        ..addAll(offen);
    }
    return [...server, ...offen];
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: widget.messages.when(
            loading: () => const Skelett(),
            error: (e, _) => _ChatError(error: e, onRetry: widget.onRetry),
            data: (server) {
              final list = _zusammenfuehren(server);
              return list.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(widget.emptyText, textAlign: TextAlign.center),
                    ),
                  )
                : _MessageList(
                    neuAb: widget.neuAb,
                    messages: list,
                    unterwegs: {
                      for (final a in _ausstehend)
                        if (!_bestaetigt.contains(a.id)) a.id,
                    },
                    names: widget.names,
                    avatars: widget.avatars,
                    myId: widget.myId,
                    extraBuilder: widget.extraBuilder,
                    systemBuilder: widget.systemBuilder,
                    onReply: widget.enableReply
                        ? (m) => setState(() => _replyTo = m)
                        : null,
                  );
            },
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
          sending: false,
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
    this.systemBuilder,
    this.neuAb,
    this.unterwegs = const {},
  });

  final Widget? Function(BuildContext, ChatMessage)? systemBuilder;

  /// IDs eigener Nachrichten, die gerade gesendet werden — sie stehen
  /// gedämpft da, bis der Server sie bestätigt.
  final Set<String> unterwegs;

  /// Siehe [LeagueChat.neuAb].
  final DateTime? neuAb;

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
  void didUpdateWidget(_MessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Kommt eine Nachricht dazu, während man schon unten steht, rutscht die
    // Liste von selbst mit (umgedrehte Liste, Offset 0 ist unten). Wer weiter
    // oben liest, bleibt, wo er ist — genau wie in jedem anderen Chat.
    // Bewegt wird nur, wenn man ohnehin fast unten war.
    if (widget.messages.length > oldWidget.messages.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _nachUnten());
    }
  }

  void _nachUnten() {
    if (!_controller.hasClients) return;
    if (_controller.offset > 220) return; // liest gerade Älteres
    _controller.animateTo(0,
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
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
    var neuMarkeGesetzt = false;
    for (final msg in widget.messages) {
      final day = DateUtils.dateOnly(msg.createdAt.toLocal());
      if (lastDay == null || day != lastDay) {
        rows.add(_DateSeparator(day: day));
        lastDay = day;
      }
      // Die Linie steht **einmal**, vor der ersten neuen fremden Nachricht.
      // Eigene zählen nicht: Was man selbst geschrieben hat, hat man gelesen.
      if (!neuMarkeGesetzt &&
          widget.neuAb != null &&
          !msg.isSystem &&
          msg.userId != widget.myId &&
          msg.createdAt.isAfter(widget.neuAb!)) {
        rows.add(const _NeuTrenner());
        neuMarkeGesetzt = true;
      }
      if (msg.isSystem) {
        rows.add(widget.systemBuilder?.call(context, msg) ??
            _SystemLine(text: msg.body));
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
      final bubble = _MessageBubble(
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
        // Auf eine Nachricht, die der Server noch nicht kennt, lässt sich
        // nicht antworten — ihre ID ist nur eine lokale.
        onReply: widget.onReply == null || msg.id.startsWith('ausstehend:')
            ? null
            : () => widget.onReply!(msg),
      );
      rows.add(widget.unterwegs.contains(msg.id)
          ? Opacity(opacity: 0.6, child: bubble)
          : bubble);
    }
    // **Die Liste ist umgedreht, nicht gescrollt.**
    //
    // Vorher stand sie normal herum, und ein `jumpTo(maxScrollExtent)` im
    // ersten Frame sollte sie ans Ende setzen. Das ging schief, sobald die
    // Blasen verschieden hoch sind: Eine `ListView.builder` kennt die Höhe
    // ungebauter Zeilen nicht, `maxScrollExtent` ist im ersten Frame also
    // geschätzt — man landete „irgendwo", und je länger der Verlauf, desto
    // weiter daneben. Bilder und nachgeladene Avatare verschoben es zusätzlich.
    //
    // Mit `reverse: true` ist Offset 0 das **untere** Ende: Die Liste beginnt
    // dort, ohne dass jemand etwas rechnen muss, und sie bleibt dort, wenn
    // eine Nachricht dazukommt. Gebaut wird von hinten (`rows.length - 1 - i`),
    // damit oben trotzdem das Ältere steht.
    return ListView.builder(
      controller: _controller,
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      itemCount: rows.length,
      itemBuilder: (context, i) => rows[rows.length - 1 - i],
    );
  }
}

/// „Neue Nachrichten" — die Linie, ab der man noch nicht gelesen hatte.
///
/// Rot, weil sie dasselbe meint wie der Zähler am Nachrichten-Symbol: Hier
/// wartet etwas. Sie steht genau einmal je Verlauf; eine Linie über jeder
/// neuen Nachricht wäre keine Grenze mehr, sondern ein Muster.
class _NeuTrenner extends StatelessWidget {
  const _NeuTrenner();

  @override
  Widget build(BuildContext context) {
    const rot = MatchUpColors.red;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: rot.withValues(alpha: 0.45))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Neue Nachrichten',
              style: TextStyle(
                color: rot,
                fontSize: Schrift.label,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
              ),
            ),
          ),
          Expanded(child: Container(height: 1, color: rot.withValues(alpha: 0.45))),
        ],
      ),
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

  /// **Wie eine Nachricht der Liga selbst** (17.10.2026, nach dem Vorbild
  /// Sleeper): links das Liga-Zeichen, daneben der Text. Vorher stand sie in
  /// einem grün getönten Kasten — grün gestochene Flächen sind in dieser App
  /// verboten, und eine Meldung ist kein Signal „hier läuft etwas".
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ChatLigaZeichen(),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Das Zeichen, unter dem die Liga selbst im Chat spricht — ein Schild im
/// Kreis, wie bei Sleeper. Öffentlich, weil die Kaderbewegungen im
/// Fantasy-Chat dieselbe Absenderzeile tragen.
class ChatLigaZeichen extends StatelessWidget {
  const ChatLigaZeichen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: scheme.onSurface.withValues(alpha: 0.07),
      ),
      child: Icon(Icons.shield_outlined, size: 20, color: scheme.primary),
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

  /// `null` = Antworten deaktiviert (Direktnachrichten). Das Long-Press-Menü
  /// öffnet sich trotzdem — es bleibt dann beim Kopieren.
  final VoidCallback? onReply;

  /// Diese Nachricht ist eine Antwort (zitiert unten aufgelöst).
  final bool hasReply;
  final String? quotedAuthor;
  final String? quotedBody;

  /// Long-Press auf eine Blase: kopieren, antworten.
  ///
  /// **Kopieren steht immer drin, Antworten nur wenn moeglich.** Frueher hing
  /// das ganze Blatt an `onReply` — wo nicht geantwortet werden kann, tat der
  /// Long-Press schlicht nichts, und ein Griff, der nichts tut, ist von einem
  /// fehlenden Griff nicht zu unterscheiden. Genau so las sich der Bericht:
  /// „kopieren funktioniert irgendwie nicht".
  void _showActions(BuildContext context) {
    // Vor dem `await` greifen: danach ist der Blatt-Kontext schon fort.
    final messenger = ScaffoldMessenger.of(context);
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.content_copy),
              title: const Text('Kopieren'),
              onTap: () async {
                Navigator.of(ctx).pop();
                await Clipboard.setData(ClipboardData(text: message.body));
                messenger.showSnackBar(
                  const SnackBar(content: Text('Nachricht kopiert')),
                );
              },
            ),
            if (onReply != null)
              ListTile(
                leading: const Icon(Icons.reply_outlined),
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
        onLongPress: () => _showActions(context),
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
                      fontSize: 11,
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
            // „Schließen" wäre zweideutig — der Chat bleibt offen, nur die
            // Antwortvorschau darüber verschwindet.
            tooltip: 'Antwort verwerfen',
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
              // Auch beim Senden benannt: der Knopf zeigt dann einen Kreisel
              // statt des Papierfliegers und hätte sonst gar kein Symbol,
              // aus dem sich etwas ableiten ließe.
              tooltip: sending ? 'Wird gesendet' : 'Senden',
              onPressed: sending ? null : onSend,
              iconSize: 26,
              padding: const EdgeInsets.all(14),
              icon: sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_outlined),
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
