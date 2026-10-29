-- Die Tippliga heißt „Globales Tippspiel" (29.10.2026, auf Ansage: „Global
-- mit in den Namen"). Nur der Name; alles andere aus 0150 bleibt.
update public.tip_rounds
   set name = 'Globales Tippspiel'
 where ist_global and name = 'MatchUp Tippliga';
