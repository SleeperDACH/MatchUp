-- Korrekturen an Quellfehlern — und ein Detektor, der sie findet.
--
-- Anlass: Giannis Konstantelias hat im Spiel Dortmund gegen HSV (29.08., 2:0)
-- das 2:0 kurz vor der Pause erzielt. **Sportmonks verbucht dieses Tor als
-- Eigentor von Sebastiaan Bornauw** und schreibt Bornauw zusaetzlich
-- `goals: 1` gut. Bei uns stand damit ein Innenverteidiger des HSV mit einem
-- Tor da, obwohl der HSV null Tore erzielt hat — und dem tatsaechlichen
-- Torschuetzen fehlten 15 Punkte.
--
-- Unsere Spiegelung ist dabei fehlerfrei: 1640 Einzelwerte ueber sieben
-- Partien stimmen exakt mit der Quelle ueberein. Der Fehler steckt in der
-- Quelle selbst, und sie widerspricht sich sogar intern (`goals: 1` neben
-- `own-goals: 1` fuer dasselbe Ereignis).
--
-- Zwei Dinge folgen daraus.

-- ---------------------------------------------------------------------------
-- 1) Ein Detektor: mehr Tore als die eigene Mannschaft
-- ---------------------------------------------------------------------------
-- Die Regel ist hart und allgemein: Ein Spieler kann nicht mehr Tore erzielt
-- haben als seine Mannschaft im selben Spiel. Sie findet genau diese Sorte
-- Fehlattribution — angewandt auf den Bestand traf sie exakt eine Zeile, und
-- zwar die richtige.
--
-- **Eigentore sind kein Widerspruch**: Josha Vagnoman hat im selben Spieltag
-- ein regulaeres Tor UND ein Eigentor erzielt, seine `goals: 1` ist korrekt.
-- Deshalb prueft die Sicht gegen die Teamtore, nicht gegen `own_goals`.
create or replace view public.stats_widersprueche
with (security_invoker = true) as
with tore_je_team as (
  select f.season, f.round, f.home_name as verein, f.home_score as tore
    from public.fixtures f
   where f.league_id = 'bundesliga' and f.id like 'sportmonks:%'
     and f.status = 'finished'
  union all
  select f.season, f.round, f.away_name, f.away_score
    from public.fixtures f
   where f.league_id = 'bundesliga' and f.id like 'sportmonks:%'
     and f.status = 'finished'
)
select s.season, s.round, s.player_id, p.name, p.club,
       'mehr Tore als die Mannschaft' as widerspruch,
       s.goals as wert, t.tore as vergleich
  from public.player_match_stats s
  join public.players p on p.id = s.player_id
  join tore_je_team t
    on t.season = s.season and t.round = s.round and t.verein = p.club
 where s.goals > t.tore;

grant select on public.stats_widersprueche to authenticated, anon;

-- ---------------------------------------------------------------------------
-- 2) Korrekturen, die einen Sync ueberleben
-- ---------------------------------------------------------------------------
-- `sync-stats` schreibt per Upsert und laeuft jede Minute; eine von Hand
-- geaenderte Zeile waere binnen sechzig Sekunden wieder ueberschrieben. Die
-- Korrektur muss deshalb **neben** den Daten stehen und bei jedem Schreiben
-- neu angewandt werden.
create table if not exists public.stat_overrides (
  season      int    not null,
  round       int    not null,
  player_id   text   not null references public.players(id) on delete cascade,
  feld        text   not null,
  wert        numeric not null,
  grund       text   not null,
  angelegt_am timestamptz not null default now(),
  primary key (season, round, player_id, feld)
);

alter table public.stat_overrides enable row level security;
drop policy if exists "Korrekturen lesen" on public.stat_overrides;
create policy "Korrekturen lesen" on public.stat_overrides
  for select to authenticated using (true);

-- Der Trigger laeuft **vor** dem Schreiben und biegt die Zeile zurecht. Ueber
-- `to_jsonb`/`jsonb_populate_record`, damit er beliebige Spalten treffen kann,
-- ohne sie einzeln aufzuzaehlen — sonst waere er beim naechsten neuen Zaehler
-- still unvollstaendig.
create or replace function public.fantasy_stat_korrektur_anwenden()
returns trigger
language plpgsql
as $$
declare v jsonb;
begin
  select jsonb_object_agg(o.feld, o.wert) into v
    from public.stat_overrides o
   where o.season = new.season
     and o.round = new.round
     and o.player_id = new.player_id;
  if v is null then return new; end if;
  new := jsonb_populate_record(new, to_jsonb(new) || v);
  return new;
end$$;

drop trigger if exists player_match_stats_korrektur on public.player_match_stats;
create trigger player_match_stats_korrektur
  before insert or update on public.player_match_stats
  for each row execute function public.fantasy_stat_korrektur_anwenden();

-- ---------------------------------------------------------------------------
-- 3) Der konkrete Fall
-- ---------------------------------------------------------------------------
-- Belegt durch die Spielberichte: Karetsas legte in der 9. fuer Guirassy auf,
-- Konstantelias erzielte in der 45.+1 das 2:0 und verdrehte sich spaeter das
-- Knie. Ein Eigentor gab es nicht.
insert into public.stat_overrides (season, round, player_id, feld, wert, grund)
values
  (2026, 1, 'sportmonks:37336765', 'goals', 1,
   'Konstantelias erzielte das 2:0 (45.+1); Sportmonks verbucht es als Eigentor Bornauw'),
  (2026, 1, 'sportmonks:4536574', 'goals', 0,
   'Bornauw hat nicht getroffen — der HSV erzielte kein Tor'),
  (2026, 1, 'sportmonks:4536574', 'own_goals', 0,
   'Es war kein Eigentor, sondern ein Treffer von Konstantelias')
on conflict (season, round, player_id, feld) do update
  set wert = excluded.wert, grund = excluded.grund;

-- Bestand einmal durch den Trigger schicken.
update public.player_match_stats set updated_at = updated_at
 where season = 2026 and round = 1
   and player_id in ('sportmonks:37336765', 'sportmonks:4536574');
