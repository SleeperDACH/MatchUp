/// Eine News-Schlagzeile aus dem RSS-Ticker (Transfers bzw. Ausfälle).
class NewsItem {
  const NewsItem({
    required this.title,
    required this.url,
    this.source,
    this.publishedAt,
    this.imageUrl,
  });

  final String title;
  final String url;
  final String? source;
  final DateTime? publishedAt;

  /// Titelbild der Meldung, wenn die Quelle eines mitliefert.
  ///
  /// **Nicht jede tut das** (gemessen 03.09.2026: Google News gar nicht,
  /// kicker nur das Kanal-Logo, Sportschau ein 16:9-Bild je Meldung). Fehlt
  /// es, zeichnet die Liste eine Ersatzfläche — eine leere Lücke sähe aus wie
  /// ein Ladefehler.
  final String? imageUrl;

  factory NewsItem.fromJson(Map<String, dynamic> json) {
    final src = (json['source'] as String?)?.trim();
    final pub = (json['publishedAt'] as String?)?.trim();
    final bild = (json['image'] as String?)?.trim();
    return NewsItem(
      title: (json['title'] as String? ?? '').trim(),
      url: (json['url'] as String? ?? '').trim(),
      source: (src == null || src.isEmpty) ? null : src,
      publishedAt: (pub == null || pub.isEmpty) ? null : DateTime.tryParse(pub),
      imageUrl: (bild == null || bild.isEmpty) ? null : bild,
    );
  }
}
