-- Ob eine Fantasy-Liga ein ligainternes Tippspiel anbietet. Steuert, ob die
-- Tippspiel-Option auf dem Übersichtsscreen erscheint. Beim Erstellen wählbar,
-- sonst später in den Liga-Einstellungen einschaltbar.
alter table public.fantasy_leagues
  add column tip_enabled boolean not null default false;

-- Bereits gekoppelte (aktivierte) Tippspiele bleiben sichtbar.
update public.fantasy_leagues fl
   set tip_enabled = true
 where exists (
   select 1 from public.tip_rounds tr where tr.fantasy_league_id = fl.id
 );
