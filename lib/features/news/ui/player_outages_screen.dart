import 'package:flutter/material.dart';

import 'news_list_screen.dart';

/// „Verletzungen & Sperren": aktuelle Ausfall-Schlagzeilen der Bundesliga
/// (RSS-Live-News), neueste zuerst. Über den Home-Screen erreichbar.
class PlayerOutagesScreen extends StatelessWidget {
  const PlayerOutagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const NewsListScreen(
      topic: 'injuries',
      title: 'Verletzungen & Sperren',
      intro: 'Aktuelle Schlagzeilen zu Verletzungen und Sperren in der '
          'Bundesliga. Tippen öffnet den Artikel.',
    );
  }
}
