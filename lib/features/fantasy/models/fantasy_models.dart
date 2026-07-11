/// Domainmodelle für den Fantasy-Modus.
///
/// Bewusst sport-/ligaunabhängig gehalten: Ein Fantasy-Wettbewerb kennt
/// einen Spielerpool (aktuell Bundesliga-Seed), zwei Modi (Liga = eine
/// Saison / Dynasty = über Jahre) und einen Snake-Draft mit konfigurierbarer
/// Pickzeit.
library;

/// Spielmodus einer Fantasy-Liga.
enum FantasyMode {
  /// Redraft: Kader gilt nur für eine Saison, danach neuer Draft.
  liga,

  /// Dynasty: Kader wird über Saisons behalten; U20-Spieler werden nach
  /// dem Erst-Draft gesperrt und vor der neuen Saison neu gedraftet.
  dynasty;

  String get label => switch (this) {
        FantasyMode.liga => 'Redraft',
        FantasyMode.dynasty => 'Dynasty',
      };

  String get tagline => switch (this) {
        FantasyMode.liga => 'Eine Saison · danach neuer Draft',
        FantasyMode.dynasty => 'Kader über Jahre · U20-Draft jede Saison',
      };

  static FantasyMode fromId(String id) =>
      values.firstWhere((m) => m.name == id, orElse: () => FantasyMode.liga);
}

/// Erlaubte Pickzeiten im Snake-Draft. Kurze Stufen ermöglichen einen
/// Live-Draft, lange Stufen einen Slow-Draft über Tage.
enum DraftPickTime {
  s30(30, '30 Sekunden'),
  m1(60, '1 Minute'),
  m2(120, '2 Minuten'),
  m5(300, '5 Minuten'),
  m10(600, '10 Minuten'),
  m30(1800, '30 Minuten'),
  h1(3600, '1 Stunde'),
  h2(7200, '2 Stunden'),
  h4(14400, '4 Stunden'),
  h8(28800, '8 Stunden'),
  d1(86400, '1 Tag');

  const DraftPickTime(this.seconds, this.label);

  final int seconds;
  final String label;

  /// Grobe Einordnung für die UI: bis 10 Minuten gilt als Live-Draft.
  bool get isLive => seconds <= 600;

  static DraftPickTime fromSeconds(int seconds) => values.firstWhere(
        (t) => t.seconds == seconds,
        orElse: () => DraftPickTime.m1,
      );
}

enum DraftStatus { setup, drafting, done }

DraftStatus _draftStatusFromId(String id) =>
    DraftStatus.values.firstWhere((s) => s.name == id,
        orElse: () => DraftStatus.setup);

/// Draft-Phase im Dynasty-Modus: Haupt-Draft (etablierte Spieler) und
/// U20-Draft (U20-Spieler + Auslands-Neuzugänge). Liga-Modus bleibt
/// immer in [startup].
enum DraftPhase {
  startup,
  u20;

  String get label =>
      this == DraftPhase.u20 ? 'U20-Draft' : 'Haupt-Draft';

  static DraftPhase fromId(String id) =>
      values.firstWhere((p) => p.name == id, orElse: () => DraftPhase.startup);
}

enum PlayerPosition {
  gk('TW', 'Tor'),
  def('ABW', 'Abwehr'),
  mid('MF', 'Mittelfeld'),
  fwd('ST', 'Sturm');

  const PlayerPosition(this.short, this.label);

  final String short;
  final String label;

  static PlayerPosition fromId(String id) => values.firstWhere(
        (p) => p.name == id,
        orElse: () => PlayerPosition.mid,
      );
}

/// Konfigurierbares Punkteschema im Kickbase-Stil. Die echten
/// Kickbase-Punkte stammen aus einem proprietären Daten-Feed; hier ist
/// das kompatible, einstellbare Modell, das später aus Live-Stats
/// gefüttert wird.
class FantasyScoring {
  const FantasyScoring({
    this.appearance = 2,
    this.goalGk = 6,
    this.goalDef = 6,
    this.goalMid = 5,
    this.goalFwd = 4,
    this.assist = 3,
    this.cleanSheetGkDef = 4,
    this.yellowCard = -1,
    this.redCard = -3,
  });

