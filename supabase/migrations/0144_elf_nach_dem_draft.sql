-- Nach jedem Draft steht eine Elf aus der Pick-Reihenfolge (20.10.2026, auf
-- Ansage) — nach dem ersten Draft einer Liga wie nach dem Reset-Draft.
--
-- Ohne das geht, wer nach dem Draft nicht selbst aufstellt, mit null Punkten
-- in den ersten Spieltag. Nach dem Reset (0143) ist es besonders deutlich: Die
-- Kader sind leer, und die Übernahme der Vorwoche (0110) findet niemanden mehr.
--
-- Die Regel: **Wer zuerst gezogen wurde, steht in der Startelf**, aufgefüllt
-- nach der Standardaufstellung **4-3-3** (1 TW, 4 ABW, 3 MF, 3 ST) — nicht
-- nach der Grundformation der Liga (4-4-2). Die Picks des Managers werden in
-- Pick-Reihenfolge durchgegangen; ein Spieler kommt in die Elf, solange auf
-- seiner Position noch ein Platz frei ist. Fünf Stürmer oder sechs
-- Mittelfeldspieler kommen so nie hinein. Der Auto-Pick füllt Positionen nach
-- Bedarf auf, also ist die Elf im Normalfall vollständig; fehlt doch eine
-- Position, bleibt der Platz leer (dieselbe Regel wie überall: lieber sichtbar
-- leer als falsch besetzt).
--
-- Drei Dinge daran:
--
-- * **Sofort mit dem letzten Pick**, per Trigger auf `draft_status = 'done'`,
--   in derselben Transaktion — er kann nicht verpasst werden. Bewusst **nicht**
--   zusätzlich im Takt (0110): Dort liefe es über jede bestehende Liga, und
--   Manager, die nie eine Elf gestellt haben, bekämen mitten in der Saison
--   eine aus einem Draft, der Wochen her ist.
-- * **Für den ersten Spieltag, der noch nicht angepfiffen ist.** Endet der
--   Draft mitten in einem Spieltag, gilt die Elf ab dem nächsten — eine Elf in
--   eine laufende Runde zu schreiben hieße, Punkte rückwirkend zu verteilen
--   (der Fehler aus 0113–0115).
-- * **Nur einmal, und Handarbeit gewinnt.** Danach übernimmt 0110 wie gewohnt
--   die Vorwoche; was ein Manager selbst stellt, wird nie überschrieben. Eine
--   vorhandene Zeile für den Zielspieltag wird nur ersetzt, wenn keiner ihrer
--   Spieler im Kader steht — das sind die Zeilen, die vor dem Reset aus der
--   Vorwoche übernommen und beim Leeren der Kader (Trigger aus 0115)
--   ausgeräumt wurden.

create or replace function public.fantasy_draft_elf(p_league_id uuid, p_manager uuid)
returns text[]
language sql stable security definer set search_path to 'public' as $$
  with picks as (
    select dp.player_id, dp.pick_number,
           row_number() over (partition by p.position order by dp.pick_number) as nr,
           p.position
      from draft_picks dp
      join players p on p.id = dp.player_id
     where dp.league_id = p_league_id
       and dp.manager_id = p_manager
       and dp.phase = (select draft_phase from fantasy_leagues where id = p_league_id)
       and exists (select 1 from fantasy_rosters r
                    where r.league_id = dp.league_id
                      and r.manager_id = dp.manager_id
                      and r.player_id = dp.player_id)
  )
  select coalesce(array_agg(player_id order by pick_number), '{}')
    from picks
   where nr <= case position when 'gk' then 1 when 'def' then 4
                             when 'mid' then 3 when 'fwd' then 3 else 0 end;
$$;

