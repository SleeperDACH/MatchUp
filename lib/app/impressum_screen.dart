import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Impressum (Anbieterkennzeichnung gemäß § 5 DDG).
class ImpressumScreen extends StatelessWidget {
  const ImpressumScreen({super.key});

  static const _email = 'business@sohrmann.de';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    Widget section(String title) => Padding(
          padding: const EdgeInsets.only(top: 22, bottom: 6),
          child: Text(
            title,
            style: textTheme.labelLarge
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Impressum')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          section('Angaben gemäß § 5 DDG'),
          Text('Felix Sohrmann', style: textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('Gostritzer Straße 7\n01728 Bannewitz',
              style: textTheme.bodyLarge),
          section('Kontakt'),
          InkWell(
            onTap: () async {
              final uri = Uri(scheme: 'mailto', path: _email);
              if (!await launchUrl(uri) && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('E-Mail-App konnte nicht geöffnet werden')),
                );
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.mail_outline, size: 18, color: scheme.primary),
                  const SizedBox(width: 8),
                  Text(_email,
                      style: textTheme.bodyLarge
                          ?.copyWith(color: scheme.primary)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
