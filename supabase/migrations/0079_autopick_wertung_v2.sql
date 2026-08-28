-- Der Auto-Pick stolperte über die eigene Wertung.
--
-- Seit der Umstellung auf die v2-Wertung sind Fantasy-Punkte `double`
-- (`assist: 12.0`, `yellowCard: -4.0`). Die Rangliste im Auto-Pick castete sie
-- weiter mit `::int` — und `'12.0'::int` ist in Postgres kein Rundungsfehler,
-- sondern `22P02 invalid input syntax for type integer`.
--
-- Damit warf `fantasy_autopick_if_expired` in **jeder** Liga mit v2-Wertung bei
-- **jedem** Aufruf. Der Draft-Raum ruft sie im Sekundentakt; der Fehler landete
-- in einem Future, auf das niemand hörte. Sichtbar war deshalb nur: die Uhr
-- läuft ab, und es passiert nichts. Zwei Ligen standen so fest, eine davon
-- siebzehneinhalb Stunden.
--
-- Drei Änderungen:
--
--  1. **Gerechnet wird in `numeric`**, nicht in `int`. Punkte sind seit v2
--     Kommazahlen (1,5 je Torschussvorlage, −0,4 je Foul) — dieselbe Regel,
--     die in Dart `formatPoints()` nötig macht.
--  2. **Die v2-Schlüssel werden gelesen.** Die alten Namen `appearance`,
--     `goalGk/Def/Mid/Fwd` und `cleanSheetGkDef` gibt es in v2 gar nicht mehr;
--     die Rangliste fiel für jede neue Liga still auf die Gewichte des alten
--     6-Kategorien-Modells zurück. Sie hätte also auch nach dem Cast-Fix noch
--     nach der falschen Wertung sortiert — nur eben ohne Fehlermeldung, und
--     das ist die schlechtere Sorte Fehler.
--  3. **`fantasy_num` liest jede Zahl defensiv.** Ein Wert, der nicht als Zahl
--     durchgeht, ergibt den Vorgabewert statt einer Exception. Der Auto-Pick
--     ist die Notbremse des Drafts; er darf an einer krummen Konfiguration
--     nicht sterben, sonst hängt wieder die ganze Liga.
--
-- Was hier **nicht** steht: die vollständige v2-Wertung. Sie liegt in
-- `scoring.config.json` und `fantasy_scoring_rules.dart` und soll keine dritte
-- Kopie bekommen. Diese Funktion braucht nur eine Reihenfolge, keine Punkte.
-- Zwei Werte müssen trotzdem hier stehen, weil `toJson()` sie gar nicht
-- serialisiert: die Einsatzpunkte (v2: 10 für volle 90 Minuten) und die Null
-- hinten (v2: 12 für Torwart und Abwehr). Wer sie in der Wertung ändert,
-- ändert sie hier mit.

-- Zahl aus JSONB, mit Vorgabewert statt Ausnahme.
create or replace function public.fantasy_num(
  p_json jsonb, p_key text, p_default numeric
) returns numeric language sql immutable as $$
  select case
    when p_json->>p_key ~ '^\s*-?[0-9]+(\.[0-9]+)?\s*$'
      then (p_json->>p_key)::numeric
    else p_default
  end;
$$;

comment on function public.fantasy_num(jsonb, text, numeric) is
  'Liest eine Zahl aus einer Wertungs-JSONB. Nicht lesbare Werte ergeben den '
  'Vorgabewert — der Auto-Pick darf an einer krummen Konfiguration nicht '
  'sterben, sonst hängt der ganze Draft.';

