import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/app_avatar.dart';
import '../../messaging/ui/conversation_screen.dart';
import 'friend_action_button.dart';

/// Schlankes, liga-unabhängiges Nutzerprofil (z. B. aus dem Chat-Kopf):
/// Avatar, Name, „Freund hinzufügen" und „Nachricht schreiben".
class UserProfileScreen extends ConsumerWidget {
  const UserProfileScreen({
    super.key,
    required this.userId,
    required this.name,
    this.avatar,
    this.showMessageButton = true,
  });

  final String userId;
  final String name;
  final AvatarInfo? avatar;
  final bool showMessageButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('Profil')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        children: [
          Center(
            child: Column(
              children: [
                AppAvatar(
                  imageUrl: avatar?.url,
                  emoji: avatar?.emoji,
                  colorHex: avatar?.color,
                  fallbackText: name,
                  size: 96,
                ),
                const SizedBox(height: 14),
                Text(name,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Center(child: FriendActionButton(userId: userId)),
          if (showMessageButton) ...[
            const SizedBox(height: 12),
            Center(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ConversationScreen(
                        partnerId: userId, partnerName: name))),
                icon: const Icon(Icons.forum_outlined, size: 18),
                label: const Text('Nachricht schreiben'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