  /// Punkte fürs Mitwirken (Einsatz).
  final int appearance;
  final int goalGk;
  final int goalDef;
  final int goalMid;
  final int goalFwd;
  final int assist;

  /// Zu-Null für Torwart/Abwehr.
  final int cleanSheetGkDef;
  final int yellowCard;
  final int redCard;

  static const kickbaseStyle = FantasyScoring();

  factory FantasyScoring.fromJson(Map<String, dynamic> json) => FantasyScoring(
        appearance: json['appearance'] as int? ?? 2,
        goalGk: json['goalGk'] as int? ?? 6,
        goalDef: json['goalDef'] as int? ?? 6,
        goalMid: json['goalMid'] as int? ?? 5,
        goalFwd: json['goalFwd'] as int? ?? 4,
        assist: json['assist'] as int? ?? 3,
        cleanSheetGkDef: json['cleanSheetGkDef'] as int? ?? 4,
        yellowCard: json['yellowCard'] as int? ?? -1,
        redCard: json['redCard'] as int? ?? -3,
      );

  Map<String, dynamic> toJson() => {
        'appearance': appearance,
        'goalGk': goalGk,
        'goalDef': goalDef,
        'goalMid': goalMid,
        'goalFwd': goalFwd,
        'assist': assist,
        'cleanSheetGkDef': cleanSheetGkDef,
        'yellowCard': yellowCard,
        'redCard': redCard,
      };
}

/// Aufbau eines Kaders: Startelf-Slots pro Position plus Bank.
class RosterConfig {
  const RosterConfig({
    this.gk = 1,
    this.def = 4,
    this.mid = 4,
    this.fwd = 2,
    this.bench = 5,
    this.defMin = 3,
    this.defMax = 5,
    this.midMin = 2,
    this.midMax = 5,
    this.fwdMin = 1,
    this.fwdMax = 3,
  });

  /// Kader-Zusammensetzung (Anzahl der gedrafteten Spieler je „Basis"-Slot
  /// plus Bank). Steuert die Draft-Runden und die Startelf-Größe.
  final int gk;
  final int def;
  final int mid;
  final int fwd;
  final int bench;

  /// Flexible Formation: erlaubte Spanne je Position in der Startelf.
  /// Torwart ist immer genau [gk] (= 1). Die Summe ergibt stets [starters]
  /// (= 11). Defaults im FPL-Stil: ABW 3–5, MF 2–5, ST 1–3.
  final int defMin;
  final int defMax;
  final int midMin;
  final int midMax;
  final int fwdMin;
  final int fwdMax;

  static const standard = RosterConfig();

  /// Gesamtzahl Spieler im Kader = Anzahl der Draft-Runden.
  int get squadSize => gk + def + mid + fwd + bench;
  int get starters => gk + def + mid + fwd;

  /// Neue Konfiguration mit geänderter Rundenzahl (= Kadergröße). Die
  /// Startelf bleibt fix; die Differenz landet auf der Bank.
  RosterConfig withRounds(int rounds) => RosterConfig(
        gk: gk,
        def: def,
        mid: mid,
        fwd: fwd,
        bench: (rounds - starters).clamp(0, 99),
        defMin: defMin,
        defMax: defMax,
        midMin: midMin,
        midMax: midMax,
        fwdMin: fwdMin,
        fwdMax: fwdMax,
      );

  int minFor(PlayerPosition pos) => switch (pos) {
        PlayerPosition.gk => gk,
        PlayerPosition.def => defMin,
        PlayerPosition.mid => midMin,
        PlayerPosition.fwd => fwdMin,
      };

  int maxFor(PlayerPosition pos) => switch (pos) {
        PlayerPosition.gk => gk,
        PlayerPosition.def => defMax,
        PlayerPosition.mid => midMax,
        PlayerPosition.fwd => fwdMax,
      };

