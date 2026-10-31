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
  _KeineBiometrie({this.email});

  /// Zuletzt benutzte E-Mail — gesetzt heißt „war hier schon angemeldet".
  final String? email;

  @override
  Future<String?> lastEmail() async => email;
  @override
  Future<bool> isSupported() async => false;
  @override
  Future<bool> isAvailable() async => false;
  @override
  Future<bool> hasSavedCredentials() async => false;
  @override
  Future<String> label() async => 'Face ID';
}

Widget _screen({required bool google, required bool apple, String? email}) =>
    ProviderScope(
      overrides: [
        googleSignInAvailableProvider.overrideWithValue(google),
        appleSignInAvailableProvider.overrideWithValue(apple),
        biometricLoginProvider.overrideWithValue(_KeineBiometrie(email: email)),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: const Scaffold(body: SafeArea(child: LoginForm())),
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

    expect(find.text('Weiter mit Google'), findsOneWidget);
    expect(find.text('Weiter mit Apple'), findsOneWidget);
    expect(find.text('oder'), findsOneWidget);

    // Die Anbieter stehen oben, das E-Mail-Feld darunter — nicht umgekehrt.
    final google = tester.getTopLeft(find.text('Weiter mit Google')).dy;
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
    // Neu auf dem Gerät: der Umschalter steht oben, gewählt ist Registrieren.
    expect(find.text('Konto erstellen'), findsOneWidget);
    expect(find.text('Willkommen zurück'), findsNothing);
  });

  testWidgets('Apple allein — kein Platzhalter, wo Google fehlt',
      (tester) async {
    await tester.pumpWidget(_screen(google: false, apple: true));
    await tester.pumpAndSettle();

    expect(find.byType(GoogleSignInButton), findsNothing);
    expect(find.byType(AppleSignInButton), findsOneWidget);
    expect(find.byType(SocialDivider), findsOneWidget);
  });

  testWidgets('Wer schon angemeldet war, landet auf „Anmelden"',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2100);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
        _screen(google: true, apple: true, email: 'felix@example.de'));
    await tester.pumpAndSettle();
    expect(find.text('Willkommen zurück'), findsOneWidget);
    expect(find.text('Passwort vergessen?'), findsOneWidget);

    // Der Umschalter führt zurück zum Registrieren — ohne Scrollen.
    await tester.tap(find.text('Registrieren').first);
    await tester.pumpAndSettle();
    expect(find.text('Konto erstellen'), findsOneWidget);
    expect(find.text('Nutzername'), findsOneWidget);

    await tester.tap(find.text('Anmelden').first);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/login_zurueck.png'),
    );
  });

  testWidgets('„Erst mal reinschauen" steht unter dem Formular',
      (tester) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Mit den Rändern eines echten iPhones (Dynamic Island, Home-Leiste):
    // Der Weg in die Vorschau muss ohne Scrollen zu sehen sein.
    tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
    addTearDown(tester.view.resetPadding);
    await tester.pumpWidget(_screen(google: true, apple: true));
    await tester.pumpAndSettle();
    expect(find.text('Erst mal reinschauen'), findsOneWidget);
    expect(tester.getBottomLeft(find.text('Erst mal reinschauen')).dy,
        lessThan(874 - 34));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/login_iphone.png'),
    );
  });
}
