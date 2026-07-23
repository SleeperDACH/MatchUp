-- Beim Löschen einer Fantasy-Liga soll die gekoppelte Tipprunde nicht mehr
-- zwangsweise mitgelöscht werden — der Admin entscheidet im Client. Daher der
-- FK von ON DELETE CASCADE auf ON DELETE SET NULL: löscht der Admin nur die
-- Liga (Tippspiel behalten), wird die Runde entkoppelt und lebt als
-- eigenständige Tipprunde weiter. Das „Mitlöschen" erledigt der Client, indem
-- er die Tipprunde vor der Liga separat löscht.
alter table public.tip_rounds
  drop constraint if exists tip_rounds_fantasy_league_id_fkey;
alter table public.tip_rounds
  add constraint tip_rounds_fantasy_league_id_fkey
    foreign key (fantasy_league_id) references public.fantasy_leagues (id)
    on delete set null;