  /// Prüft, ob eine Positionsverteilung eine gültige Startelf-Formation ist:
  /// Torwart exakt, Feldspieler in ihrer Spanne, Summe = [starters].
  bool isValidFormation({
    required int gkCount,
    required int defCount,
    required int midCount,
    required int fwdCount,
  }) =>
      gkCount == gk &&
      defCount >= defMin &&
      defCount <= defMax &&
      midCount >= midMin &&
      midCount <= midMax &&
      fwdCount >= fwdMin &&
      fwdCount <= fwdMax &&
      gkCount + defCount + midCount + fwdCount == starters;

  /// Kurzschreibweise der Feldspieler-Formation, z. B. „4-4-2".
  String formationLabel({
    required int defCount,
    required int midCount,
    required int fwdCount,
  }) =>
      '$defCount-$midCount-$fwdCount';

  /// Alle gültigen Feldspieler-Formationen `(def, mid, fwd)` — Torwart ist
  /// immer [gk], die Summe ergibt [starters]. Sortiert nach ABW, dann MF.
  List<(int def, int mid, int fwd)> validFormations() {
    final out = <(int, int, int)>[];
    final outfield = starters - gk;
    for (var d = defMin; d <= defMax; d++) {
      for (var m = midMin; m <= midMax; m++) {
        final f = outfield - d - m;
        if (f < fwdMin || f > fwdMax) continue;
        out.add((d, m, f));
      }
    }
    out.sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
    return out;
  }

  factory RosterConfig.fromJson(Map<String, dynamic> json) => RosterConfig(
        gk: json['gk'] as int? ?? 1,
        def: json['def'] as int? ?? 4,
        mid: json['mid'] as int? ?? 4,
        fwd: json['fwd'] as int? ?? 2,
        bench: json['bench'] as int? ?? 5,
        defMin: json['defMin'] as int? ?? 3,
        defMax: json['defMax'] as int? ?? 5,
        midMin: json['midMin'] as int? ?? 2,
        midMax: json['midMax'] as int? ?? 5,
        fwdMin: json['fwdMin'] as int? ?? 1,
        fwdMax: json['fwdMax'] as int? ?? 3,
      );

  Map<String, dynamic> toJson() => {
        'gk': gk,
        'def': def,
        'mid': mid,
        'fwd': fwd,
        'bench': bench,
        'defMin': defMin,
        'defMax': defMax,
        'midMin': midMin,
        'midMax': midMax,
        'fwdMin': fwdMin,
        'fwdMax': fwdMax,
      };
}

/// Ein Spieler im Pool. Alter und U20-Status werden zu einem Stichtag
/// (1. Spieltag) berechnet — Grundlage der Dynasty-U20-Mechanik.
class FantasyPlayer {
  const FantasyPlayer({
    required this.id,
    required this.name,
    required this.position,
    required this.club,
    required this.birthDate,
    required this.nationality,
    this.isForeignNewcomer = false,
  });

  final String id;
  final String name;
  final PlayerPosition position;
  final String club;
  final DateTime birthDate;

  /// ISO-Ländercode (z. B. 'de', 'gb-eng') für die Flagge.
  final String nationality;

  /// Neuzugang aus dem Ausland — im Dynasty-Modus zusammen mit den
  /// U20-Spielern im Vorsaison-Draft wählbar.
  final bool isForeignNewcomer;

  int ageOn(DateTime date) {
    var age = date.year - birthDate.year;
    final hadBirthday = date.month > birthDate.month ||
        (date.month == birthDate.month && date.day >= birthDate.day);
    if (!hadBirthday) age--;
    return age;
  }

  /// U20 = jünger als 20 Jahre zum Stichtag.
  bool isU20On(DateTime date) => ageOn(date) < 20;

  /// Im U20-Draft wählbar: U20 zum 1. Spieltag der Saison oder
  /// Auslands-Neuzugang. Stichtag ~ 1. August des Saison-Startjahrs.
  /// Muss der Server-Funktion fantasy_is_rookie entsprechen.
  bool isRookieFor(int season) =>
      isForeignNewcomer || isU20On(DateTime(season, 8, 1));

