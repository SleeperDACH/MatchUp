import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'default_avatar.dart';

/// Gemeinsame Darstellung eines Profil-/Liga-Bildes ("Beides kombiniert"):
/// bevorzugt ein hochgeladenes Bild ([imageUrl]); sonst Emoji + Farbe
/// ([emoji]/[colorHex]); sonst der klassische Fallback (Initiale bzw. Icon).
class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    this.imageUrl,
    this.emoji,
    this.colorHex,
    this.fallbackText,
    this.fallbackIcon,
    this.seed,
    this.size = 44,
    this.cornerRadius,
  });

  final String? imageUrl;
  final String? emoji;
  final String? colorHex;

  /// Fallback, wenn weder Bild noch Emoji gesetzt sind.
  final String? fallbackText;
  final IconData? fallbackIcon;

  /// Stabiler Schlüssel für das generierte Standard-Avatar (User-ID
  /// bevorzugt). Ohne Angabe dient [fallbackText] als Schlüssel.
  final String? seed;

  final double size;

  /// `null` → Kreis (Profile); ein Wert → abgerundetes Quadrat (Ligen).
  final double? cornerRadius;

  bool get _hasImage => imageUrl != null && imageUrl!.trim().isNotEmpty;
  bool get _hasEmoji => emoji != null && emoji!.trim().isNotEmpty;

  BorderRadius? get _radius =>
      cornerRadius == null ? null : BorderRadius.circular(cornerRadius!);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_hasImage) {
      final img = Image.network(
        imageUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _fallbackBox(context, scheme),
      );
      return SizedBox(
        width: size,
        height: size,
        child: cornerRadius == null
            ? ClipOval(child: img)
            : ClipRRect(borderRadius: _radius!, child: img),
      );
    }
    return _fallbackBox(context, scheme);
  }

  Widget _fallbackBox(BuildContext context, ColorScheme scheme) {
    // Profile ohne Bild/Emoji (Kreis) bekommen das generierte MatchUp-Gesicht
    // als Standard-Avatar — pro Nutzer in einer eigenen Farbe. Ligen
    // (abgerundetes Quadrat) behalten Buchstabe/Icon.
    final faceSeed = (seed ?? fallbackText)?.trim();
    if (!_hasEmoji &&
        cornerRadius == null &&
        faceSeed != null &&
        faceSeed.isNotEmpty) {
      return DefaultAvatar(seed: faceSeed, size: size, cornerRadius: cornerRadius);
    }

    final bg = parseColor(colorHex) ??
        (_hasEmoji ? scheme.surfaceContainerHighest : scheme.primary.withValues(alpha: 0.12));
    final Widget child;
    if (_hasEmoji) {
      child = Text(emoji!, style: TextStyle(fontSize: size * 0.5));
    } else if (fallbackText != null && fallbackText!.trim().isNotEmpty) {
      child = Text(
        fallbackText!.characters.first.toUpperCase(),
        style: TextStyle(
          fontSize: size * 0.44,
          fontWeight: FontWeight.bold,
          color: scheme.primary,
        ),
      );
    } else {
      child = Icon(fallbackIcon ?? Icons.emoji_events_outlined,
          size: size * 0.5, color: scheme.primary);
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        shape: cornerRadius == null ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: _radius,
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}

/// Kompakte Avatar-Info (Bild-URL oder Emoji + Farbe) zum Durchreichen in
/// Maps (z. B. userId → AvatarInfo für Chat/Tabellen).
typedef AvatarInfo = ({String? url, String? emoji, String? color});

/// Die zu speichernden Avatar-Felder (alle `null` = entfernen/zurücksetzen).
class AvatarValue {
  const AvatarValue({this.url, this.emoji, this.color});
  final String? url;
  final String? emoji;
  final String? color;
}

/// Farb-Hex (`#RRGGBB` oder `RRGGBB`) → [Color]; `null`/ungültig → `null`.
Color? parseColor(String? hex) {
  if (hex == null) return null;
  var h = hex.trim().replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(v);
}

/// Auswahl an Hintergrundfarben für den Emoji-Modus.
const List<String> kAvatarColors = [
  '#4ADE6A', '#4FC3A1', '#5B9DF9', '#8B7CF6', '#F472B6',
  '#F23030', '#FF8A3D', '#FFC83D', '#94A3B8', '#12141C',
];

/// Auswahl an Emojis (sport-/team-lastig) für den Emoji-Modus.
const List<String> kAvatarEmojis = [
  '⚽', '🏆', '🥇', '🔥', '⭐', '🐐', '🦁', '🐉', '🚀', '💪',
  '👑', '🎯', '🛡️', '🎮', '😎', '🤖', '🐺', '🦅', '🐻', '🦈',
  '🌍', '🏈', '🏀', '⚡',
];

/// Lädt Bytes in den `avatars`-Bucket und gibt eine cache-sichere öffentliche
/// URL zurück (Zeitstempel-Query, weil der Pfad je Entität stabil bleibt).
Future<String> uploadAvatarBytes(
    String path, Uint8List bytes, String contentType) async {
  final storage = Supabase.instance.client.storage.from('avatars');
  await storage.uploadBinary(path, bytes,
      fileOptions: FileOptions(upsert: true, contentType: contentType));
  final base = storage.getPublicUrl(path);
  return '$base?v=${DateTime.now().millisecondsSinceEpoch}';
}

/// Öffnet den Avatar-Editor (Foto hochladen ODER Emoji + Farbe wählen) und gibt
/// die zu speichernden Felder zurück (`null` = abgebrochen). [storagePath] ist
/// der stabile Zielpfad im Bucket (z. B. `profiles/<uid>.jpg`).
Future<AvatarValue?> showAvatarEditor(
  BuildContext context, {
  required String storagePath,
  required String title,
  bool circle = true,
  String? currentUrl,
  String? currentEmoji,
  String? currentColor,
}) {
  return showModalBottomSheet<AvatarValue>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _AvatarEditorSheet(
      storagePath: storagePath,
      title: title,
      circle: circle,
      currentUrl: currentUrl,
      currentEmoji: currentEmoji,
      currentColor: currentColor,
    ),
  );
}

