/// **Die Elf der Vorwoche, bis die echte Prognose kommt.**
///
/// Sportmonks stellt die voraussichtliche Aufstellung erst ein bis zwei Tage
/// vor Anpfiff bereit. Nachgemessen am 08.09.2026, drei bis fünf Tage vor dem
/// 3. Spieltag: **null Einträge für alle neun Partien**. Das Vorlauffenster
/// hochzudrehen kauft deshalb nichts — die Daten gibt es einfach noch nicht.
/// Zwischen Abpfiff und Prognose liegen so regelmäßig drei bis fünf Tage, in
/// denen die Frage „spielt er?" trotzdem gestellt wird.
///
/// **Die banalste Regel ist genauso gut wie die gekaufte.** Gemessen über die
/// Saison 2025/26 (306 Spiele): Sportmonks trifft 77,0 % der tatsächlichen
/// Startelf, „dieselbe Elf wie letzte Woche" 77,1 %. Die Fortschreibung ist
/// also kein Notbehelf mit schlechteren Zahlen, sondern dieselbe Trefferquote
/// — nur Tage früher verfügbar.
///
/// **Was sie nicht darf: jemanden hinstellen, der nicht kann.** Verletzte,
/// Gesperrte und Abgewanderte werden durch den **nominellen Ersatz** ersetzt:
/// derselbe Positionsraum, meiste Einsatzminuten dieser Saison. Er erbt den
/// Platz im Raster, damit die Formation stehen bleibt.
///
/// **Und sie behauptet nie, eine Prognose zu sein.** [PrognoseElf.ausRunde]
/// trägt den Spieltag, aus dem sie stammt; die Oberfläche sagt „Zuletzt in der
/// Startelf", nicht „voraussichtlich". Eine Fortschreibung, die sich als
/// Vorhersage ausgibt, wäre die Sorte Behauptung, gegen die diese App an einem
/// Dutzend Stellen argumentiert.
library;

import '../models/fantasy_models.dart';
import '../models/player_absence.dart';
import 'aufstellungs_prognose.dart';

/// Schreibt [letzte] auf den kommenden Spieltag fort.
///
/// [letzte] muss eine **gemeldete** Elf sein (`bestaetigt`) — eine
/// Prognose fortzuschreiben hieße, eine Schätzung als Tatsache auszugeben.
/// `null`, wenn es nichts fortzuschreiben gibt.
///
/// [faelltAus] sind die Spieler-IDs, die für den kommenden Spieltag ausfallen
/// (verletzt, gesperrt, angeschlagen). [vereinsKader] ist der Pool des
/// Vereins, [minuten] die Einsatzminuten dieser Saison je Spieler.
PrognoseElf? fortgeschriebeneElf({
  required PrognoseElf letzte,
  required int ausRunde,
  required List<FantasyPlayer> vereinsKader,
  required Set<String> faelltAus,
  required Map<String, int> minuten,
}) {
  if (!letzte.bestaetigt || letzte.elf.isEmpty) return null;

  // **Abgewanderte zählen wie Ausfälle**, ohne in der Ausfallliste zu stehen:
  // Wer die Liga verlassen hat, steht für keinen Verein mehr auf dem Platz
  // (Migration 0117).
  final kannNicht = <String>{
    ...faelltAus,
    for (final p in vereinsKader)
      if (p.abgewandert) p.id,
  };

  final imKader = {for (final p in vereinsKader) p.id: p};

  // Rückennummern aus der gemeldeten Aufstellung — **die Bank zählt mit**.
  // Genau dort steht der nominelle Ersatz meistens schon drin, und dann trägt
  // sein Trikot die richtige Zahl statt gar keiner.
  final nummerVon = <String, int>{
    for (final s in [...letzte.elf, ...letzte.bank])
      if (s.nummer != null) s.playerId: s.nummer!,
  };

  // Wer aus der alten Elf bleibt, ist vergeben und kann nicht zugleich
  // jemanden ersetzen.
  final belegt = <String>{
    for (final s in letzte.elf)
      if (!kannNicht.contains(s.playerId)) s.playerId,
  };

  FantasyPlayer? ersatzFuer(PlayerPosition pos) {
    final frei = [
      for (final p in vereinsKader)
        if (p.position == pos &&
            !p.abgewandert &&
            !kannNicht.contains(p.id) &&
            !belegt.contains(p.id))
          p,
    ]..sort((a, b) {
        final ma = minuten[a.id] ?? 0;
        final mb = minuten[b.id] ?? 0;
        // Meiste Minuten zuerst; bei Gleichstand der Name, damit die Liste
        // zwischen zwei Aufbauten nicht springt.
        if (ma != mb) return mb.compareTo(ma);
        return a.name.compareTo(b.name);
      });
    return frei.isEmpty ? null : frei.first;
  }

  final neu = <PrognoseSpieler>[];
  for (final s in letzte.elf) {
    if (!kannNicht.contains(s.playerId)) {
      neu.add(s);
      continue;
    }

    // **Ohne bekannte Position kein Ersatz.** Ein Spieler, den unser Pool
    // nicht kennt, hat keinen Positionsraum — irgendjemanden auf seinen Platz
    // zu stellen wäre geraten.
    final pos = imKader[s.playerId]?.position;
    final ersatz = pos == null ? null : ersatzFuer(pos);

    if (ersatz == null) {
      // **Ein offener Platz ist besser als ein falscher.** Lieber sichtbar
      // leer als ein Stürmer im Tor — dieselbe Regel wie beim unbesetzten
      // Torwart im Duell (0120).
      neu.add(PrognoseSpieler(
        playerId: '',
        name: '',
        formationsPosition: s.formationsPosition,
        reihe: s.reihe,
        spalte: s.spalte,
        offen: true,
        fuer: s.name,
      ));
      continue;
    }

    belegt.add(ersatz.id);
    neu.add(PrognoseSpieler(
      playerId: ersatz.id,
      name: ersatz.name,
      nummer: nummerVon[ersatz.id],
      // **Er erbt den Platz im Raster.** Die Formation der Vorwoche bleibt
      // damit stehen; ohne das fiele die Elf beim ersten Ausfall in eine
      // einzige Reihe zusammen.
      formationsPosition: s.formationsPosition,
      reihe: s.reihe,
      spalte: s.spalte,
      ersatz: true,
      fuer: s.name,
    ));
  }

  return PrognoseElf(
    club: letzte.club,
    elf: neu,
    // **Keine Bank.** Die der Vorwoche wäre eine Aussage über ein Spiel, das
    // gelaufen ist; für den kommenden Spieltag weiß sie niemand.
    bank: const [],
    bestaetigt: false,
    formation: letzte.formation,
    stand: letzte.stand,
    ausRunde: ausRunde,
  );
}

/// Wer für den kommenden Spieltag ausfällt — aus den Ausfällen dieser App.
///
/// **Auch der „vermutlich verletzt" zählt.** Er kommt aus dem Wechsel-Ereignis
/// (0122) und ist die einzige Auskunft, die es für fünf von neun verletzt
/// ausgewechselten Spielern überhaupt gab. Ihn hier zu übergehen hieße, genau
/// die Lücke wieder aufzumachen, für die er gebaut wurde — und die
/// Fortschreibung löst sich ohnehin auf, sobald der Verein ihn wieder einplant
/// (0124).
Set<String> faelltAusFuer(
  Map<String, PlayerAbsence> ausfaelle,
  Iterable<FantasyPlayer> vereinsKader,
) {
  final imVerein = {for (final p in vereinsKader) p.id};
  return {
    for (final e in ausfaelle.entries)
      if (imVerein.contains(e.key)) e.key,
  };
}
