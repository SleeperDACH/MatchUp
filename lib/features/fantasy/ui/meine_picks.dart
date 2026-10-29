import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/typografie.dart';
import '../../auth/providers.dart';
import '../logic/draft_rechte.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';

/// **Die eigenen Picks für den Reset-Draft** (0145) — auf der Übersicht
/// kompakt als Reihe, im Kader-Reiter unter der Bank als Liste.
///
/// Gehandelt wird **Runde + Team**, nicht die Nummer (`pickBeschriftung`):
/// Vor dem Reset steht „Runde 1 · Big Bang" vorn und „aktuell 1.01"
/// dahinter, danach die feste Nummer. Ohne Reset in der Liga zeigt der
/// Baustein nichts.
class MeinePicks extends ConsumerWidget {
  const MeinePicks({super.key, required this.league, this.kompakt = false});

  final FantasyLeague league;

  /// Reihe aus Marken statt Liste.
  final bool kompakt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myId = ref.watch(currentUserProvider)?.id;
    final alle = ref.watch(resetPicksProvider(league.id));
    if (myId == null || alle == null) return const SizedBox.shrink();
    final meine = picksVon(alle, myId);
    final nameVon = {
      for (final m
          in ref.watch(fantasyManagersProvider(league.id)).valueOrNull ??
              const <FantasyManager>[])
        m.userId: m.display,
    };
    final abgegeben = alle
        .where((p) => p.ursprung == myId && p.gehandelt)
        .length;
    final scheme = Theme.of(context).colorScheme;

    if (meine.isEmpty) {
      return Text(
        'Du hast keine Picks für den Reset-Draft.',
        style: TextStyle(
          fontSize: Schrift.text,
          color: scheme.onSurfaceVariant,
        ),
      );
    }

    String? team(PickSlot p) =>
        p.ursprung == myId ? null : (nameVon[p.ursprung] ?? '?');
    ({String titel, String? zusatz}) text(PickSlot p) => pickBeschriftung(
          runde: p.runde,
          team: team(p),
          code: p.code,
          fest: p.fest,
        );

    if (kompakt) {
      return SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in meine)
                  _PickMarke(code: text(p).titel, erhandelt: p.gehandelt),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              [
                '${meine.length} Picks',
                if (meine.any((p) => p.gehandelt))
                  '${meine.where((p) => p.gehandelt).length} erhandelt',
                if (abgegeben > 0) '$abgegeben abgegeben',
              ].join(' · '),
              style: TextStyle(
                fontSize: Schrift.label,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        for (final (i, p) in meine.indexed) ...[
          if (i > 0) Divider(height: 1, color: Theme.of(context).dividerColor),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                if (p.gehandelt) ...[
                  Icon(Icons.swap_horiz,
                      size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    text(p).titel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: Schrift.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (text(p).zusatz case final z?)
                  Text(
                    z,
                    style: TextStyle(
                      fontSize: Schrift.label,
                      color: scheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _PickMarke extends StatelessWidget {
  const _PickMarke({required this.code, required this.erhandelt});

  final String code;
  final bool erhandelt;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (erhandelt) ...[
            Icon(Icons.swap_horiz, size: 13, color: scheme.onSurfaceVariant),
            const SizedBox(width: 3),
          ],
          Text(
            code,
            style: const TextStyle(
              fontSize: Schrift.text,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// **Ein Pick als Karte** — im Trade-Schirm neben den Spielerkarten, in
/// derselben Größe, damit ein Angebot aus Spielern und Picks wie eines
/// aussieht. Beschriftet nach `pickBeschriftung`: vor dem Reset „Runde 1 ·
/// Big Bang" mit „aktuell 1.01" darunter, danach die feste Nummer vorn.
class PickKachel extends StatelessWidget {
  const PickKachel({
    super.key,
    required this.runde,
    required this.team,
    this.code,
    this.fest = false,
    this.hervor = false,
    this.onTap,
    this.hoehe = 62,
    this.breite,
  });

  /// Die Nummer steht fest (ab dem Reset).
  final bool fest;

  final int runde;

  /// Name des ursprünglichen Teams.
  final String team;

  /// „2.07" — fehlt, solange die Reihenfolge noch nicht berechnet ist.
  final String? code;

  /// Ausgewählt bzw. Inhalt eines Angebots.
  final bool hervor;
  final VoidCallback? onTap;
  final double hoehe;
  final double? breite;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final klein = hoehe < 55;
    final text = pickBeschriftung(
      runde: runde,
      team: team,
      code: code,
      fest: fest,
    );
    return Semantics(
      button: onTap != null,
      selected: hervor,
      label: [text.titel, ?text.zusatz].join(', '),
      excludeSemantics: true,
      child: Material(
        color: hervor
            ? scheme.onSurface.withValues(alpha: 0.14)
            : Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: hervor
                ? scheme.onSurface.withValues(alpha: 0.55)
                : Theme.of(context).dividerColor,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: hoehe,
            width: breite,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Container(
                    width: klein ? 26 : 32,
                    height: klein ? 26 : 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.onSurface.withValues(alpha: 0.08),
                    ),
                    child: Icon(
                      Icons.confirmation_number_outlined,
                      size: klein ? 14 : 17,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            text.titel,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: Schrift.text,
                              fontWeight: FontWeight.w800,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                        if (text.zusatz case final z?)
                          Text(
                            z,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: Schrift.label,
                              color: scheme.onSurfaceVariant,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (onTap != null && hervor)
                    Icon(Icons.check_circle, size: 18, color: scheme.onSurface),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