create or replace function public.fantasy_autopick_if_expired(p_league_id uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare
  v_status text; v_deadline timestamptz; v_manager uuid; v_player text;
  v_mode text; v_phase text; v_season int; v_away boolean; v_expired boolean;
  v_scoring jsonb; v_last_season int; v_roster jsonb;
  v_tgt_gk int; v_tgt_def int; v_tgt_mid int; v_tgt_fwd int;
  v_cnt_gk int; v_cnt_def int; v_cnt_mid int; v_cnt_fwd int;
  v_starter_phase boolean; v_v2 boolean;
  -- Gewichte der Rangliste, einmal aufgelöst statt neunmal im ORDER BY.
  v_w_app numeric; v_w_assist numeric; v_w_cs numeric;
  v_w_yellow numeric; v_w_red numeric;
  v_w_goal_gk numeric; v_w_goal_def numeric;
  v_w_goal_mid numeric; v_w_goal_fwd numeric;
begin
  select draft_status, current_pick_deadline, mode, draft_phase, season,
         scoring, roster
    into v_status, v_deadline, v_mode, v_phase, v_season, v_scoring, v_roster
    from fantasy_leagues where id = p_league_id for update;
  if v_status <> 'drafting' then return false; end if;

  -- Letzte abgeschlossene Saison für die Ranking-Punkte — kalenderbasiert wie
  -- der Client (Saison = Startjahr; ab Juli das laufende Jahr), minus 1.
  v_last_season := (case when extract(month from now())::int >= 7
                         then extract(year from now())::int
                         else extract(year from now())::int - 1 end) - 1;

  if auth.uid() is not null and not public.is_fantasy_member(p_league_id) then
    raise exception 'Kein Mitglied dieser Liga';
  end if;

  v_manager := public.fantasy_current_manager(p_league_id);
  select coalesce(auto_pick, false) into v_away
    from fantasy_league_members
    where league_id = p_league_id and user_id = v_manager;

  v_expired := v_deadline is not null and now() > v_deadline;
  if not v_expired and not coalesce(v_away, false) then return false; end if;

  -- Kader-Sollwerte (gleiche Defaults wie fantasy_squad_size).
  v_tgt_gk  := coalesce((v_roster->>'gk')::int, 1);
  v_tgt_def := coalesce((v_roster->>'def')::int, 4);
  v_tgt_mid := coalesce((v_roster->>'mid')::int, 4);
  v_tgt_fwd := coalesce((v_roster->>'fwd')::int, 2);

  -- Aktuelle Kaderzusammensetzung des Managers.
  select count(*) filter (where p.position = 'gk'),
         count(*) filter (where p.position = 'def'),
         count(*) filter (where p.position = 'mid'),
         count(*) filter (where p.position = 'fwd')
    into v_cnt_gk, v_cnt_def, v_cnt_mid, v_cnt_fwd
    from fantasy_rosters r join players p on p.id = r.player_id
    where r.league_id = p_league_id and r.manager_id = v_manager;

  -- Startelf-Phase, solange irgendeine Positionsgruppe noch nicht voll ist.
  v_starter_phase := v_cnt_gk  < v_tgt_gk  or v_cnt_def < v_tgt_def
                  or v_cnt_mid < v_tgt_mid or v_cnt_fwd < v_tgt_fwd;

  -- Wertungs-Gewichte auflösen. v2 kennt ein flaches `goal` für alle
  -- Positionen; das alte Modell hatte vier getrennte Werte.
  v_v2 := public.fantasy_num(v_scoring, 'version', 1) >= 2;
  if v_v2 then
    v_w_app       := 10;  -- volle 90 Minuten, siehe Kopfkommentar
    v_w_cs        := 12;  -- Zu Null (Torwart/Abwehr), siehe Kopfkommentar
    v_w_assist    := public.fantasy_num(v_scoring, 'assist', 12);
    v_w_yellow    := public.fantasy_num(v_scoring, 'yellowCard', -4);
    v_w_red       := public.fantasy_num(v_scoring, 'redCard', -10);
    v_w_goal_gk   := public.fantasy_num(v_scoring, 'goal', 16);
    v_w_goal_def  := v_w_goal_gk;
    v_w_goal_mid  := v_w_goal_gk;
    v_w_goal_fwd  := v_w_goal_gk;
  else
    v_w_app       := public.fantasy_num(v_scoring, 'appearance', 2);
    v_w_cs        := public.fantasy_num(v_scoring, 'cleanSheetGkDef', 4);
    v_w_assist    := public.fantasy_num(v_scoring, 'assist', 3);
    v_w_yellow    := public.fantasy_num(v_scoring, 'yellowCard', -1);
    v_w_red       := public.fantasy_num(v_scoring, 'redCard', -3);
    v_w_goal_gk   := public.fantasy_num(v_scoring, 'goalGk', 6);
    v_w_goal_def  := public.fantasy_num(v_scoring, 'goalDef', 6);
    v_w_goal_mid  := public.fantasy_num(v_scoring, 'goalMid', 5);
    v_w_goal_fwd  := public.fantasy_num(v_scoring, 'goalFwd', 4);
  end if;

  -- Queue zuerst (nach Wunschreihenfolge des Managers) — gewinnt immer,
  -- unabhängig von der Position.
  select q.player_id into v_player
    from fantasy_draft_queue q join players p on p.id = q.player_id
    where q.league_id = p_league_id and q.manager_id = v_manager
      and q.player_id not in
          (select player_id from fantasy_rosters where league_id = p_league_id)
      and (v_mode <> 'dynasty'
           or v_phase <> 'u20'
           or public.fantasy_is_rookie(p.birth_date, p.is_foreign_newcomer, v_season))
    order by q.rank limit 1;

  -- Rückfall: bester freier, phasen-gültiger Spieler nach projizierten
  -- Vorsaison-Punkten (gleiche Formel wie die Client-Draftreihung), aber
  -- positions-priorisiert (Startelf vor Bank, siehe 0072).
  if v_player is null then
    select p.id into v_player
      from players p
      left join player_season_totals t
        on t.player_id = p.id and t.season = v_last_season
      where p.id not in
            (select player_id from fantasy_rosters where league_id = p_league_id)
        and (v_mode <> 'dynasty'
             or v_phase <> 'u20'
             or public.fantasy_is_rookie(p.birth_date, p.is_foreign_newcomer, v_season))
      order by
        -- Positions-Priorität (kleiner = zuerst).
        (case when v_starter_phase then
           -- Startelf: noch offene Gruppen zuerst (0), volle Gruppen zuletzt (1).
           case p.position
             when 'gk'  then (case when v_cnt_gk  < v_tgt_gk  then 0 else 1 end)
             when 'def' then (case when v_cnt_def < v_tgt_def then 0 else 1 end)
             when 'mid' then (case when v_cnt_mid < v_tgt_mid then 0 else 1 end)
             else            (case when v_cnt_fwd < v_tgt_fwd then 0 else 1 end)
           end
         else
           -- Bank: kein Torwart (ganz nach hinten), sonst gleichmäßig über
           -- def/mid/fwd — Gruppe mit den wenigsten Bankspielern zuerst.
           case p.position
             when 'gk'  then 1000000
             when 'def' then (v_cnt_def - v_tgt_def)
             when 'mid' then (v_cnt_mid - v_tgt_mid)
             else            (v_cnt_fwd - v_tgt_fwd)
           end
         end) asc,
        (
          coalesce(t.appearances, 0) * v_w_app
        + coalesce(t.goals, 0) * (case p.position
            when 'gk'  then v_w_goal_gk
            when 'def' then v_w_goal_def
            when 'mid' then v_w_goal_mid
            else            v_w_goal_fwd end)
        + coalesce(t.assists, 0) * v_w_assist
        + (case when p.position in ('gk', 'def')
                then coalesce(t.clean_sheets, 0) * v_w_cs
                else 0 end)
        + coalesce(t.yellow, 0) * v_w_yellow
        + coalesce(t.red, 0) * v_w_red
      ) desc, p.name asc
      limit 1;
  end if;

  if v_player is null then
    update fantasy_leagues
      set draft_status = 'done', current_pick_deadline = null
      where id = p_league_id;
    return false;
  end if;

  if v_expired then
    update fantasy_league_members set auto_pick = true
      where league_id = p_league_id and user_id = v_manager;
  end if;

  perform public.fantasy_advance(p_league_id, v_manager, v_player, true);
  return true;
end$$;
