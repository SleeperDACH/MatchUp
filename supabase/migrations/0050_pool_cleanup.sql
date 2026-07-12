-- Pool-Cleanup: entfernt die alten (seed:/tsdb:) Bundesliga-Einträge, die beim
-- Sportmonks-Import (0048) FK-gesperrt zurückblieben, samt aller abhängigen
-- Daten. Danach besteht der Bundesliga-Pool nur noch aus den aktuellen
-- Sportmonks-Kadern. Bewusst destruktiv (betrifft nur die vorhandenen
-- Test-Ligen): Draft-Picks/Rosters/Queue/Waiver/Trades/alte Stats zu diesen
-- Spielern gehen verloren.

create temporary table _old_bl on commit drop as
  select id from public.players
  where id not like 'sportmonks:%'
    and club in (
      '1. FC Heidenheim 1846', '1. FC Köln', '1. FC Union Berlin',
      '1. FSV Mainz 05', 'Bayer 04 Leverkusen', 'Borussia Dortmund',
      'Borussia Mönchengladbach', 'Eintracht Frankfurt', 'FC Augsburg',
      'FC Bayern München', 'FC St. Pauli', 'Hamburger SV', 'RB Leipzig',
      'SC Freiburg', 'SV Werder Bremen', 'TSG Hoffenheim', 'VfB Stuttgart',
      'VfL Wolfsburg'
    );

-- Abhängige Zeilen zuerst (FK-Reihenfolge).
delete from public.draft_picks         where player_id     in (select id from _old_bl);
delete from public.fantasy_draft_queue where player_id     in (select id from _old_bl);
delete from public.fantasy_rosters     where player_id     in (select id from _old_bl);
delete from public.fantasy_trade_items where player_id     in (select id from _old_bl);
delete from public.fantasy_waiver_players where player_id  in (select id from _old_bl);
delete from public.fantasy_waiver_claims
  where add_player_id in (select id from _old_bl)
     or drop_player_id in (select id from _old_bl);
delete from public.player_match_stats  where player_id     in (select id from _old_bl);

-- Zum Schluss die Spieler selbst.
delete from public.players where id in (select id from _old_bl);
