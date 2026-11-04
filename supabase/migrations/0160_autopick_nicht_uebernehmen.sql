-- 0160: Auto-Pick gilt nur für einen Draft (31.10.2026, gemeldet: „auf dem
-- Draft-Board haben manche noch Auto-Pick vom vorherigen Draft drin —
-- Auto-Picks werden nicht mit in neue Drafts übernommen").
--
-- fantasy_league_members.auto_pick wurde nie zurückgesetzt: In MatchUp! #1
-- standen nach dem ersten Draft 12 von 18 Managern auf Auto-Pick und hätten
-- im Reset-Draft am 24.12. ohne eigenes Zutun automatisch gepickt.
--
-- Jetzt: Endet ein Draft (draft_status → done) oder beginnt der Reset
-- (→ reset), steht Auto-Pick für alle Mitglieder wieder auf aus. Wer im
-- nächsten Draft automatisch picken will, schaltet es dort neu ein.

create or replace function public.fantasy_autopick_zuruecksetzen()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if new.draft_status is distinct from old.draft_status
     and new.draft_status in ('done', 'reset') then
    update fantasy_league_members
       set auto_pick = false
     where league_id = new.id
       and auto_pick;
  end if;
  return new;
end$$;

revoke all on function public.fantasy_autopick_zuruecksetzen() from public, anon, authenticated;

drop trigger if exists fantasy_autopick_zuruecksetzen on public.fantasy_leagues;
create trigger fantasy_autopick_zuruecksetzen
  after update of draft_status on public.fantasy_leagues
  for each row execute function public.fantasy_autopick_zuruecksetzen();

-- Bestand: überall, wo gerade kein Draft läuft.
update public.fantasy_league_members m
   set auto_pick = false
  from public.fantasy_leagues l
 where l.id = m.league_id
   and m.auto_pick
   and l.draft_status <> 'drafting';