  /// Ab 05.09. (nach Transferschluss) gesperrt: für den U20-Draft
  /// reserviert, nicht per Free Agency holbar. Entspricht
  /// fantasy_is_locked auf dem Server.
  bool isLockedNow(int season) =>
      isRookieFor(season) && !DateTime.now().isBefore(DateTime(season, 9, 5));

  factory FantasyPlayer.fromJson(Map<String, dynamic> json) => FantasyPlayer(
        id: json['id'] as String,
        name: json['name'] as String,
        position: PlayerPosition.fromId(json['position'] as String),
        club: json['club'] as String,
        birthDate: DateTime.parse(json['birth_date'] as String),
        nationality: json['nationality'] as String,
        isForeignNewcomer: json['is_foreign_newcomer'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'position': position.name,
        'club': club,
        'birth_date':
            '${birthDate.year.toString().padLeft(4, '0')}-${birthDate.month.toString().padLeft(2, '0')}-${birthDate.day.toString().padLeft(2, '0')}',
        'nationality': nationality,
        'is_foreign_newcomer': isForeignNewcomer,
      };
}

/// Eine Fantasy-Liga (= Wettbewerb mehrerer Manager).
class FantasyLeague {
  const FantasyLeague({
    required this.id,
    required this.name,
    required this.mode,
    required this.season,
    required this.pickTime,
    required this.scoring,
    required this.roster,
    required this.inviteCode,
    required this.draftStatus,
    required this.createdBy,
    this.picksMade = 0,
    this.currentPickDeadline,
    this.draftPhase = DraftPhase.startup,
    this.u20Rounds = 3,
    this.maxTeams,
    this.pauseStart,
    this.pauseEnd,
    this.playoffTeams,
    this.playoffWeeks,
    this.tradeDeadlineOffset,
    this.draftOrderMode = 'auto',
  });

  final String id;
  final String name;
  final FantasyMode mode;

  /// Startjahr der Saison (z. B. 2025 für 2025/26).
  final int season;
  final DraftPickTime pickTime;
  final FantasyScoring scoring;
  final RosterConfig roster;
  final String inviteCode;
  final DraftStatus draftStatus;
  final String createdBy;

  /// Anzahl bereits getätigter Picks (0-basierter Index des nächsten Picks).
  final int picksMade;

  /// Ablaufzeitpunkt des aktuellen Picks; null außerhalb des laufenden Drafts.
  final DateTime? currentPickDeadline;

  /// Aktuelle Draft-Phase (Dynasty: Haupt- vs. U20-Draft).
  final DraftPhase draftPhase;

  /// Anzahl Runden im U20-Draft (Dynasty).
  final int u20Rounds;

  /// Maximale Teilnehmerzahl (null = unbegrenzt).
  final int? maxTeams;

  /// Slow-Draft-Pausenfenster als Minute des Tages (0–1439, Europe/Berlin);
  /// null = keine Pause. In diesem Fenster picken abgelaufene Picks nicht auto.
  final int? pauseStart;
  final int? pauseEnd;

  /// Playoff-Einstellungen (null = noch nicht konfiguriert).
  final int? playoffTeams;

  /// Dauer einer Playoff-Partie in Spieltagen (1 oder 2).
  final int? playoffWeeks;

  /// Trade-Deadline in Spieltagen vor Playoff-Start (5–10).
  final int? tradeDeadlineOffset;

  /// Draft-Reihenfolge: `auto` (Zufall beim Start) oder `manual` (vorab gesetzt).
  final String draftOrderMode;

  /// Anzahl Draft-Runden insgesamt (= Kadergröße = Startelf + Bank).
  int get rounds => roster.squadSize;

  bool get hasPause => pauseStart != null && pauseEnd != null;
  bool get hasPlayoffs => playoffTeams != null;
  bool get manualDraftOrder => draftOrderMode == 'manual';

