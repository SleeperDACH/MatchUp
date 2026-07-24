-- Altzustände normalisieren: Ligen, die mit dem früheren Rollover in den
-- „U20 steht an"-Zustand kamen (u20_draft_pending = true, draft_status = 'done'),
-- in den neuen U20-Setup überführen — draft_status = 'setup', draft_phase =
-- 'u20'. Dadurch erscheint der U20-Draft wieder (im Draft-Raum startbar) und
-- draftet den U20-Pool statt „nichts / voller Kader".
update public.fantasy_leagues
   set draft_status = 'setup',
       draft_phase = 'u20',
       u20_draft_pending = false,
       picks_made = 0,
       current_pick_deadline = null,
       draft_started_at = null
 where mode = 'dynasty'
   and u20_draft_pending = true
   and draft_status = 'done';

-- Sicherheitsnetz: falls durch einen alten Rollover bereits ein regulärer
-- Draft-Verlauf der neuen Saison entstanden ist, den U20-Setup nicht mit
-- Alt-Picks vermischen (die Kader stecken in fantasy_rosters).
delete from public.draft_picks dp
 using public.fantasy_leagues fl
 where dp.league_id = fl.id
   and fl.draft_status = 'setup'
   and fl.draft_phase = 'u20';
