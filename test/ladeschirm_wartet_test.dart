import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/home_favorites.dart';
import 'package:matchup/app/widgets/matchup_splash.dart';
import 'package:matchup/core/config/app_config.dart';
import 'package:matchup/features/auth/providers.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/features/fantasy/providers.dart';
import 'package:matchup/features/news/models/news_item.dart';
import 'package:matchup/features/news/providers.dart';
import 'package:matchup/features/tippspiel/models/tip_round.dart';
import 'package:matchup/features/tippspiel/providers.dart';
import 'package:matchup/core/models/team_fixture.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

/// **Der Startbildschirm bleibt stehen, bis der Homescreen wirklich steht.**
///
/// Gewünscht: *„Bitte verlänger den Ladescreen der App, bis das Match über
/// den Ligen geladen hat und die News da sind."*
///
/// Vorher wartete `homeBereitProvider` nur auf Ligen und Tipprunden — mit der
/// Begründung, man dürfe den Schirm nicht an die langsamste Quelle hängen.
/// Technisch richtig, in der Sache falsch: Der Schirm blendete ab, und
/// **danach** wuchsen Kopfkarte und Newsblock nach; der Screen sprang unter
/// dem Daumen.
///
/// Der Test hält beide Enden fest: Jede der vier Quellen hält den Schirm
/// allein fest (sonst könnte eine wieder herausfallen, ohne dass es auffällt),
/// **und** ein Fehler hält ihn nicht fest — sonst stünde er bei jedem
/// Netzausfall bis zur Notbremse.

final _nutzer = User(
  id: 'ich',
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: DateTime(2026).toIso8601String(),
);

/// Ein Future, das nie fertig wird — die Quelle bleibt „lädt".
Future<T> _haengt<T>() => Completer<T>().future;

enum _Zustand { laedt, fertig, fehler }

ProviderContainer _behaelter({
  _Zustand ligen = _Zustand.fertig,
  _Zustand runden = _Zustand.fertig,
  _Zustand favoriten = _Zustand.fertig,
  _Zustand news = _Zustand.fertig,
  bool angemeldet = true,
}) {
  Future<List<T>> quelle<T>(_Zustand z) => switch (z) {
        _Zustand.laedt => _haengt<List<T>>(),
        _Zustand.fertig => Future.value(<T>[]),
        _Zustand.fehler => Future.error(Exception('Netz weg')),
      };

  return ProviderContainer(
    overrides: [
      currentUserProvider.overrideWith((ref) => angemeldet ? _nutzer : null),
      myFantasyLeaguesProvider.overrideWith(
          (ref) => Stream.fromFuture(quelle<FantasyLeague>(ligen))),
      myRoundsProvider.overrideWith((ref) => quelle<TipRound>(runden)),
      favoritenSpieleProvider
          .overrideWith((ref) => quelle<TeamFixture>(favoriten)),
      newsProvider.overrideWith((ref, thema) => quelle<NewsItem>(news)),
    ],
  );
}

/// Lässt die fertigen Futures durchlaufen und liest dann den Zustand.
Future<bool> _bereit(ProviderContainer c) async {
  c.listen(homeBereitProvider, (a, b) {}, fireImmediately: true);
  // Ein paar Runden der Ereignisschleife: Was fertig werden kann, wird es
  // hier; was hängt, hängt auch danach noch.
  await Future<void>.delayed(const Duration(milliseconds: 20));
  return c.read(homeBereitProvider);
}

void main() {
  late bool vorher;

  setUp(() {
    vorher = AppConfig.supabaseInitialized;
    AppConfig.supabaseInitialized = true;
  });
  tearDown(() => AppConfig.supabaseInitialized = vorher);

  test('alles geladen → der Schirm darf gehen', () async {
    final c = _behaelter();
    addTearDown(c.dispose);
    expect(await _bereit(c), isTrue);
  });

  test('jede einzelne Quelle hält den Schirm fest', () async {
    for (final fall in [
      ('Ligen', _behaelter(ligen: _Zustand.laedt)),
      ('Tipprunden', _behaelter(runden: _Zustand.laedt)),
      // Das „Match über den Ligen" — die Kopfkarte mit dem nächsten Spiel.
      ('Favoritenspiele', _behaelter(favoriten: _Zustand.laedt)),
      ('News', _behaelter(news: _Zustand.laedt)),
    ]) {
      final (name, c) = fall;
      addTearDown(c.dispose);
      expect(await _bereit(c), isFalse, reason: '$name lädt noch');
    }
  });

  test('ein Fehler hält den Schirm nicht fest', () async {
    for (final c in [
      _behaelter(favoriten: _Zustand.fehler),
      _behaelter(news: _Zustand.fehler),
    ]) {
      addTearDown(c.dispose);
      expect(await _bereit(c), isTrue);
    }
  });

  test('ohne Anmeldung sofort bereit — auch wenn alles hängt', () async {
    final c = _behaelter(
      angemeldet: false,
      ligen: _Zustand.laedt,
      news: _Zustand.laedt,
    );
    addTearDown(c.dispose);
    expect(await _bereit(c), isTrue);
  });

  test('ohne Server sofort bereit', () async {
    AppConfig.supabaseInitialized = false;
    final c = _behaelter(ligen: _Zustand.laedt, news: _Zustand.laedt);
    addTearDown(c.dispose);
    expect(await _bereit(c), isTrue);
  });
}