  factory FantasyLeague.fromJson(Map<String, dynamic> json) => FantasyLeague(
        id: json['id'] as String,
        name: json['name'] as String,
        mode: FantasyMode.fromId(json['mode'] as String),
        season: json['season'] as int,
        pickTime: DraftPickTime.fromSeconds(json['draft_pick_seconds'] as int),
        scoring: FantasyScoring.fromJson(
            (json['scoring'] as Map<String, dynamic>?) ?? const {}),
        roster: RosterConfig.fromJson(
            (json['roster'] as Map<String, dynamic>?) ?? const {}),
        inviteCode: json['invite_code'] as String,
        draftStatus: _draftStatusFromId(json['draft_status'] as String),
        createdBy: json['created_by'] as String,
        picksMade: json['picks_made'] as int? ?? 0,
        currentPickDeadline: json['current_pick_deadline'] == null
            ? null
            : DateTime.parse(json['current_pick_deadline'] as String),
        draftPhase: DraftPhase.fromId(json['draft_phase'] as String? ?? 'startup'),
        u20Rounds: json['u20_rounds'] as int? ?? 3,
        maxTeams: json['max_teams'] as int?,
        pauseStart: json['draft_pause_start'] as int?,
        pauseEnd: json['draft_pause_end'] as int?,
        playoffTeams: json['playoff_teams'] as int?,
        playoffWeeks: json['playoff_weeks'] as int?,
        tradeDeadlineOffset: json['trade_deadline_offset'] as int?,
        draftOrderMode: json['draft_order_mode'] as String? ?? 'auto',
      );

  /// Picks pro Manager in der aktuellen Phase (= Anzahl Runden). Im
  /// Dynasty-Haupt-Draft bleibt Platz für den U20-Draft, damit die
  /// Kadergröße nicht überschritten wird.
  int get roundsThisPhase {
    if (draftPhase == DraftPhase.u20) return u20Rounds;
    return mode == FantasyMode.dynasty
        ? roster.squadSize - u20Rounds
        : roster.squadSize;
  }
}

/// Ein Kadereintrag (aktueller Besitz eines Spielers in einer Liga).
class RosterEntry {
  const RosterEntry({
    required this.managerId,
    required this.playerId,
    required this.acquiredVia,
  });

  final String managerId;
  final String playerId;
  final String acquiredVia; // draft | fa | waiver

  factory RosterEntry.fromJson(Map<String, dynamic> json) => RosterEntry(
        managerId: json['manager_id'] as String,
        playerId: json['player_id'] as String,
        acquiredVia: json['acquired_via'] as String? ?? 'draft',
      );
}

/// Die für einen Spieltag gewählte Startelf eines Managers. Leer/keine
/// Aufstellung ⇒ es zählt die automatische beste Elf.
class FantasyLineup {
  const FantasyLineup({
    required this.managerId,
    required this.round,
    required this.playerIds,
  });

  final String managerId;
  final int round;
  final Set<String> playerIds;

  factory FantasyLineup.fromJson(Map<String, dynamic> json) => FantasyLineup(
        managerId: json['manager_id'] as String,
        round: json['round'] as int,
        playerIds: {
          for (final id in (json['player_ids'] as List? ?? const []))
            id as String
        },
      );
}

/// Ein getätigter Draft-Pick.
class DraftPick {
  const DraftPick({
    required this.phase,
    required this.pickNumber,
    required this.round,
    required this.managerId,
    required this.playerId,
    required this.isAuto,
  });

  final DraftPhase phase;
  final int pickNumber;
  final int round;
  final String managerId;
  final String playerId;
  final bool isAuto;

  factory DraftPick.fromJson(Map<String, dynamic> json) => DraftPick(
        phase: DraftPhase.fromId(json['phase'] as String? ?? 'startup'),
        pickNumber: json['pick_number'] as int,
        round: json['round'] as int,
        managerId: json['manager_id'] as String,
        playerId: json['player_id'] as String,
        isAuto: json['is_auto'] as bool? ?? false,
      );
}

/// Ein Manager (Mitglied) einer Fantasy-Liga.
class FantasyManager {
  const FantasyManager({
    required this.userId,
    required this.username,
    this.teamName,
    this.draftPosition,
    this.waiverPriority,
    this.vacant = false,
    this.pending = false,
    this.autoPick = false,
  });

