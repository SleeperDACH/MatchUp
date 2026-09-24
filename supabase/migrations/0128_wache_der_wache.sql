-- **Wer bewacht die Wache?**
--
-- 0127 lässt die Sync-Wache reparieren und klingeln — aber nur, solange sie
-- selbst läuft. Steht der Cron, ist die Datenbank nicht erreichbar oder bricht
-- `pruefe_sync()` mit einem Fehler ab, kommt **kein** Push, und das sieht
-- genauso aus wie Ruhe.
--
-- Deshalb ein Lebenszeichen, das von **außerhalb** abgefragt wird: Ein
-- GitHub-Workflow (`.github/workflows/wache-der-wache.yml`) fragt alle 30
-- Minuten `wache_lebenszeichen()` ab und schickt selbst einen Push, wenn die
-- Antwort ausbleibt oder die Wache seit über 30 Minuten nicht mehr
-- durchgelaufen ist. Außerhalb deshalb, weil ein Wächter in derselben
-- Datenbank mit ihr zusammen ausfiele.

create table if not exists public.wache_puls (
  id           boolean     primary key default true check (id),
  letzter_lauf timestamptz not null
);

alter table public.wache_puls enable row level security;
-- Ohne Policy: gelesen wird ausschließlich über `wache_lebenszeichen()`.

insert into public.wache_puls (id, letzter_lauf)
values (true, now())
on conflict (id) do nothing;

-- Der Puls wird **nach** `pruefe_sync()` geschrieben. Bricht die Wache mit
-- einem Fehler ab, rollt die Anweisung zurück und der Puls bleibt stehen —
-- genau das soll der Wächter draußen sehen. Ein Zeitstempel, den der Cron vor
-- der Prüfung setzt, hätte eine abstürzende Wache als gesund gemeldet.
create or replace function public.wache_lauf()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_neu integer;
begin
  v_neu := public.pruefe_sync();
  update public.wache_puls set letzter_lauf = now() where id;
  return v_neu;
end $$;

revoke execute on function public.wache_lauf() from public, anon, authenticated;

-- Öffentlich lesbar, und das ist Absicht: Der Wächter läuft außerhalb und hat
-- nur den Publishable-Key. Verraten wird eine Sekundenzahl, nichts weiter.
create or replace function public.wache_lebenszeichen()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'wache_vor_sekunden', extract(epoch from now() - letzter_lauf)::int,
    'jetzt', now()
  )
    from public.wache_puls
   where id;
$$;

revoke execute on function public.wache_lebenszeichen() from public;
grant execute on function public.wache_lebenszeichen() to anon, authenticated;

select cron.schedule(
  'sync-wache',
  '*/10 * * * *',
  $$select public.wache_lauf();$$
);
