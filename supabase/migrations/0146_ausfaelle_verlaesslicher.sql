-- Ausfälle verlässlicher (27.10.2026, auf Ansage: „Bekommen wir das hin, dass
-- die Verletzungsmeldungen verlässlich sind?").
--
-- Nachgemessen vor dieser Migration:
--
-- * **Veraltete Meldungen blieben stehen.** Die Quelle schließt einen Ausfall
--   oft nicht; `ueberholt` griff nur über eigene Bundesliga-Minuten. Robin
--   Zentner stand seit dem 14.09. als verletzt da und am 27.10. im offiziellen
--   Kader. Neu: Wer nach dem Verletzungstag in einem **offiziell gemeldeten**
--   Spieltagskader steht (`predicted_lineups.bestaetigt`, Startelf oder Bank,
--   0118), ist nicht mehr verletzt. Gemeldet heißt: Der Verein hat ihn
--   eingeplant — dieselbe Begründung wie 0124 für die abgeleiteten Einträge.
--   Verglichen wird der **Tag** in deutscher Zeit, damit eine Verletzung im
--   Spiel selbst (Beginn = Spieltag) sich nicht sofort wieder aufhebt.
-- * **„Verletzt ausgewechselt" wurde von jeder alten Meldung verschluckt.**
--   Die Sicht blendete die Beobachtung aus, sobald es für den Spieler
--   *irgendeinen* Eintrag gab — auch eine alte Sperre oder eine längst
--   überholte Verletzung. Jetzt nur noch, wenn eine Verletzung **zum selben
--   Vorfall** gemeldet ist (Beginn ab dem Tag vor dem Spiel).
-- * Der Grund der Beobachtung steht deutsch in der Sicht (die App setzt ihn
--   ohnehin selbst, aber nichts Englisches soll herauskommen).
-- * Zwei Typen ohne Übersetzung.
-- * **Takt 15 statt 60 Minuten** — zwei Requests je Lauf.
--
-- Die Function `sync-absences` löscht außerdem nicht mehr alles, wenn die
-- Quelle eine leere oder unvollständige Antwort liefert (siehe dort).

create or replace view public.player_absences_v
with (security_invoker = true) as
 WITH letzter_einsatz AS (
         SELECT s.player_id,
            max(f.kickoff) AS gespielt_am,
            max(s.round) AS letzte_runde
           FROM ((player_match_stats s
             JOIN players p ON ((p.id = s.player_id)))
             JOIN fixtures f ON (((f.season = s.season) AND (f.round = s.round) AND (f.league_id = 'bundesliga'::text) AND ((fantasy_verein_kanonisch(f.home_name) = fantasy_verein_kanonisch(p.club)) OR (fantasy_verein_kanonisch(f.away_name) = fantasy_verein_kanonisch(p.club))))))
          WHERE (s.minutes > 0)
          GROUP BY s.player_id
        ), karte AS (
         SELECT s.player_id,
            (f.kickoff)::date AS tag,
            s.yellow,
            s.second_yellow,
            s.red
           FROM ((player_match_stats s
             JOIN players p ON ((p.id = s.player_id)))
             JOIN fixtures f ON (((f.season = s.season) AND (f.round = s.round) AND (f.league_id = 'bundesliga'::text) AND ((fantasy_verein_kanonisch(f.home_name) = fantasy_verein_kanonisch(p.club)) OR (fantasy_verein_kanonisch(f.away_name) = fantasy_verein_kanonisch(p.club))))))
          WHERE (((s.yellow + s.second_yellow) + s.red) > 0)
        ), saisonstart AS (
         SELECT (min(f.kickoff))::date AS tag
           FROM fixtures f
          WHERE ((f.league_id = 'bundesliga'::text) AND (f.season = ( SELECT max(fixtures.season) AS max
                   FROM fixtures
                  WHERE (fixtures.league_id = 'bundesliga'::text))))
        )
 SELECT a.id,
    a.player_id,
    a.kategorie,
    a.type_id,
    a.seit,
    a.bis,
    a.spiele_verpasst,
    a.updated_at,
    COALESCE(t.name_de,
        CASE
            WHEN (a.kategorie = 'suspended'::text) THEN 'Sperre'::text
            ELSE 'Verletzung'::text
        END) AS grund_quelle,
    e.gespielt_am,
    'gemeldet'::text AS quelle,
    NULL::integer AS runde,
    NULL::integer AS minute,
    (((e.gespielt_am IS NOT NULL) AND (a.seit IS NOT NULL) AND ((e.gespielt_am)::date > a.seit)) OR ((a.kategorie = 'suspended'::text) AND (a.seit IS NOT NULL) AND (a.seit < ( SELECT saisonstart.tag
           FROM saisonstart))) OR (a.type_id = 1612) OR ((a.type_id = ANY (ARRAY[1608, 1610, 1611])) AND (a.seit IS NOT NULL) AND (NOT (EXISTS ( SELECT 1
           FROM karte k
          WHERE ((k.player_id = a.player_id) AND ((k.tag >= (a.seit - 10)) AND (k.tag <= (a.seit + 1))) AND
                CASE a.type_id
                    WHEN 1608 THEN (k.red > 0)
                    WHEN 1610 THEN ((k.second_yellow > 0) OR (k.red > 0))
                    ELSE (k.yellow > 0)
                END))))) OR ((a.kategorie = 'injury'::text) AND (a.seit IS NOT NULL) AND (EXISTS ( SELECT 1
           FROM (predicted_lineups pl
             JOIN fixtures f3 ON ((f3.id = pl.fixture_id)))
          WHERE ((pl.player_id = a.player_id) AND pl.bestaetigt AND (((f3.kickoff AT TIME ZONE 'Europe/Berlin'::text))::date > a.seit)))))) AS ueberholt
   FROM ((player_absences a
     LEFT JOIN sideline_types t ON ((t.id = a.type_id)))
     LEFT JOIN letzter_einsatz e ON ((e.player_id = a.player_id)))
UNION ALL
 SELECT ('-1000000000'::integer - ((v.season * 100) + v.round)) AS id,
    v.player_id,
    'injury'::text AS kategorie,
    NULL::integer AS type_id,
    (f.kickoff)::date AS seit,
    NULL::date AS bis,
    NULL::integer AS spiele_verpasst,
    v.erkannt_am AS updated_at,
    'Verletzt ausgewechselt'::text AS grund_quelle,
    e.gespielt_am,
    'ausgewechselt'::text AS quelle,
    v.round AS runde,
    v.minute,
    false AS ueberholt
   FROM ((verletzt_ausgewechselt v
     JOIN fixtures f ON ((f.id = v.fixture_id)))
     LEFT JOIN letzter_einsatz e ON ((e.player_id = v.player_id)))
  WHERE ((NOT (EXISTS ( SELECT 1
           FROM player_absences a
          WHERE ((a.player_id = v.player_id) AND (a.kategorie = 'injury'::text) AND ((a.seit IS NULL) OR (a.seit >= ((f.kickoff)::date - 1))))))) AND (COALESCE(e.letzte_runde, 0) <= v.round) AND (NOT (EXISTS ( SELECT 1
           FROM (predicted_lineups pl
             JOIN fixtures f2 ON ((f2.id = pl.fixture_id)))
          WHERE ((pl.player_id = v.player_id) AND (f2.kickoff > f.kickoff))))));

update public.sideline_types set name_de = 'Zahnoperation' where id = 722 and name_de is null;
update public.sideline_types set name_de = 'Nackenprellung' where id = 1017 and name_de is null;

select cron.alter_job(
  (select jobid from cron.job where jobname = 'sync-absences'),
  schedule := '*/15 * * * *'
);
