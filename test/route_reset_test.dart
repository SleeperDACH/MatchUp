import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/widgets/route_reset.dart';

// Regressionstest für „nach Abmelden + neu Anmelden komme ich nur durch
// Beenden der App auf den Homescreen": über dem Gate liegengebliebene Routen
// verdecken den Kontowechsel.

/// Baut das Gate nach: erste Route = [wert] entscheidet über den Inhalt.
Widget _app(String? wert) => MaterialApp(
      home: RouteReset<String?>(
        wert: wert,
        child: Scaffold(body: Text(wert == null ? 'Login' : 'Shell $wert')),
      ),
    );

void main() {
  testWidgets('Abmelden räumt aufgeschobene Screens weg', (tester) async {
    await tester.pumpWidget(_app('nutzer-1'));
    expect(find.text('Shell nutzer-1'), findsOneWidget);

    // Profil o. ä. liegt über dem Gate.
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    unawaitedPush(nav, 'Profil');
    await tester.pumpAndSettle();
    expect(find.text('Profil'), findsOneWidget);

    // Abmelden.
    await tester.pumpWidget(_app(null));
    await tester.pumpAndSettle();

    expect(find.text('Profil'), findsNothing);
    expect(find.text('Login'), findsOneWidget);
  });

  testWidgets('Kontowechsel räumt auch einen zweiten Login weg',
      (tester) async {
    await tester.pumpWidget(_app(null));
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    unawaitedPush(nav, 'Zweiter Login');
    await tester.pumpAndSettle();
    expect(find.text('Zweiter Login'), findsOneWidget);

    await tester.pumpWidget(_app('nutzer-2'));
    await tester.pumpAndSettle();

    expect(find.text('Zweiter Login'), findsNothing);
    expect(find.text('Shell nutzer-2'), findsOneWidget);
  });

  testWidgets('Gleiches Konto lässt den Stapel in Ruhe', (tester) async {
    await tester.pumpWidget(_app('nutzer-1'));
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    unawaitedPush(nav, 'Liga');
    await tester.pumpAndSettle();

    // Rebuild ohne Kontowechsel (z. B. anderer Provider hat sich geändert).
    await tester.pumpWidget(_app('nutzer-1'));
    await tester.pumpAndSettle();

    expect(find.text('Liga'), findsOneWidget);
  });
}

void unawaitedPush(NavigatorState nav, String titel) {
  nav.push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(body: Text(titel))));
}
