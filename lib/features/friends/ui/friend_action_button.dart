import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../auth/providers.dart';
import '../providers.dart';

/// Freundes-Status-Button für Profile: „Freund hinzufügen" / „Anfrage gesendet"
/// / „Anfrage annehmen" / „Befreundet". Für den eigenen Account unsichtbar.
class FriendActionButton extends ConsumerWidget {
  const FriendActionButton({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // **Nicht `Supabase.instance` direkt.** Der Zugriff wirft eine Assertion,
    // wenn es die Instanz nicht gibt — im Test und, was schwerer wiegt, bei
    // fehlgeschlagener Initialisierung im Release-Build. Dort reißt er dann
    // den ganzen Schirm hoch, auf dem er steht, und das sieht für den Nutzer
    // wie eine graue Fläche ohne Meldung aus. Dieselbe Falle hat schon einmal
    // den Favoriten-Tab erwischt; die Regel dazu steht in CLAUDE.md.
    //
    // `currentUserProvider` prüft `isSupabaseConfigured` selbst und liefert
    // sonst `null` — ohne angemeldeten Nutzer gibt es hier ohnehin nichts
    // anzubieten.
    if (!AppConfig.isSupabaseConfigured) return const SizedBox.shrink();
    final me = ref.watch(currentUserProvider)?.id;
    if (me == null || me == userId) return const SizedBox.shrink();

    final status = ref.watch(friendStatusProvider(userId));
    final repo = ref.read(friendsRepositoryProvider);

    void snack(String text) => ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text)));

    return switch (status) {
      FriendStatus.friends => OutlinedButton.icon(
          onPressed: () => repo.remove(userId),
          icon: const Icon(Icons.how_to_reg, size: 18),
          label: const Text('Befreundet'),
        ),
      FriendStatus.outgoing => OutlinedButton.icon(
          onPressed: () => repo.remove(userId),
          icon: const Icon(Icons.hourglass_top, size: 18),
          label: const Text('Anfrage gesendet'),
        ),
      FriendStatus.incoming => FilledButton.icon(
          onPressed: () => repo.accept(userId),
          icon: const Icon(Icons.check, size: 18),
          label: const Text('Anfrage annehmen'),
        ),
      FriendStatus.none => FilledButton.icon(
          onPressed: () async {
            await repo.sendRequest(userId);
            if (context.mounted) snack('Anfrage gesendet');
          },
          icon: const Icon(Icons.person_add_alt_1, size: 18),
          label: const Text('Freund hinzufügen'),
        ),
    };
  }
}
