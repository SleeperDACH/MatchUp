-- Verletzt ausgewechselt: die Quelle meldet den Ausfall nicht immer.
--
-- Gemeldet: „Filippo Mane wurde im zweiten Spiel nach 32 Minuten
-- ausgewechselt, mit einer Oberschenkelverletzung. Solche Fehler duerfen nicht
-- passieren. Ich kann nicht bei jedem Spieler manuell nachforschen."
--
-- Nachgemessen ueber die ganze Saison 2026 (18 gespielte Partien, 173
-- Wechsel): **neun** Auswechslungen tragen `injured: true`, und **fuenf**
-- dieser Spieler hatten keinen einzigen Eintrag in `player_absences` --
-- Brackelmann, Dinkci, Mane, Moffi, Lemperle. Die Ausfallliste von Sportmonks
-- (`include=sidelined`) ist bei Stammspielern gut gepflegt und bei allen
-- anderen loechrig; sie ist als alleinige Quelle nicht tragfaehig.
--
-- **Die zweite Quelle kostet keinen einzigen Request.** `sync-stats` holt
-- ohnehin `/fixtures/multi/{ids}?include=lineups.details.type;events`, und in
-- genau diesen Ereignissen steht das Feld schon drin:
--
--   type_id 18, related_player_id = der Spieler, der herausgeht,
--   minute = 32, injured = true
--
-- Diese Tabelle haelt das Ereignis fest. Sie behauptet **keine Diagnose** --
-- nur, dass jemand verletzt vom Platz ging. Was daraus fuer die Anzeige folgt,
-- entscheidet die Sicht darunter.
create table if not exists public.verletzt_ausgewechselt (
  season      int  not null,
  round       int  not null,
  player_id   text not null references public.players(id) on delete cascade,
  fixture_id  text not null,
  minute      int,
  erkannt_am  timestamptz not null default now(),
  primary key (season, round, player_id)
);

alter table public.verletzt_ausgewechselt enable row level security;

drop policy if exists "Ausfaelle sind fuer alle lesbar"
  on public.verletzt_ausgewechselt;
create policy "Ausfaelle sind fuer alle lesbar"
  on public.verletzt_ausgewechselt for select using (true);

-- Geschrieben wird ausschliesslich von `sync-stats` (Service-Role).

-- ---------------------------------------------------------------------------
-- Die Sicht fuehrt beide Quellen zusammen.
--
-- Aufbau wie gehabt, plus zwei Spalten: `quelle` sagt, woher die Auskunft
-- kommt, `runde` traegt den Spieltag der Auswechslung. Der Client
-- unterscheidet daran den Wortlaut -- eine Vermutung darf nicht aussehen wie
-- eine Meldung.
--
-- **Ein abgeleiteter Eintrag loest sich von selbst auf.** Er gilt nur, solange
-- der Spieler seither in keinem spaeteren Spieltag Minuten gemacht hat. Wer
-- am naechsten Wochenende wieder auf dem Platz steht, hat keinen Ausfall mehr
-- -- dieselbe Logik wie `ueberholt` bei der gemeldeten Quelle, nur andersherum
-- angewandt.
--
-- **Die gemeldete Quelle gewinnt.** Steht ein Spieler ohnehin in
-- `player_absences`, taucht er nicht zusaetzlich als abgeleiteter Eintrag auf;
-- die Meldung kennt den Grund, das Ereignis nur die Tatsache.
drop view if exists public.player_absences_v;

create view public.player_absences_v
with (security_invoker = true) as
with letzter_einsatz as (
  select s.player_id, max(f.kickoff) as gespielt_am, max(s.round) as letzte_runde
    from player_match_stats s
    join players p on p.id = s.player_id
    join fixtures f
      on f.season = s.season
     and f.round = s.round
     and f.league_id = 'bundesliga'
     and (fantasy_verein_kanonisch(f.home_name) = fantasy_verein_kanonisch(p.club)
       or fantasy_verein_kanonisch(f.away_name) = fantasy_verein_kanonisch(p.club))
   where s.minutes > 0
   group by s.player_id
), saisonstart as (
  select min(f.kickoff)::date as tag
    from fixtures f
   where f.league_id = 'bundesliga'
     and f.season = (select max(season) from fixtures where league_id = 'bundesliga')
)
select
  a.id,
  a.player_id,
  a.kategorie,
  a.type_id,
  a.seit,
  a.bis,
  a.spiele_verpasst,
  a.updated_at,
  t.name as grund_quelle,
  e.gespielt_am,
  'gemeldet'::text as quelle,
  null::int as runde,
  null::int as minute,
  (e.gespielt_am is not null and a.seit is not null and e.gespielt_am::date > a.seit)
    or (a.kategorie = 'suspended' and a.seit is not null
        and a.seit < (select tag from saisonstart)) as ueberholt
from player_absences a
left join sideline_types t on t.id = a.type_id
left join letzter_einsatz e on e.player_id = a.player_id

union all

select
  -- Eigener Zahlenraum, damit die Schluessel beider Quellen sich nie
  -- ueberschneiden: Der Client entdoppelt ueber `id`.
  -1000000000 - (v.season * 100 + v.round) as id,
  v.player_id,
  'injury'::text as kategorie,
  null::int as type_id,
  f.kickoff::date as seit,
  null::date as bis,
  null::int as spiele_verpasst,
  v.erkannt_am as updated_at,
  'Substituted Off Injured'::text as grund_quelle,
  e.gespielt_am,
  'ausgewechselt'::text as quelle,
  v.round as runde,
  v.minute,
  false as ueberholt
from verletzt_ausgewechselt v
join fixtures f on f.id = v.fixture_id
left join letzter_einsatz e on e.player_id = v.player_id
where not exists (
        select 1 from player_absences a where a.player_id = v.player_id)
  and coalesce(e.letzte_runde, 0) <= v.round;

grant select on public.player_absences_v to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Wache, gleiche Bauart wie `stats_widersprueche` und `vereine_ohne_spielplan`:
-- Wer verletzt vom Platz ging, ohne dass die Quelle einen Ausfall meldet.
-- Heute waeren das fuenf. Steht hier etwas, ist die Ausfallliste luecken-
-- haft -- und man sieht es hier, statt es von einem Nutzer zu erfahren.
create or replace view public.ausfaelle_ohne_meldung
with (security_invoker = true) as
select v.season, v.round, v.player_id, p.name, p.club, v.minute
  from verletzt_ausgewechselt v
  join players p on p.id = v.player_id
 where not exists (
   select 1 from player_absences a where a.player_id = v.player_id);

grant select on public.ausfaelle_ohne_meldung to anon, authenticated;