create or replace function public.fantasy_draft_elf_eintragen(p_league_id uuid)
returns int
language plpgsql security definer set search_path to 'public' as $$
declare l record; v_runde int; n int;
begin
  select id, season, reset_erfolgt_at, draft_status, draft_phase into l
    from fantasy_leagues where id = p_league_id;
  if l.id is null or l.draft_status <> 'done' then
    return 0;
  end if;

  -- Erster Bundesliga-Spieltag, der noch nicht angepfiffen ist.
  select min(x.runde) into v_runde
    from (select f.round as runde
            from fixtures f
           where f.league_id = 'bundesliga' and f.id like 'sportmonks:%'
             and f.season = l.season
           group by f.round
          having min(f.kickoff) > now()) x;
  if v_runde is null then return 0; end if;

  insert into fantasy_lineups (league_id, manager_id, season, round, player_ids)
  select l.id, m.user_id, l.season, v_runde, e.elf
    from fantasy_league_members m
    cross join lateral (select public.fantasy_draft_elf(l.id, m.user_id) as elf) e
   where m.league_id = l.id and not m.vacant
     and cardinality(e.elf) > 0
     -- Nur einmal: Hat er seit diesem Draft schon eine Elf für einen früheren
     -- Spieltag, übernimmt ab hier 0110. Beim ersten Draft einer Liga gibt
     -- es keine früheren Elfen, nach dem Reset zählen nur neuere.
     and not exists (
           select 1 from fantasy_lineups a
            where a.league_id = l.id and a.manager_id = m.user_id
              and a.season = l.season and a.round < v_runde
              and a.updated_at > coalesce(l.reset_erfolgt_at, '-infinity')
              and cardinality(a.player_ids) > 0)
  on conflict (league_id, manager_id, season, round) do update
     set player_ids = excluded.player_ids, updated_at = now()
   where not exists (
           select 1 from unnest(fantasy_lineups.player_ids) as pid
             join fantasy_rosters r
               on r.league_id = fantasy_lineups.league_id
              and r.manager_id = fantasy_lineups.manager_id
              and r.player_id = pid);

  get diagnostics n = row_count;
  return n;
end $$;

create or replace function public.fantasy_draft_fertig()
returns trigger
language plpgsql security definer set search_path to 'public' as $$
begin
  if new.draft_status = 'done' and old.draft_status is distinct from 'done' then
    perform public.fantasy_draft_elf_eintragen(new.id);
  end if;
  return null;
end $$;

drop trigger if exists fantasy_draft_fertig on public.fantasy_leagues;
create trigger fantasy_draft_fertig
  after update of draft_status on public.fantasy_leagues
  for each row execute function public.fantasy_draft_fertig();

-- 0110 mit einer Änderung: Eine Übernahme, nach der **niemand** mehr übrig
-- ist, legt keine leere Zeile mehr an. Die stand sonst nach dem Reset für jeden
-- Manager da, und eine vorhandene Zeile gilt hier als „gestellt".
create or replace function public.fantasy_aufstellung_uebernehmen()
returns int language plpgsql security definer set search_path to 'public' as $$
declare
  l record; v_runde int; v_zahl int; n int := 0;
begin
  for l in select id, season from fantasy_leagues where draft_status = 'done' loop
    v_runde := public.fantasy_laufende_runde(l.season);
    continue when v_runde is null or v_runde <= 1;

    insert into fantasy_lineups (league_id, manager_id, season, round, player_ids)
    select u.league_id, u.manager_id, u.season, v_runde, u.elf
      from (
        select v.league_id, v.manager_id, v.season,
               array(
                 select pid from unnest(v.player_ids) as pid
                  where exists (select 1 from fantasy_rosters r
                                where r.league_id = v.league_id
                                  and r.manager_id = v.manager_id
                                  and r.player_id = pid)) as elf
          from (
            -- Je Manager die juengste Aufstellung vor dieser Runde.
            select distinct on (a.manager_id) a.*
              from fantasy_lineups a
             where a.league_id = l.id and a.season = l.season and a.round < v_runde
               and cardinality(a.player_ids) > 0
             order by a.manager_id, a.round desc
          ) v
         where not exists (
                 select 1 from fantasy_lineups vorhanden
                  where vorhanden.league_id = v.league_id
                    and vorhanden.manager_id = v.manager_id
                    and vorhanden.season = v.season
                    and vorhanden.round = v_runde)
           -- Verwaiste Teams brauchen keine Elf.
           and exists (select 1 from fantasy_league_members m
                        where m.league_id = v.league_id and m.user_id = v.manager_id
                          and not m.vacant)
      ) u
     where cardinality(u.elf) > 0;

    get diagnostics v_zahl = row_count;
    n := n + v_zahl;
  end loop;
  return n;
end$$;

revoke all on function public.fantasy_draft_elf(uuid, uuid) from public, anon, authenticated;
revoke all on function public.fantasy_draft_elf_eintragen(uuid) from public, anon, authenticated;
revoke all on function public.fantasy_draft_fertig() from public, anon, authenticated;
