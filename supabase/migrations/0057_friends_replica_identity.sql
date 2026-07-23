-- Realtime für Freundschaften: Annehmen (UPDATE) und Ablehnen/Entfernen
-- (DELETE) müssen bei den Beteiligten sofort ankommen. Für UPDATE/DELETE-
-- Events unter RLS braucht Supabase Realtime die vollständige alte Zeile —
-- sonst werden die Ereignisse nicht zuverlässig ausgeliefert und die Liste
-- aktualisiert sich beim Empfänger nicht.
alter table public.friendships replica identity full;
