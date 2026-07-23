-- Liga-Einladung als Direktnachricht: Eine Nachricht kann eine Fantasy-Liga
-- verlinken, die der Empfänger im Chat per Karte („Beitreten") direkt annehmen
-- kann. Beide Felder null = normale Textnachricht.
alter table public.direct_messages
  add column if not exists invite_league_id uuid,
  add column if not exists invite_code      text;
