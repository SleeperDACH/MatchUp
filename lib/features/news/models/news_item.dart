/// Eine News-Schlagzeile aus dem RSS-Ticker (Transfers bzw. Ausfälle).
class NewsItem {
  const NewsItem({
    required this.title,
    required this.url,
    this.source,
    this.publishedAt,
  });

  final String title;
  final String url;
  final String? source;
  final DateTime? publishedAt;

  factory NewsItem.fromJson(Map<String, dynamic> json) {
    final src = (json['source'] as String?)?.trim();
    final pub = (json['publishedAt'] as String?)?.trim();
    return NewsItem(
      title: (json['title'] as String? ?? '').trim(),
      url: (json['url'] as String? ?? '').trim(),
      source: (src == null || src.isEmpty) ? null : src,
      publishedAt: (pub == null || pub.isEmpty) ? null : DateTime.tryParse(pub),
    );
  }
}
