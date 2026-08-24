import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/features/auth/biometric_login.dart';
import 'package:matchup/features/auth/providers.dart';
import 'package:matchup/features/auth/ui/login_form.dart';
import 'package:matchup/features/auth/ui/social_buttons.dart';

import 'support/schrift.dart';

/// Der Anmeldescreen mit Google und Apple.
///
/// Prüfen lässt sich das nur als Vorschau: Die Knöpfe erscheinen erst, wenn
/// die Client-IDs einkompiliert sind, und im echten Ablauf öffnet der Tipp
/// darauf ein Systemfenster, das kein Test bedienen kann. Was hier festgehalten
/// wird, ist deshalb das, was der Nutzer sieht — dass beide Knöpfe **über** dem
/// Formular stehen, dass sie sich beschriften, und dass sie verschwinden, wo
/// sie nicht funktionieren würden.

/// Biometrie meldet im Test „nichts eingerichtet". Ohne diesen Ersatz greift
/// `initState` auf Schlüsselbund und Sensor zu — beides gibt es hier nicht,
/// und der Aufbau bricht mit einer MissingPluginException ab.
class _KeineBiometrie extends BiometricLoginService {
  @override
  Future<String?> lastEmail() async => null;
  @override
  Future<bool> isSupported() async => false;
  @override
  Future<bool> isAvailable() async => false;
  @override
  Future<bool> hasSavedCredentials() async => false;
  @override
  Future<String> label() async => 'Face ID';
}

Widget _screen({required bool google, required bool apple}) => ProviderScope(
      overrides: [
        googleSignInAvailableProvider.overrideWithValue(google),
        appleSignInAvailableProvider.overrideWithValue(apple),
        biometricLoginProvider.overrideWithValue(_KeineBiometrie()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: const Scaffold(body: LoginForm()),
      ),
    );

void main() {
  setUpAll(ladeSchrift);

  testWidgets('Vorschau: Anmeldung mit Google und Apple', (tester) async {
    tester.view.physicalSize = const Size(1080, 2100);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_screen(google: true, apple: true));
    await tester.pumpAndSettle();

    expect(find.text('Mit Google anmelden'), findsOneWidget);
    expect(find.text('Mit Apple anmelden'), findsOneWidget);
    expect(find.text('oder'), findsOneWidget);

    // Die Anbieter stehen oben, das E-Mail-Feld darunter — nicht umgekehrt.
    final google = tester.getTopLeft(find.text('Mit Google anmelden')).dy;
    final email = tester.getTopLeft(find.text('E-Mail')).dy;
    expect(google, lessThan(email));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/login_social_preview.png'),
    );
  });

  testWidgets('Ohne eingerichtete Anbieter bleibt das Formular allein',
      (tester) async {
    await tester.pumpWidget(_screen(google: false, apple: false));
    await tester.pumpAndSettle();

    expect(find.byType(GoogleSignInButton), findsNothing);
    expect(find.byType(AppleSignInButton), findsNothing);
    // Ohne Knöpfe darf auch die Trennlinie nicht stehen bleiben: „oder"
    // zwischen nichts und dem Formular wäre ein Rest.
    expect(find.byType(SocialDivider), findsNothing);
    expect(find.text('Anmelden'), findsOneWidget);
  });

  testWidgets('Apple allein — kein Platzhalter, wo Google fehlt',
      (tester) async {
    await tester.pumpWidget(_screen(google: false, apple: true));
    await tester.pumpAndSettle();

    expect(find.byType(GoogleSignInButton), findsNothing);
    expect(find.byType(AppleSignInButton), findsOneWidget);
    expect(find.byType(SocialDivider), findsOneWidget);
  });
}
