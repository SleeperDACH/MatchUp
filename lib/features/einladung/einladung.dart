import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **Einladen per Link** (29.10.2026, Punkt 2 der Nutzer-Analyse).
///
/// Vorher ging eine Einladung nur an Leute, die die App schon hatten (eine
/// Direktnachricht), oder als Code in den Einstellungen. Jetzt teilt man über
/// das Teilen-Menü des Handys einen **Web-Link**:
///
///   https://sleeperdach.github.io/MatchUp/einladung/?code=…&name=…
///
/// Ein Web-Link, weil WhatsApp & Co. nur `https` anklickbar machen —
/// `app.matchup.mobile://…` stünde dort als toter Text. Die Seite
/// (`web/einladung/index.html`, liegt mit der Web-Demo auf `gh-pages`) zeigt
/// die Einladung, einen Knopf „In MatchUp öffnen" (das App-Schema), die
/// Download-Wege und den Code zum Abtippen. Ohne `code` ist es eine
/// allgemeine Einladung zur App (Knopf auf dem Homescreen).
///
/// **Was es nicht gibt:** Wer die App erst installiert, landet danach nicht
/// automatisch in der Liga (dafür bräuchte es einen Dienst für „deferred deep
/// links"). Deshalb steht der Code groß auf der Seite und im geteilten Text.
const einladungsSeite = 'https://sleeperdach.github.io/MatchUp/einladung/';

/// Schema-Link, über den die Einladungsseite die App öffnet. Muss zu
/// `CFBundleURLSchemes` (iOS) und dem Intent-Filter mit Host `einladung`
/// (Android) passen.
const einladungsSchema = 'app.matchup.mobile';
const einladungsHost = 'einladung';

/// Der Link, der geteilt wird. Ohne [code] die allgemeine App-Einladung.
Uri einladungsLink({String? code, String? name}) {
  final parameter = {
    if (code != null && code.isNotEmpty) 'code': code,
    if (name != null && name.isNotEmpty) 'name': name,
  };
  final basis = Uri.parse(einladungsSeite);
  return parameter.isEmpty ? basis : basis.replace(queryParameters: parameter);
}

/// Was im Teilen-Menü landet: ein Satz, der Link, und der Code für alle, die
/// die App erst installieren müssen.
String einladungsText({String? code, String? name, String? art}) {
  final link = einladungsLink(code: code, name: name).toString();
  if (code == null || code.isEmpty) {
    return 'Spiel mit mir bei MatchUp — Fantasy-Fußball und Tippspiel zur '
        'Bundesliga: $link';
  }
  final was = art ?? 'Liga';
  final titel = name == null || name.isEmpty ? 'meine $was' : '„$name“';
  return 'Komm in $titel bei MatchUp: $link\n\n'
      'Falls du die App erst installierst: Einladungscode $code '
      '(in der App unter Neu › Mit Code beitreten).';
}

/// Öffnet das Teilen-Menü des Handys. [context] gibt dem iPad die Stelle,
/// an der das Menü aufklappt (ohne sie stürzt es dort ab).
Future<void> teileEinladung(
  BuildContext context, {
  String? code,
  String? name,
  String? art,
}) async {
  final box = context.findRenderObject() as RenderBox?;
  await SharePlus.instance.share(
    ShareParams(
      text: einladungsText(code: code, name: name, art: art),
      subject: 'Einladung zu MatchUp',
      sharePositionOrigin: box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size,
    ),
  );
}

/// Der Code aus einem eingehenden Link, oder `null`, wenn es keine Einladung
/// ist. Erkannt werden das App-Schema (`app.matchup.mobile://einladung?code=…`,
/// so öffnet die Einladungsseite die App) und die Web-Adresse selbst, falls
/// das System sie einmal direkt an die App gibt.
String? einladungsCodeAus(Uri uri) {
  final istSchema =
      uri.scheme == einladungsSchema && uri.host == einladungsHost;
  final istSeite =
      uri.scheme == 'https' &&
      uri.host == 'sleeperdach.github.io' &&
      uri.path.startsWith('/MatchUp/einladung');
  if (!istSchema && !istSeite) return null;
  final code = uri.queryParameters['code']?.trim();
  return (code == null || code.isEmpty) ? null : code;
}

/// Eine angekommene Einladung, die noch nicht angenommen wurde: Code und — wenn
/// der Link ihn trägt — der Name der Liga. Gesetzt aus `main.dart` (Kalt- und
/// Warmstart), abgearbeitet in der App-Hülle, sobald jemand angemeldet ist.
/// Wer erst noch ein Konto anlegt, verliert die Einladung dabei nicht.
final offeneEinladung = ValueNotifier<({String code, String? name})?>(null);

/// Der Link, mit dem die App gestartet wurde — der Strom von `app_links`
/// meldet ihn beim ersten Zuhören noch einmal, und das darf keine zweite
/// Rückfrage werden.
String? _startLink;
bool _startLinkImStromGesehen = false;

const _schluesselStartLink = 'einladung_startlink';

/// **Der Startlink fragt nur einmal** (29.10.2026, gemeldet: „Warum kommt
/// jedes Mal dieses Fenster?"). iOS gibt der App den Link, mit dem sie
/// geöffnet wurde, bei jedem neuen Durchlauf von `main()` wieder als
/// Startlink — im Simulator bei jedem Hot Restart, auf dem Gerät nach jedem
/// Neustart des Prozesses, solange niemand die App anders öffnet. Wer die
/// Einladung einmal beantwortet hat, soll sie nicht wieder sehen; gemerkt
/// wird deshalb der zuletzt behandelte Startlink.
Future<void> einladungAusStartLink(Uri uri) async {
  if (einladungsCodeAus(uri) == null) return;
  final text = uri.toString();
  _startLink = text;
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_schluesselStartLink) == text) return;
    await prefs.setString(_schluesselStartLink, text);
  } catch (_) {
    // Ohne Speicher wird eben gefragt — lieber einmal zu oft als nie.
  }
  _annehmen(uri);
}

/// Ein Link, der bei laufender App ankommt (Warmstart). Die Wiederholung des
/// Startlinks im Strom wird einmal übersprungen; jeder später angetippte Link
/// fragt, auch derselbe noch einmal.
void einladungAusLink(Uri uri) {
  if (!_startLinkImStromGesehen && uri.toString() == _startLink) {
    _startLinkImStromGesehen = true;
    return;
  }
  _annehmen(uri);
}

void _annehmen(Uri uri) {
  final code = einladungsCodeAus(uri);
  if (code == null) return;
  if (kDebugMode) debugPrint('[EINLADUNG] Code aus Link: $code');
  offeneEinladung.value = (code: code, name: uri.queryParameters['name']);
}

/// Ganz oben auf „Spieler einladen" / „Mitglieder einladen": der Weg zu
/// Leuten, die die App noch nicht haben. Die Liste darunter erreicht nur
/// Freunde und Chats innerhalb der App.
class EinladungsLinkKnopf extends StatelessWidget {
  const EinladungsLinkKnopf({
    super.key,
    required this.code,
    required this.name,
    required this.art,
  });

  final String code;
  final String name;

  /// „Fantasy-Liga" oder „Tipprunde" — steht im geteilten Text.
  final String art;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Ohne Symbol: Knöpfe mit Wort tragen in dieser App keins.
          Builder(
            builder: (knopf) => FilledButton(
              onPressed: () =>
                  teileEinladung(knopf, code: code, name: name, art: art),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              child: const Text('Einladungslink teilen'),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Per WhatsApp, iMessage oder Mail — auch an Leute ohne MatchUp.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
