-- Die Abgaenge nachtragen, die anderswo festgehalten sind.
--
-- 0096 hat nur Zugaenge zurueckgefuellt, mit der Begruendung, Abgaenge seien
-- nirgends festgehalten und duerften nicht erfunden werden. **Der erste Teil
-- war falsch.** Sie stehen sehr wohl da, nur nicht in `fantasy_rosters`:
--
--   * **Trades** — `fantasy_trade_items` haelt fest, wer welchen Spieler
--     abgegeben hat. ID-basiert, vollstaendig.
--   * **Gewonnene Waiver-Antraege** — `fantasy_waiver_claims.drop_player_id`.
--     ID-basiert, vollstaendig.
--   * **Free Agency und reine Drops** — die Systemnachricht im Liga-Chat
--     („✅ X hat Y verpflichtet und Z abgegeben.").
--
-- Der dritte Weg klingt nach Raten, ist es aber nicht, und zwar aus zwei
-- nachgemessenen Gruenden:
--
--   1. **Die Nachricht entsteht in derselben Transaktion** wie die Bewegung
--      (`fantasy_post_system_message` wird aus `fantasy_add_free_agent`
--      heraus gerufen). Ihr `created_at` ist deshalb exakt der Zeitstempel des
--      Zugangs — geprueft: `2026-08-29 11:54:40.781945` steht auf beiden.
--   2. **Es gibt keine mehrdeutigen Spielernamen** im Pool (gezaehlt: null
--      Namen kommen zweimal vor). Name -> ID ist damit eindeutig.
--
-- Und die Rekonstruktion prueft sich selbst: Bei „X verpflichtet und Y
-- abgegeben" muss zu diesem Zeitstempel eine Zugangszeile fuer **genau diesen
-- X** existieren. Passt sie nicht, wird die Zeile uebersprungen statt geraten.
--
-- Was danach fehlt, fehlt wirklich: Drops aus einer Zeit vor den
-- Systemnachrichten, und Admin-Korrekturen. Die bleiben aus.

-- ---------------------------------------------------------------------------
-- 1) Trades
-- ---------------------------------------------------------------------------
-- Wer in einem Trade abgibt, steht in `fantasy_trade_items.giver`. Den
-- Zeitpunkt liefert die zugehoerige Zugangszeile der Gegenseite — so fallen
-- Abgang und Zugang auf dieselbe Zeit und werden in der App ein Vorgang.
insert into public.fantasy_roster_moves
  (league_id, manager_id, player_id, richtung, weg, passiert_am)
select distinct t.league_id, it.giver, it.player_id, 'abgang', 'trade',
       z.passiert_am
  from public.fantasy_trade_items it
  join public.fantasy_trades t on t.id = it.trade_id
  join public.fantasy_roster_moves z
    on z.league_id = t.league_id
   and z.player_id = it.player_id
   and z.richtung = 'zugang'
   and z.weg = 'trade'
   and z.manager_id <> it.giver
 where not exists (
   select 1 from public.fantasy_roster_moves m
    where m.league_id = t.league_id and m.player_id = it.player_id
      and m.manager_id = it.giver and m.richtung = 'abgang');

-- ---------------------------------------------------------------------------
-- 2) Gewonnene Waiver-Antraege
-- ---------------------------------------------------------------------------
insert into public.fantasy_roster_moves
  (league_id, manager_id, player_id, richtung, weg, passiert_am)
select distinct c.league_id, c.manager_id, c.drop_player_id, 'abgang', null,
       z.passiert_am
  from public.fantasy_waiver_claims c
  join public.fantasy_roster_moves z
    on z.league_id = c.league_id
   and z.manager_id = c.manager_id
   and z.player_id = c.add_player_id
   and z.richtung = 'zugang'
 where c.status = 'won'
   and c.drop_player_id is not null
   and not exists (
     select 1 from public.fantasy_roster_moves m
      where m.league_id = c.league_id and m.player_id = c.drop_player_id
        and m.manager_id = c.manager_id and m.richtung = 'abgang'
        and m.passiert_am = z.passiert_am);

-- ---------------------------------------------------------------------------
-- 3) Free Agency: „verpflichtet und ... abgegeben"
-- ---------------------------------------------------------------------------
-- Der Manager kommt **nicht** aus dem Nachrichtentext, sondern aus der
-- Zugangszeile — ein Nutzername waere die schwaechere Zuordnung. Der Text
-- liefert nur die beiden Spielernamen, und der erste muss zur Zugangszeile
-- passen, sonst wird nichts eingetragen.
with geparst as (
  select m.league_id,
         m.created_at,
         (regexp_match(m.body,
            '^✅ .+? hat (.+?) verpflichtet und (.+?) abgegeben\.$'))[1] as rein,
         (regexp_match(m.body,
            '^✅ .+? hat (.+?) verpflichtet und (.+?) abgegeben\.$'))[2] as raus
    from public.fantasy_league_messages m
   where m.body like '✅%verpflichtet und%abgegeben.'
)
insert into public.fantasy_roster_moves
  (league_id, manager_id, player_id, richtung, weg, passiert_am)
select distinct g.league_id, z.manager_id, praus.id, 'abgang', null, g.created_at
  from geparst g
  join public.players prein on prein.name = g.rein
  join public.players praus on praus.name = g.raus
  -- Die Selbstpruefung: zu dieser Zeit muss der genannte Zugang stehen.
  join public.fantasy_roster_moves z
    on z.league_id = g.league_id
   and z.player_id = prein.id
   and z.richtung = 'zugang'
   and z.passiert_am = g.created_at
 where g.rein is not null and g.raus is not null
   and not exists (
     select 1 from public.fantasy_roster_moves m
      where m.league_id = g.league_id and m.player_id = praus.id
        and m.manager_id = z.manager_id and m.richtung = 'abgang'
        and m.passiert_am = g.created_at);

-- ---------------------------------------------------------------------------
-- 4) Reine Drops: „🔻 X hat Y abgegeben."
-- ---------------------------------------------------------------------------
-- Hier gibt es keine Zugangszeile zum Abgleich, also muss der Nutzername
-- herhalten. Er wird gegen `profiles` aufgeloest und muss **Mitglied dieser
-- Liga** sein; findet sich kein eindeutiges Profil, bleibt die Zeile aus.
with geparst as (
  select m.league_id,
         m.created_at,
         (regexp_match(m.body, '^🔻 (.+?) hat (.+?) abgegeben\.$'))[1] as wer,
         (regexp_match(m.body, '^🔻 (.+?) hat (.+?) abgegeben\.$'))[2] as raus
    from public.fantasy_league_messages m
   where m.body like '🔻%abgegeben.'
)
insert into public.fantasy_roster_moves
  (league_id, manager_id, player_id, richtung, weg, passiert_am)
select distinct g.league_id, pr.id, p.id, 'abgang', null, g.created_at
  from geparst g
  join public.players p on p.name = g.raus
  join public.profiles pr on pr.username = g.wer
  join public.fantasy_league_members lm
    on lm.league_id = g.league_id and lm.user_id = pr.id
 where g.wer is not null and g.raus is not null
   and not exists (
     select 1 from public.fantasy_roster_moves m
      where m.league_id = g.league_id and m.player_id = p.id
        and m.manager_id = pr.id and m.richtung = 'abgang'
        and m.passiert_am = g.created_at);
