import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../fantasy/providers.dart';
import '../../tippspiel/providers.dart';
import 'join_requests_list.dart';
import 'visibility_picker.dart';

/// Kurzbeschreibung des Sichtbarkeits-/Beitrittszustands (für Untertitel).
String visibilityLabel(String visibility, String joinPolicy) {
  if (visibility != 'public') return 'Privat — nur per Einladung';
  return joinPolicy == 'invite'
      ? 'Öffentlich — auf Einladung'
      : 'Öffentlich — freier Eintritt';
}

/// Trailing für die Einstellungs-Zeile: Anzahl offener Anfragen als Badge
/// (0 = nichts) plus Chevron.
class RequestsBadgeChevron extends StatelessWidget {
  const RequestsBadgeChevron({super.key, required this.pending});

  final int pending;

  @override
  Widget build(BuildContext context) {
    if (pending <= 0) return const Icon(Icons.chevron_right);
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text('$pending',
              style: TextStyle(
                  color: scheme.onPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12)),
        ),
        const SizedBox(width: 4),
        const Icon(Icons.chevron_right),
      ],
    );
  }
}

/// Sichtbarkeit & Beitritt eines Wettbewerbs (Fantasy-Liga oder Tipprunde)
/// ändern und – bei „auf Einladung" – offene Beitrittsanfragen bestätigen
/// oder ablehnen. Nur der Admin sieht diese Seite (RLS setzt es zusätzlich
/// serverseitig durch).
class VisibilitySettingsPage extends ConsumerStatefulWidget {
  const VisibilitySettingsPage({
    super.key,
    required this.kind,
    required this.id,
    required this.name,
    required this.visibility,
    required this.joinPolicy,
  });

  /// `fantasy` oder `tip`.
  final String kind;
  final String id;

  /// Name des Wettbewerbs (für die Rückmeldung an Anfragende).
  final String name;
  final String visibility;
  final String joinPolicy;

  @override
  ConsumerState<VisibilitySettingsPage> createState() =>
      _VisibilitySettingsPageState();
}

class _VisibilitySettingsPageState
    extends ConsumerState<VisibilitySettingsPage> {
  late String _visibility = widget.visibility;
  late String _joinPolicy = widget.joinPolicy;
  bool _saving = false;

  bool get _isFantasy => widget.kind == 'fantasy';

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (_isFantasy) {
        await ref.read(fantasyLeagueRepositoryProvider).updateVisibility(
            widget.id,
            visibility: _visibility,
            joinPolicy: _joinPolicy);
        ref.invalidate(draftLeagueProvider(widget.id));
        ref.invalidate(myFantasyLeaguesProvider);
      } else {
        await ref.read(tipRoundRepositoryProvider).updateVisibility(widget.id,
            visibility: _visibility, joinPolicy: _joinPolicy);
        ref.invalidate(myRoundsProvider);
      }
      messenger.showSnackBar(
          const SnackBar(content: Text('Sichtbarkeit gespeichert.')));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Speichern fehlgeschlagen: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showRequests = _visibility == 'public' && _joinPolicy == 'invite';
    return Scaffold(
      appBar: AppBar(title: const Text('Sichtbarkeit & Beitritt')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          VisibilityPicker(
            visibility: _visibility,
            joinPolicy: _joinPolicy,
            onChanged: (v, p) => setState(() {
              _visibility = v;
              _joinPolicy = p;
            }),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: const Text('Speichern'),
            onPressed: _saving ? null : _save,
          ),
          if (showRequests) ...[
            const SizedBox(height: 28),
            JoinRequestsList(
              kind: widget.kind,
              id: widget.id,
              leagueName: widget.name,
              title: 'Beitrittsanfragen',
              emptyNote: 'Keine offenen Anfragen.',
            ),
          ],
        ],
      ),
    );
  }
}
