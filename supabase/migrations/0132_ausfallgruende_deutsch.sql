-- Ausfallgruende nur noch auf Deutsch.
--
-- Gemeldet: „Warum stehen die Verletzungen auf Englisch drin, bitte nur
-- deutsch." Sportmonks liefert den Grund englisch (`/core/types/<id>`). Die
-- App uebersetzte ihn ueber eine feste Liste von 35 Gruenden, gemessen am
-- 30.08.2026; seitdem hat `sync-absences` bis zu 177 Typen gesammelt, und
-- jeder neue erschien im Wortlaut der Quelle („Torn Muscle Fiber").
--
-- **Die Uebersetzung liegt jetzt am Server**: `sideline_types.name_de`, und
-- die Sicht gibt sie als `grund_quelle` aus. Die App zeigt einen Wortlaut,
-- den ihre Liste nicht kennt, unveraendert an -- damit greift das ohne
-- Update in jeder Version.
--
-- Ein Typ, der spaeter neu dazukommt und noch keine Uebersetzung hat, wird
-- **nicht** englisch angezeigt, sondern als „Verletzung" bzw. „Sperre".
-- `sync-absences` meldet solche Typen (`ohneDeutsch`), damit sie hier
-- nachgetragen werden.

alter table public.sideline_types add column if not exists name_de text;

update public.sideline_types t
   set name_de = v.name_de
  from (values
    (1958, 'Bauchmuskelzerrung'),
    (603, 'Achillessehnen-Probleme'),
    (604, 'Achillessehnenriss'),
    (2043, 'Schultereckgelenksprengung'),
    (1952, 'Adduktorenverletzung'),
    (1938, 'Adduktorenbeschwerden'),
    (926, 'Allergische Reaktion'),
    (773, 'Angina'),
    (537, 'Sprunggelenkverletzung'),
    (1955, 'Bänderriss im Sprunggelenk'),
    (672, 'Sprunggelenkprobleme'),
    (671, 'Sprunggelenk-OP'),
    (675, 'Blinddarm-OP'),
    (595, 'Rückenverletzung'),
    (1935, 'Rückenprobleme'),
    (704, 'Knochenprellung'),
    (1974, 'Knochenödem'),
    (2089, 'Knochenstauchung'),
    (2017, 'Sprunggelenkbruch'),
    (2038, 'Jochbeinbruch'),
    (1915, 'Schlüsselbeinbruch'),
    (1916, 'Wadenbeinbruch'),
    (1973, 'Fußbruch'),
    (1986, 'Handbruch'),
    (1983, 'Kieferbruch'),
    (1985, 'Nasenbeinbruch'),
    (1953, 'Schulterbruch'),
    (1930, 'Schienbeinbruch'),
    (1966, 'Zehenbruch'),
    (794, 'Bronchitis'),
    (658, 'Prellung'),
    (896, 'Sprunggelenkprellung'),
    (2024, 'Sprunggelenkprellung'),
    (1941, 'Rückenprellung'),
    (683, 'Knieprellung'),
    (2002, 'Rippenprellung'),
    (811, 'Schleimbeutelentzündung'),
    (532, 'Wadenverletzung'),
    (661, 'Wadenprobleme'),
    (1613, 'Länderspielreise'),
    (2030, 'Kapselverletzung'),
    (2122, 'Kapselriss im Sprunggelenk'),
    (2013, 'Kapselriss'),
    (633, 'Knorpelschaden'),
    (784, 'Halswirbelverletzung'),
    (883, 'Kreislaufprobleme'),
    (652, 'Erkältung'),
    (2104, 'Wirbelsäulenstauchung'),
    (550, 'Gehirnerschütterung'),
    (538, 'Corona-Infektion'),
    (557, 'Kreuzbandverletzung'),
    (839, 'Kreuzbanddehnung'),
    (1918, 'Kreuzbandriss'),
    (853, 'Schnittwunde'),
    (600, 'Pferdekuss'),
    (2049, 'Doppelter Bänderriss'),
    (2023, 'Ellbogenbruch'),
    (755, 'Ellbogenverletzung'),
    (752, 'Gesichtsverletzung'),
    (680, 'Ermüdungsbruch'),
    (691, 'Fieber'),
    (547, 'Aufbautraining'),
    (610, 'Grippe'),
    (757, 'Lebensmittelvergiftung'),
    (1996, 'Fußprellung'),
    (549, 'Fußverletzung'),
    (558, 'Fuß-OP'),
    (646, 'Unterarmbruch'),
    (339, 'Leistenverletzung'),
    (1911, 'Leistenprobleme'),
    (548, 'Leisten-OP'),
    (2075, 'Haarriss im Fuß'),
    (535, 'Verletzung der hinteren Oberschenkelmuskulatur'),
    (1936, 'Zerrung der hinteren Oberschenkelmuskulatur'),
    (664, 'Handverletzung'),
    (630, 'Kopfverletzung'),
    (1994, 'Fersenverletzung'),
    (614, 'Bandscheibenvorfall'),
    (551, 'Hüftverletzung'),
    (605, 'Hüftprobleme'),
    (336, 'Erkrankung'),
    (1610, 'Gelbsperre'),
    (737, 'Infekt'),
    (637, 'Entzündung'),
    (2012, 'Schambeinentzündung'),
    (553, 'Leistenbruch'),
    (629, 'Verletzung'),
    (1979, 'Bauchmuskelverletzung'),
    (2021, 'Innenbandriss im Knie'),
    (1910, 'Innenbandverletzung'),
    (2047, 'Innenbanddehnung im Knie'),
    (1981, 'Innenbandriss im Sprunggelenk'),
    (1942, 'Innenbanddehnung'),
    (2081, 'Innenbandriss'),
    (2027, 'Magen-Darm-Infekt'),
    (1976, 'Knieprellung'),
    (536, 'Knieverletzung'),
    (2061, 'Innenbandriss im Knie'),
    (687, 'Knieprobleme'),
    (540, 'Knie-OP'),
    (531, 'Prellung'),
    (2083, 'Risswunde'),
    (552, 'Beinverletzung'),
    (1972, 'Bänderdehnung'),
    (640, 'Hexenschuss'),
    (1962, 'Lendenwirbelprobleme'),
    (696, 'Meniskusschaden'),
    (1971, 'Meniskusverletzung'),
    (1543, 'Meniskusriss'),
    (1968, 'Mittelhandbruch'),
    (2056, 'Mittelfußprellung'),
    (542, 'Mittelfußbruch'),
    (677, 'Leichte Prellung'),
    (2074, 'Pfeiffersches Drüsenfieber'),
    (694, 'Muskelfaserriss'),
    (554, 'Muskelverletzung'),
    (1964, 'Muskelverhärtung'),
    (2048, 'Muskelzerrung'),
    (2011, 'Muskelriss'),
    (598, 'Muskuläre Probleme'),
    (745, 'Nackenverletzung'),
    (1612, 'Keine Spielberechtigung'),
    (660, 'Nasenverletzung'),
    (659, 'Nasen-OP'),
    (1609, 'Olympische Spiele'),
    (2020, 'Außenbandprobleme'),
    (1951, 'Außenbandriss'),
    (909, 'Überdehnung der Syndesmose'),
    (714, 'Kreuzbandteilriss'),
    (2037, 'Muskelteilriss'),
    (2000, 'Patellasehnenreizung'),
    (2029, 'Patellasehnen-Probleme'),
    (2097, 'Beckenprellung'),
    (2059, 'Beckenverletzung'),
    (989, 'Beckenschiefstand'),
    (793, 'Eingeklemmter Nerv'),
    (2093, 'Schambeinprellung'),
    (1984, 'Schambeinreizung'),
    (1608, 'Rotsperre'),
    (590, 'Belastungssteuerung'),
    (2062, 'Rippenbruch'),
    (1961, 'Kahnbeinbruch'),
    (1967, 'Schienbeinprellung'),
    (1912, 'Schienbeinverletzung'),
    (545, 'Schulterverletzung'),
    (1614, 'Sonderurlaub'),
    (2031, 'Magen-Darm-Grippe'),
    (1997, 'Magenprobleme'),
    (846, 'Zerrung im Oberschenkel- und Gesäßmuskel'),
    (2025, 'Knochenstressreaktion'),
    (608, 'Operation'),
    (561, 'Sperre'),
    (1615, 'Sperre durch Sportgericht'),
    (1999, 'Syndesmosebandriss'),
    (621, 'Syndesmosebandriss'),
    (690, 'Sehnenreizung'),
    (2036, 'Sehnenriss'),
    (2079, 'Sehnenriss'),
    (798, 'Sehnenentzündung'),
    (533, 'Oberschenkelprobleme'),
    (815, 'Schien- und Wadenbeinbruch'),
    (673, 'Zehenverletzung'),
    (762, 'Mandelentzündung'),
    (1987, 'Bänderriss im Sprunggelenk'),
    (2005, 'Außenbandriss im Sprunggelenk'),
    (1929, 'Außenbandriss im Knie'),
    (1937, 'Bänderriss'),
    (2085, 'Bänderriss in der Fußwurzel'),
    (667, 'Muskelbündelriss'),
    (1946, 'Muskelfaserriss'),
    (1949, 'Muskelfaserriss im Adduktorenbereich'),
    (1939, 'Oberschenkelmuskelriss'),
    (587, 'Verletzung ohne nähere Angabe'),
    (2019, 'Wirbelverletzung'),
    (1933, 'Virusinfekt'),
    (723, 'Schleudertrauma'),
    (1611, 'Gelbsperre')
  ) as v(id, name_de)
 where t.id = v.id;

create or replace view public.player_absences_v
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
  coalesce(t.name_de,
           case when a.kategorie = 'suspended' then 'Sperre' else 'Verletzung' end)
    as grund_quelle,
  e.gespielt_am,
  'gemeldet'::text as quelle,
  null::int as runde,
  null::int as minute,
  -- „Gilt fuer die Bundesliga nicht (mehr)": drei Gruende, drei Zeilen.
  (e.gespielt_am is not null and a.seit is not null and e.gespielt_am::date > a.seit)
    or (a.kategorie = 'suspended' and a.seit is not null
        and a.seit < (select tag from saisonstart))
    or a.type_id = 1612 as ueberholt
from player_absences a
left join sideline_types t on t.id = a.type_id
left join letzter_einsatz e on e.player_id = a.player_id

union all

select
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
        -- Ein ausgeblendeter Eintrag darf die Beobachtung nicht verdecken:
        -- Wer nur „No Eligibility" traegt, gilt hier als ungemeldet.
        select 1 from player_absences a
         where a.player_id = v.player_id and a.type_id is distinct from 1612)
  -- Er hat seither gespielt.
  and coalesce(e.letzte_runde, 0) <= v.round
  -- Oder der Verein plant ihn wieder ein: Elf **oder** Bank eines spaeteren
  -- Spiels. Auf die Bank setzt niemand einen Verletzten.
  and not exists (
        select 1
          from predicted_lineups pl
          join fixtures f2 on f2.id = pl.fixture_id
         where pl.player_id = v.player_id
           and f2.kickoff > f.kickoff);

grant select on public.player_absences_v to anon, authenticated;