  final String userId;

  /// Globaler Nutzername (aus `profiles`).
  final String username;

  /// Ligaspezifischer Anzeigename; null/leer = kein eigener Name.
  final String? teamName;

  /// In der Liga anzuzeigender Name: Teamname, sonst der Nutzername.
  String get display =>
      (teamName?.trim().isNotEmpty ?? false) ? teamName!.trim() : username;

  /// Position in der Draft-Reihenfolge (1-basiert), null bis ausgelost.
  final int? draftPosition;

  /// Rollende Waiver-Priorität (1 = zuerst dran), null bis zur ersten
  /// Waiver-Abarbeitung.
  final int? waiverPriority;

  /// Verwaistes Team: der bisherige Manager hat die Liga verlassen/ wurde
  /// gekickt; der Kader bleibt, bis der Admin einen neuen Nutzer zuweist.
  final bool vacant;

  /// Nach Draft-Start beigetretenes Mitglied ohne Team; wartet darauf, dass der
  /// Admin es einem verwaisten Team zuweist. Zählt nicht als Team/Manager.
  final bool pending;

  /// Auto-Pick aktiv: der Manager ist abwesend, der Server draftet für ihn
  /// (aus der Queue bzw. bestem verfügbaren Spieler).
  final bool autoPick;

  FantasyManager copyWith({int? draftPosition, int? waiverPriority}) =>
      FantasyManager(
        userId: userId,
        username: username,
        teamName: teamName,
        draftPosition: draftPosition ?? this.draftPosition,
        waiverPriority: waiverPriority ?? this.waiverPriority,
        vacant: vacant,
        pending: pending,
        autoPick: autoPick,
      );

  factory FantasyManager.fromJson(Map<String, dynamic> json) => FantasyManager(
        userId: json['user_id'] as String,
        username:
            (json['profiles'] as Map<String, dynamic>?)?['username'] as String? ??
                '?',
        teamName: json['team_name'] as String?,
        draftPosition: json['draft_position'] as int?,
        waiverPriority: json['waiver_priority'] as int?,
        vacant: json['vacant'] as bool? ?? false,
        pending: json['pending'] as bool? ?? false,
        autoPick: json['auto_pick'] as bool? ?? false,
      );
}

/// Status eines Waiver-Antrags (entspricht der Server-Enum).
enum WaiverStatus {
  pending('Offen'),
  won('Erfolgreich'),
  lost('Verpasst'),
  invalid('Ungültig'),
  cancelled('Storniert');

  const WaiverStatus(this.label);

  final String label;

  bool get isPending => this == WaiverStatus.pending;

  static WaiverStatus fromId(String id) => values.firstWhere(
        (s) => s.name == id,
        orElse: () => WaiverStatus.pending,
      );
}

/// Ein Waiver-Antrag: hole [addPlayerId], gib dafür optional [dropPlayerId]
/// ab. Wird terminiert in Prioritätsreihenfolge abgearbeitet.
class WaiverClaim {
  const WaiverClaim({
    required this.id,
    required this.leagueId,
    required this.managerId,
    required this.addPlayerId,
    required this.rank,
    required this.status,
    required this.createdAt,
    this.dropPlayerId,
    this.reason,
  });

  final String id;
  final String leagueId;
  final String managerId;
  final String addPlayerId;
  final String? dropPlayerId;

  /// Eigene Reihenfolge mehrerer Anträge (1 = wichtigster).
  final int rank;
  final WaiverStatus status;
  final String? reason;
  final DateTime createdAt;

  factory WaiverClaim.fromJson(Map<String, dynamic> json) => WaiverClaim(
        id: json['id'] as String,
        leagueId: json['league_id'] as String,
        managerId: json['manager_id'] as String,
        addPlayerId: json['add_player_id'] as String,
        dropPlayerId: json['drop_player_id'] as String?,
        rank: json['rank'] as int? ?? 1,
        status: WaiverStatus.fromId(json['status'] as String? ?? 'pending'),
        reason: json['reason'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
