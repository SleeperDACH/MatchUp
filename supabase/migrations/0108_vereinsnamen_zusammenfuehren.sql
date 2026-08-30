-- Der Spielplan und die Spieler nennen dieselben Vereine verschieden.
--
-- **Ein Fehler, den 0107 ausgeloest hat.** `players.club` traegt bewusst die
-- OpenLigaDB-Schreibweise („SV 07 Elversberg", „1. FSV Mainz 05") — so steht
-- es in `sync-squads`, wo eine feste Karte diese Namen auf Sportmonks-Team-IDs
-- abbildet, und die App braucht sie so, weil sie ihren Spielplan direkt bei
-- OpenLigaDB holt. Der Sportmonks-Spielplan schreibt dieselben Vereine
-- kuerzer: „Elversberg", „FSV Mainz 05".
--
-- Solange **beide** Quellen in `fixtures` standen, fand
-- `fantasy_spieler_anpfiff` fuer jeden Spieler eine Zeile — ueber die
-- OpenLigaDB-Zeile. Mit deren Loeschung (0107) riss der Join fuer **sieben**
-- der achtzehn Vereine: Koeln, Union Berlin, Mainz, Schalke, Paderborn,
-- Elversberg, Werder. Fuer deren Spieler lieferte die Funktion `null`, und
-- weil „kein Spiel gefunden" als „nicht gesperrt" gilt, galten sie als frei —
-- der Antrag wurde mit *„Spieler ist frei – du kannst ihn direkt holen"*
-- abgelehnt, waehrend die App den Waiver-Knopf zeigte.
--
-- **Genau die Sorte Fehler, die diese Datei sonst beschreibt:** Ein Zustand
-- „ich finde nichts" sah aus wie „alles in Ordnung".
--
-- Verglichen wird deshalb nicht mehr der Name, sondern seine **kanonische
-- Form**: ohne Ziffern, ohne Punkte, ohne die Vereinsformen (FC, SV, SC, …).
-- Nachgemessen an allen 19 Vereinen im Kaderbestand: 18 finden genau einen
-- Spielplan-Verein, AS Monaco keinen (richtig, er spielt nicht in der Liga),
-- und weder bei den Spielern noch im Spielplan fallen zwei Vereine auf
-- dieselbe Form.

create or replace function public.fantasy_verein_kanonisch(p_name text)
returns text language sql immutable as $$
  select btrim(regexp_replace(
    regexp_replace(
      regexp_replace(lower(coalesce(p_name, '')), '[0-9.]', '', 'g'),
      '(^|\s)(fc|sv|sc|tsg|vfb|vfl|fsv|tsv|bsc|spvgg|msv|kfc)(\s|$)', ' ', 'g'),
    '\s+', ' ', 'g'));
$$;

create or replace function public.fantasy_spieler_anpfiff(
  p_season int, p_round int, p_player_id text)
returns timestamptz language sql stable security definer set search_path to 'public' as $$
  select min(f.kickoff)
    from players p
    join fixtures f
      on f.season = p_season and f.round = p_round
     and f.league_id = 'bundesliga'
     and f.id like 'sportmonks:%'
     and (public.fantasy_verein_kanonisch(f.home_name)
            = public.fantasy_verein_kanonisch(p.club)
       or public.fantasy_verein_kanonisch(f.away_name)
            = public.fantasy_verein_kanonisch(p.club))
   where p.id = p_player_id;
$$;

-- **Damit es beim naechsten Mal auffaellt.** Ein Verein, dessen Spieler in
-- Kadern stehen, der aber im Spielplan nicht vorkommt, ist entweder neu
-- aufgestiegen oder anders geschrieben — beides muss man sehen, statt es an
-- abgelehnten Antraegen zu merken.
create or replace view public.vereine_ohne_spielplan
with (security_invoker = true) as
  select distinct p.club,
         public.fantasy_verein_kanonisch(p.club) as kanonisch
    from players p
    join fantasy_rosters r on r.player_id = p.id
   where p.club is not null
     and not exists (
       select 1 from fixtures f
        where f.league_id = 'bundesliga'
          and f.id like 'sportmonks:%'
          and (public.fantasy_verein_kanonisch(f.home_name)
                 = public.fantasy_verein_kanonisch(p.club)
            or public.fantasy_verein_kanonisch(f.away_name)
                 = public.fantasy_verein_kanonisch(p.club)));
