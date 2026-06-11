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
        FantasyMode.liga => 'Liga',
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
  });

  final int gk;
  final int def;
  final int mid;
  final int fwd;
  final int bench;

  static const standard = RosterConfig();

  /// Gesamtzahl Spieler im Kader = Anzahl der Draft-Runden.
  int get squadSize => gk + def + mid + fwd + bench;
  int get starters => gk + def + mid + fwd;

  factory RosterConfig.fromJson(Map<String, dynamic> json) => RosterConfig(
        gk: json['gk'] as int? ?? 1,
        def: json['def'] as int? ?? 4,
        mid: json['mid'] as int? ?? 4,
        fwd: json['fwd'] as int? ?? 2,
        bench: json['bench'] as int? ?? 5,
      );

  Map<String, dynamic> toJson() => {
        'gk': gk,
        'def': def,
        'mid': mid,
        'fwd': fwd,
        'bench': bench,
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
    this.draftPosition,
    this.waiverPriority,
  });

  final String userId;
  final String username;

  /// Position in der Draft-Reihenfolge (1-basiert), null bis ausgelost.
  final int? draftPosition;

  /// Rollende Waiver-Priorität (1 = zuerst dran), null bis zur ersten
  /// Waiver-Abarbeitung.
  final int? waiverPriority;

  FantasyManager copyWith({int? draftPosition, int? waiverPriority}) =>
      FantasyManager(
        userId: userId,
        username: username,
        draftPosition: draftPosition ?? this.draftPosition,
        waiverPriority: waiverPriority ?? this.waiverPriority,
      );

  factory FantasyManager.fromJson(Map<String, dynamic> json) => FantasyManager(
        userId: json['user_id'] as String,
        username:
            (json['profiles'] as Map<String, dynamic>?)?['username'] as String? ??
                '?',
        draftPosition: json['draft_position'] as int?,
        waiverPriority: json['waiver_priority'] as int?,
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
