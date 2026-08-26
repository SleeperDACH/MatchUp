import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/home_menu_drawer.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/core/config/app_config.dart';
import 'package:matchup/features/auth/providers.dart';
import 'package:matchup/features/auth/user_profile.dart';
import 'package:matchup/features/friends/providers.dart';
import 'package:matchup/features/messaging/models/direct_message.dart';
import 'package:matchup/features/messaging/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/schrift.dart';

/// Vorschau des **Seitenmenüs** (Hamburger oben links) — kein Regressionstest:
///   flutter test --update-goldens test/seitenmenue_vorschau_test.dart
///   -> test/goldens/seitenmenue_vorschau.png
///
/// Das Menü hängt an vier Providern (Profil, Name, offene Freundschafts-
/// anfragen, ungelesene Nachrichten) und zeigt auf dem Gerät nur, was der
/// eigene Account gerade hergibt — mit null offenen Anfragen sieht man die
/// Zähler nie. Hier stehen sie fest.
///
/// Anders als bei den drei Schirmen ist der Bildvergleich hier **fest**: Das
/// Menü zeigt kein Datum, das Bild ist also von Tag zu Tag gleich.
void main() {
  setUpAll(ladeSchrift);

  setUp(() {
    // Der Ungelesen-Punkt je Gespräch liest seine Lesemarke aus
    // SharedPreferences; ohne Mock wirft der Plugin-Kanal im Test.
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Vorschau: Seitenmenü', (tester) async {
    final vorher = AppConfig.supabaseInitialized;
    AppConfig.supabaseInitialized = true;
    addTearDown(() => AppConfig.supabaseInitialized = vorher);

    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentProfileProvider.overrideWith(
            (ref) async => const UserProfile(username: 'SFV03'),
          ),
          currentUsernameProvider.overrideWith((ref) async => 'SFV03'),
          // Zwei offene Anfragen und zwei Gespräche — das Menü zeigt beides
          // jetzt selbst, statt nur darauf zu verlinken.
          incomingRequestsProvider.overrideWith((ref) => ['u-lena', 'u-tim']),
          friendNamesProvider.overrideWith(
            (ref) async => {'u-lena': 'Lena', 'u-tim': 'Tim'},
          ),
          friendAvatarsProvider.overrideWith((ref) async => const {}),
          conversationsProvider.overrideWith(
            (ref) => [
              Conversation(
                partnerId: 'u-jonas',
                lastMessage: DirectMessage(
                  id: 'm1',
                  senderId: 'u-jonas',
                  recipientId: 'ich',
                  body: 'Hast du schon gedraftet?',
                  createdAt: DateTime(2026, 8, 27, 20, 10),
                ),
              ),
              Conversation(
                partnerId: 'u-marie',
                lastMessage: DirectMessage(
                  id: 'm2',
                  senderId: 'ich',
                  recipientId: 'u-marie',
                  body: 'Der Pick war stark',
                  createdAt: DateTime(2026, 8, 27, 18, 2),
                ),
              ),
            ],
          ),
          conversationNamesProvider.overrideWith(
            (ref) async => {'u-jonas': 'Jonas', 'u-marie': 'Marie'},
          ),
          conversationAvatarsProvider.overrideWith((ref) async => const {}),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(
            body: Align(
              alignment: Alignment.centerLeft,
              child: HomeMenuDrawer(),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    await expectLater(
      find.byType(HomeMenuDrawer),
      matchesGoldenFile('goldens/seitenmenue_vorschau.png'),
    );
  });
}
