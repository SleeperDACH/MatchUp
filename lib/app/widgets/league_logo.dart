import 'package:flutter/material.dart';

/// DFB-Pokal-Logo als lokales Asset: Die Sportmonks-CDN-Version ist ein JPEG
/// mit fest eingebranntem weißem Hintergrund; diese Variante ist freigestellt
/// (transparent).
const String _dfbPokalAsset = 'assets/leagues/dfb_pokal.png';

/// 2.-Bundesliga-Logo als lokales Asset: Sportmonks liefert noch das alte
/// (glänzende) Logo; dies ist das aktuelle, freigestellte DFL-Logo.
const String _bundesliga2Asset = 'assets/leagues/bundesliga2.png';

/// Offizielles Wettbewerbs-Logo je Liga (Sportmonks-CDN); null = kein Logo.
String? leagueLogoUrl(String leagueId) => switch (leagueId) {
      'bundesliga' =>
        'https://cdn.sportmonks.com/images/soccer/leagues/18/82.png',
      'bundesliga2' =>
        'https://cdn.sportmonks.com/images/soccer/leagues/21/85.png',
      'liga3' => 'https://cdn.sportmonks.com/images/soccer/leagues/24/88.png',
      'dfb_pokal' =>
        'https://cdn.sportmonks.com/images/soccer/leagues/13/109.png',
      'frauen_bundesliga' =>
        'https://cdn.sportmonks.com/images/soccer/leagues/12/1740.png',
      _ => null,
    };

/// Erkennt den DFB-Pokal anhand von Liga-ID, Wettbewerbsname oder Logo-URL,
/// damit dessen weißer CDN-Hintergrund überall durch das freigestellte Asset
/// ersetzt wird.
bool _isDfbPokal({String? leagueId, String? name, String? url}) {
  if (leagueId == 'dfb_pokal') return true;
  if (url != null && url.contains('/109.png')) return true;
  if (name != null) {
    final n = name.toLowerCase();
    if (n.contains('dfb') && n.contains('pokal')) return true;
  }
  return false;
}

/// Erkennt die 2. Bundesliga (Sportmonks führt nur das alte Logo).
bool _isBundesliga2({String? leagueId, String? name, String? url}) {
  if (leagueId == 'bundesliga2') return true;
  if (url != null && url.contains('/85.png')) return true;
  if (name != null) {
    final n = name.toLowerCase();
    if (n.startsWith('2.') && n.contains('bundesliga')) return true;
  }
  return false;
}

/// Wettbewerbs-Logo als Widget. Für den DFB-Pokal wird das freigestellte
/// lokale Asset genutzt (kein weißer Kasten), sonst das offizielle CDN-Logo.
/// [logoUrl] hat Vorrang vor [leagueId]; passt nichts, wird [fallback]
/// gezeigt.
class LeagueLogo extends StatelessWidget {
  const LeagueLogo({
    super.key,
    this.leagueId,
    this.logoUrl,
    this.name,
    required this.size,
    this.fallback,
  });

  final String? leagueId;
  final String? logoUrl;
  final String? name;
  final double size;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    if (_isDfbPokal(leagueId: leagueId, name: name, url: logoUrl)) {
      return Image.asset(_dfbPokalAsset,
          width: size, height: size, fit: BoxFit.contain);
    }
    if (_isBundesliga2(leagueId: leagueId, name: name, url: logoUrl)) {
      return Image.asset(_bundesliga2Asset,
          width: size, height: size, fit: BoxFit.contain);
    }
    final url =
        (logoUrl != null && logoUrl!.isNotEmpty) ? logoUrl : leagueLogoUrl(leagueId ?? '');
    if (url == null || url.isEmpty) return fallback ?? const SizedBox.shrink();
    return Image.network(
      url,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => fallback ?? const SizedBox.shrink(),
    );
  }
}