class _AvatarEditorSheet extends StatefulWidget {
  const _AvatarEditorSheet({
    required this.storagePath,
    required this.title,
    required this.circle,
    this.currentUrl,
    this.currentEmoji,
    this.currentColor,
  });

  final String storagePath;
  final String title;
  final bool circle;
  final String? currentUrl;
  final String? currentEmoji;
  final String? currentColor;

  @override
  State<_AvatarEditorSheet> createState() => _AvatarEditorSheetState();
}

class _AvatarEditorSheetState extends State<_AvatarEditorSheet> {
  late String? _emoji = widget.currentEmoji;
  late String _color = widget.currentColor ?? kAvatarColors.first;
  bool _uploading = false;

  Future<void> _pickPhoto() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 640,
        maxHeight: 640,
        imageQuality: 85,
      );
      if (picked == null) return;
      setState(() => _uploading = true);
      final bytes = await picked.readAsBytes();
      final url = await uploadAvatarBytes(
          widget.storagePath, bytes, picked.mimeType ?? 'image/jpeg');
      if (!mounted) return;
      Navigator.of(context).pop(AvatarValue(url: url));
    } catch (e) {
      if (mounted) setState(() => _uploading = false);
      messenger.showSnackBar(
          SnackBar(content: Text('Upload fehlgeschlagen: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final corner = widget.circle ? null : 14.0;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Text(widget.title,
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            const SizedBox(height: 16),
            // Vorschau der aktuellen Emoji-/Farb-Wahl.
            Center(
              child: AppAvatar(
                emoji: _emoji,
                colorHex: _emoji != null ? _color : null,
                fallbackIcon: Icons.image_outlined,
                size: 76,
                cornerRadius: corner,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _uploading ? null : _pickPhoto,
              icon: _uploading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.photo_library_outlined),
              label: Text(_uploading ? 'Lädt hoch …' : 'Foto hochladen'),
            ),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(child: Divider(color: scheme.outlineVariant)),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('oder Emoji + Farbe'),
              ),
              Expanded(child: Divider(color: scheme.outlineVariant)),
            ]),
            const SizedBox(height: 12),
            // Emoji-Auswahl.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in kAvatarEmojis)
                  GestureDetector(
                    onTap: () => setState(() => _emoji = e),
                    child: Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _emoji == e ? scheme.primary : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Text(e, style: const TextStyle(fontSize: 22)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            // Farb-Auswahl.
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final c in kAvatarColors)
                  GestureDetector(
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: parseColor(c),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _color == c ? scheme.onSurface : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: _color == c
                          ? const Icon(Icons.check, size: 18, color: Colors.white)
                          : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                if (widget.currentUrl != null ||
                    widget.currentEmoji != null) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _uploading
                          ? null
                          : () => Navigator.of(context)
                              .pop(const AvatarValue()),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Entfernen'),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: FilledButton(
                    onPressed: _emoji == null || _uploading
                        ? null
                        : () => Navigator.of(context)
                            .pop(AvatarValue(emoji: _emoji, color: _color)),
                    child: const Text('Speichern'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
