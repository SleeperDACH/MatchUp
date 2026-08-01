-- FK-sichere Entfernung abgewanderter Spieler für den automatischen Kader-Sync
-- (Edge-Function `sync-squads`).
--
-- "Abgang" = ein Sportmonks-Spieler, dessen `club` noch als Bundesliga-Klub
-- geführt wird, der aber nicht mehr im aktuellen Kader (p_current_ids) steht —
-- also z. B. ins Ausland gewechselt. Anders als der einmalige Saison-Import darf
-- ein regelmäßiger Sync niemandem einen bereits gedrafteten Spieler still aus
-- dem Kader reißen: Deshalb werden Abgänge NUR gelöscht, wenn sie in KEINER der
-- referenzierenden Tabellen vorkommen (nicht gedraftet, nicht im Kader, keine
-- Trades/Waiver, keine Match-Stats). Reine Wunschlisten-Einträge werden vorher
-- geleert (harmlos) und blockieren die Löschung damit nicht.
--
-- Rückgabe: (deleted, kept) — wie viele Abgänge entfernt wurden bzw. wegen
-- Referenzen stehen blieben.

create or replace function public.fantasy_prune_departed_players(
  p_current_ids text[], p_bl_clubs text[])
returns table(deleted int, kept int)
language plpgsql security definer set search_path = public as $$
declare
  v_departed int;
  v_deleted int;
begin
  -- Wie viele Abgänge gibt es insgesamt?
  select count(*) into v_departed
    from public.players
    where id like 'sportmonks:%'
      and club = any(p_bl_clubs)
      and not (id = any(p_current_ids));

  -- Wunschlisten der Abgänge leeren (harmlos), damit nur gewünschte Abgänge
  -- nicht fälschlich als "referenziert" gelten.
  delete from public.fantasy_draft_queue q
    where q.player_id in (
      select id from public.players
      where id like 'sportmonks:%'
        and club = any(p_bl_clubs)
        and not (id = any(p_current_ids)));

  -- Löschbar = Abgang ohne "harte" Referenz.
  with del as (
    delete from public.players p
    where p.id like 'sportmonks:%'
      and p.club = any(p_bl_clubs)
      and not (p.id = any(p_current_ids))
      and not exists (select 1 from public.draft_picks x where x.player_id = p.id)
      and not exists (select 1 from public.fantasy_rosters x where x.player_id = p.id)
      and not exists (select 1 from public.fantasy_trade_items x where x.player_id = p.id)
      and not exists (select 1 from public.fantasy_waiver_players x where x.player_id = p.id)
      and not exists (select 1 from public.fantasy_waiver_claims x
                        where x.add_player_id = p.id or x.drop_player_id = p.id)
      and not exists (select 1 from public.player_match_stats x where x.player_id = p.id)
    returning p.id)
  select count(*) into v_deleted from del;

  deleted := v_deleted;
  kept := v_departed - v_deleted;
  return next;
end$$;

-- Nur der Server (Service-Role, über die geschützte Edge-Function) darf prunen.
revoke all on function public.fantasy_prune_departed_players(text[], text[])
  from public, anon, authenticated;
grant execute on function public.fantasy_prune_departed_players(text[], text[])
  to service_role;
