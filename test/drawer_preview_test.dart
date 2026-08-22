import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/home_menu_drawer.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/features/auth/providers.dart';
import 'package:matchup/features/auth/user_profile.dart';
import 'package:matchup/features/friends/providers.dart';
import 'package:matchup/features/messaging/providers.dart';

// Vorschau des Seitenmenüs (kein Regressionstest):
//   flutter test --update-goldens test/drawer_preview_test.dart
// -> test/goldens/drawer_preview.png

void main() {
  testWidgets('Vorschau: Seitenmenü', (tester) async {
    tester.view.physicalSize = const Size(292 * 3, 700 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Avatar bewusst ohne Bild-URL: im Test lädt kein Netz-Bild.
          currentProfileProvider.overrideWith((ref) async => const UserProfile(
                username: 'SFV03',
                avatarEmoji: '⚽️',
                avatarColor: '#4ADE6A',
              )),
          currentUsernameProvider.overrideWith((ref) async => 'SFV03'),
          incomingRequestsCountProvider.overrideWithValue(3),
          hasUnreadDmsProvider.overrideWithValue(true),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          home: Scaffold(
            backgroundColor: MatchUpColors.base,
            body: RepaintBoundary(
              key: const Key('preview'),
              child: Align(
                alignment: Alignment.centerLeft,
                child: const HomeMenuDrawer(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(find.byKey(const Key('preview')),
        matchesGoldenFile('goldens/drawer_preview.png'));
  });
}
